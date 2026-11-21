// SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
// SPDX-License-Identifier: MIT

// This file is part of Renouveau Caffeine, available under the MIT license.
// https://github.com/renouveau/caffeine

#nullable enable

using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Runtime.ConstrainedExecution;
using System.Runtime.InteropServices;
using System.Threading;

#pragma warning disable SYSLIB0004 // We need CER in .NET Framework to guard against thread aborts.
#pragma warning disable CA2219 // We need to `throw` from a reliable `finally`.

namespace Renouveau.Caffeine.PlatformPowerRequests
{
  internal sealed class Win32 : PowerRequest
  {
    private protected sealed override void PreventOutsiders() { }

    /// <summary>
    /// Creates a power request for Windows 7 or later.
    /// </summary>
    internal new static Win32 Create(string reason, PowerRequestFlags preferred, PowerRequestFlags minimum)
    {
      const PowerRequestFlags Supported = (PowerRequestFlags.DoNotIdleSleep | PowerRequestFlags.DoNotIdleDisplay | PowerRequestFlags.DoNotSleep);
      minimum &= ~Supported;
      if (minimum != PowerRequestFlags.None)
        throw new PowerRequestException("The following power request(s) included in '" + nameof(minimum) + "' is/are not supported on Windows: " + minimum.ToString());
      // Always use `Win32` on Windows (instead of `NoOp` sometimes)
      // to be friendly with devirtualization.
      return new Win32(reason, preferred & Supported);
    }

    private PowerRequestHandle? handle_;

    private unsafe Win32(string reason, PowerRequestFlags flags) : base(reason)
    {
      if (flags == PowerRequestFlags.None)
      {
        Dispose();
        return;
      }
      try
      {
        PowerRequestHandle handle = new PowerRequestHandle();
        Interlocked.Exchange(ref handle_, handle);
        IntPtr h;
        fixed (char* preason = reason)
        {
          PowerRequestHandle.SimpleReasonContext context = new PowerRequestHandle.SimpleReasonContext(preason);
          RuntimeHelpers.PrepareConstrainedRegions();
          // Ensures that the handle ownership is transferred to the critical finalizer object.
          try
          {
          }
          finally
          {
            h = PowerRequestHandle.PowerCreateRequest(&context);
            Interlocked.Exchange(ref handle.Handle, h);
          }
        }
        if (h == default || h == (IntPtr)(-1))
          goto Throw;
        if ((flags & PowerRequestFlags.DoNotIdleSleep) != default && PowerRequestHandle.PowerSetRequest(h, PowerRequestHandle.PowerRequestType.SystemRequired) == 0)
          goto Throw;
        if ((flags & PowerRequestFlags.DoNotIdleDisplay) != default && PowerRequestHandle.PowerSetRequest(h, PowerRequestHandle.PowerRequestType.DisplayRequired) == 0)
          goto Throw;
        if ((flags & PowerRequestFlags.DoNotSleep) != default && PowerRequestHandle.PowerSetRequest(h, PowerRequestHandle.PowerRequestType.AwayModeRequired) == 0)
          goto Throw;
        GC.KeepAlive(handle);
        // ^^^ Ensures that `handle` is not finalized until we're done with `h`.
        Interlocked.Exchange(ref flags_, (int)(uint)flags);
        return;
      Throw:
        int win32error = Marshal.GetLastWin32Error();
        throw new PowerRequestException("An exception occurred when making a power request to Windows.", new Win32Exception(win32error));
      }
      catch
      {
        Dispose();
        throw;
      }
    }

    public sealed override void Dispose()
    {
      Interlocked.Exchange(ref flags_, default);
      Interlocked.Exchange(ref handle_, null)?.Dispose();
    }

    private sealed class PowerRequestHandle : CriticalFinalizerObject, IDisposable
    {
      // Member order is from Windows SDK 10.0.26100.0.
      internal enum PowerRequestType
      {
        DisplayRequired,
        SystemRequired,
        AwayModeRequired,
        ExecutionRequired,
      }

      [StructLayout(LayoutKind.Sequential)]
      internal readonly unsafe struct SimpleReasonContext
      {
        [ReliabilityContract(Consistency.WillNotCorruptState, Cer.MayFail)]
        internal SimpleReasonContext(char* reason)
        {
          // POWER_REQUEST_CONTEXT_VERSION from Windows SDK 10.0.26100.0.
          Version = 0;
          // POWER_REQUEST_CONTEXT_SIMPLE_STRING
          Flags = 1;
          SimpleReasonString = reason;
          Padding1 = default;
          Padding2 = default;
          Padding3 = default;
        }
        private readonly uint Version;
        private readonly uint Flags;
        private readonly char* SimpleReasonString;
        private readonly uint Padding1;
        private readonly uint Padding2;
        private readonly IntPtr Padding3;
      }

#pragma warning disable SYSLIB1054 // No marshaling is needed.

      [DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
      [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
      [ReliabilityContract(Consistency.WillNotCorruptState, Cer.MayFail)]
      internal static extern unsafe IntPtr PowerCreateRequest(SimpleReasonContext* context);

      [DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
      [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
      [ReliabilityContract(Consistency.WillNotCorruptState, Cer.MayFail)]
      internal static extern int PowerSetRequest(IntPtr handle, PowerRequestType pqt);

      [DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
      [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
      [ReliabilityContract(Consistency.WillNotCorruptState, Cer.MayFail)]
      private static extern int CloseHandle(IntPtr handle);

#pragma warning restore SYSLIB1054

      internal IntPtr Handle;

      [ReliabilityContract(Consistency.WillNotCorruptState, Cer.MayFail)]
      internal PowerRequestHandle()
      {
        RuntimeHelpers.PrepareConstrainedRegions();
        try
        {
        }
        finally
        {
          Interlocked.Exchange(ref Handle, default);
        }
      }

      [ReliabilityContract(Consistency.WillNotCorruptState, Cer.MayFail)]
      public void Dispose()
      {
        RuntimeHelpers.PrepareConstrainedRegions();
        try
        {
        }
        finally
        {
          GC.SuppressFinalize(this);
          IntPtr h = Interlocked.Exchange(ref Handle, default);
          if (h != default && h != (IntPtr)(-1) && CloseHandle(h) == 0)
          {
            int win32error = Marshal.GetLastWin32Error();
            throw new Win32Exception(win32error);
          }
        }
      }

      [ReliabilityContract(Consistency.WillNotCorruptState, Cer.MayFail)]
      ~PowerRequestHandle()
      {
        RuntimeHelpers.PrepareConstrainedRegions();
        try
        {
        }
        finally
        {
          Dispose();
        }
      }
    }
  }
}

#pragma warning restore CA2219
#pragma warning restore SYSLIB0004
