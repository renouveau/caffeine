// SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
// SPDX-License-Identifier: MIT

// This file is part of Renouveau Caffeine, available under the MIT license.
// https://github.com/renouveau/caffeine

#nullable enable

using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;

namespace Renouveau.Caffeine.PlatformPowerRequests
{
  internal sealed class Win32 : PowerRequest
  {
    /// <summary>
    /// Creates a power request for Windows XP or later.
    /// </summary>
    internal new static Win32 Create(PowerRequestFlags preferred, PowerRequestFlags minimum)
    {
      const PowerRequestFlags Supported = (PowerRequestFlags.DoNotIdleSleep | PowerRequestFlags.DoNotIdleDisplay | PowerRequestFlags.DoNotSleep);
      minimum &= ~Supported;
      if (minimum != PowerRequestFlags.None)
        throw new PowerRequestException("The following power request(s) included in '" + nameof(minimum) + "' is/are not supported on Windows: " + minimum.ToString());
      // Always use `Win32` on Windows (instead of `NoOp` sometimes)
      // to be friendly with devirtualization.
      return new Win32(preferred & Supported);
    }

    private WorkerThreadSite? site_;

    private Win32(PowerRequestFlags flags)
    {
      try
      {
        Interlocked.Exchange(ref flags_, (int)(uint)flags);
        Interlocked.Exchange(ref site_, null);
        if (flags == PowerRequestFlags.None)
        {
          Dispose();
          // ^^^ The only interesting effect is it suppresses finalization of `this`.
          return;
        }
        // Create the worker and wait for its initial `SetThreadExecutionState`.
        // Currently, all supported flags coincide with its Win32 API integral values.
        WorkerThreadSite site = new WorkerThreadSite((uint)flags);
        Interlocked.Exchange(ref site_, site);
        site.WorkerThread.Start(site);
        bool failed;
        int win32err;
        lock (site)
        {
          while (site.WorkerThreadStatus == 0)
            Monitor.Wait(site);
          failed = (site.WorkerThreadStatus < 0);
          win32err = site.Win32ErrorCode;
        }
        if (failed)
          throw new Win32Exception(win32err);
      }
      catch (Exception ex)
      {
        Dispose();
        throw new PowerRequestException("An exception occurred when making a power request to Windows.", ex);
      }
      finally
      {
        // Robustly prevent finalization before the constructor is about to return.
        // If JIT knew Win32 and multi-threaded code *too* well, it could infer that
        // (for certainty, say when `flags` is `DoNotIdleDisplay` to avoid complications with `DoNotSleep`)
        // `this` is unused after `site.WorkerThread.Start(site)` succeeds,
        // as the remaining code will not fail
        // (so `this.Dispose()` in `catch` becomes unreachable),
        // so it could choose to run the finalizer before the constructor enters
        // the critical section awaiting the initial call to `SetThreadExecutionState`.
        // That race would be very bad!
        GC.KeepAlive(this);
      }
    }

    private protected override void Dispose(bool disposing)
    {
      Interlocked.Exchange(ref flags_, 0);
      WorkerThreadSite? site = Interlocked.Exchange(ref site_, null);
      if (site is null)
        return;
      // .NET Framework:
      // When the finalizer is called for shutdown / AppDomain unload,
      // the worker thread, if executing, is aborted, which could happen
      // in the implicit `finally` right before exiting from monitor `site`.
      // If we attempt to enter `site` below, we deadlock.
      // Also, upon shutdown / AppDomain unload, we might be racing with
      // the half-run aborted constructor call, so let's just back out.
      if (Environment.HasShutdownStarted)
        return;
      // .NET Core / .NET 5+:
      // The runtime does not attempt finalization upon process exit
      // and non-current threads cannot be aborted via `Thread.Abort`.
      // There is no danger of deadlock below.
      lock (site)
      {
        site.ShouldExit = true;
        // Notify the worker to exit.
        Monitor.PulseAll(site);
      }
    }

    /// <summary>
    /// It's important to use a separate object as the site seen by the thread method,
    /// as otherwise the thread method would keep the outer <c><see cref="Win32"/></c> power request object alive,
    /// which then would never become eligible for finalization / garbage collection
    /// if the client fails to call <c><see cref="IDisposable.Dispose()"/></c>.
    /// </summary>
    private sealed class WorkerThreadSite
    {
#pragma warning disable SYSLIB1054 // There's no marshaling so LibraryImport is pointless.
      [DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
      [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
      private static extern uint SetThreadExecutionState(uint esFlags);
#pragma warning restore SYSLIB1054

      internal readonly uint BareFlags;
      internal bool ShouldExit;
      internal int WorkerThreadStatus;
      internal int Win32ErrorCode;
      internal readonly Thread WorkerThread;

      internal WorkerThreadSite(uint flags)
      {
        BareFlags = flags;
        ShouldExit = false;
        WorkerThreadStatus = 0;
        Win32ErrorCode = 0;
        WorkerThread = new Thread(ParamThreadStart) { IsBackground = true };
      }

      private static readonly ParameterizedThreadStart ParamThreadStart = WorkerMethod;

      private static void WorkerMethod(object? obj)
      {
        const uint EsContinuous = 0x80000000u;
        WorkerThreadSite site = (WorkerThreadSite)obj!;
        lock (site)
        {
          // Apply the flags and save the error code.
          uint applying = site.BareFlags;
          _ = SetThreadExecutionState(applying | EsContinuous);
          int win32err = Marshal.GetLastWin32Error();
          // Check that the flags are indeed applied.
          uint applied = SetThreadExecutionState(applying | EsContinuous);
          if ((applied & applying) == applying)
          {
            site.WorkerThreadStatus = 1;
            // Notify the success of `SetThreadExecutionState`.
            // This causes the creator to return from the constructor.
            Monitor.PulseAll(site);
            // Wait for instruction to exit.
            while (!site.ShouldExit)
              Monitor.Wait(site);
          }
          else
          {
            site.WorkerThreadStatus = -1;
            site.Win32ErrorCode = win32err;
            // Notify the failure of `SetThreadExecutionState`.
            // This causes the creator to throw an exception.
            Monitor.PulseAll(site);
            // Cancel the power request immediately.
          }
          _ = SetThreadExecutionState(EsContinuous);
        }
      }
    }
  }
}
