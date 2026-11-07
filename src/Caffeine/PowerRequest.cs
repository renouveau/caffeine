// SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
// SPDX-License-Identifier: MIT

// This file is part of Renouveau Caffeine, available under the MIT license.
// https://github.com/renouveau/caffeine

#nullable enable

using System;
using System.Runtime.CompilerServices;
using System.Threading;
using Renouveau.Caffeine.PlatformPowerRequests;

#if !IS_Windows_only
using System.Runtime.InteropServices;
#endif

namespace Renouveau.Caffeine
{
  /// <summary>
  /// Represents a potentially active power request.
  /// All members of this class are thread-safe.
  /// It is <strong>not</strong> suitable for use in SQL Server
  /// or any hosted environment which does not map managed threads one-to-one with unmanaged threads.
  /// It is also <strong>not</strong> suitable when the thread calling creation methods might be aborted.
  /// (Using it in unloadable application domains, if the thread is never aborted inside creation methods, is fine.)
  /// A client application cannot meaningfully derive from this class.
  /// </summary>
  public abstract class PowerRequest : IDisposable
  {
    private protected int flags_;

    /// <summary>
    /// Gets the combination of requests
    /// that are currently maintained by this object.
    /// For the lifetime of an object, the active flag set can only shrink.
    /// This property can be retrieved after disposal and
    /// a disposed request returns <c><see cref="PowerRequestFlags.None"/></c>.
    /// If the current object is accessed concurrently,
    /// the returned result is correct at some point in time (not torn),
    /// but it might have become stale by the time the method returns.
    /// </summary>
    public PowerRequestFlags ActiveRequests
    {
      get
      {
        return (PowerRequestFlags)(uint)Interlocked.CompareExchange(ref flags_, 0, 0);
      }
    }

    private protected PowerRequest() { }

    /// <summary>
    /// Terminates the power request if it is active.
    /// This method is idempotent.
    /// </summary>
    public void Dispose()
    {
      Dispose(true);
      GC.SuppressFinalize(this);
    }

#pragma warning disable CA1063 // Allow this method to be less visible than `protected`.
    private protected abstract void Dispose(bool disposing);
#pragma warning restore CA1063

    /// <summary>
    /// Terminates the power request if it is active.
    /// </summary>
    ~PowerRequest() { Dispose(false); }

    /// <summary>
    /// Tries to create a power request.
    /// <list type="bullet">
    /// <item>
    /// <c><paramref name="minimum"/></c> must be a subset of <c><paramref name="preferred"/></c>.
    /// </item>
    /// <item>
    /// If all requests in <c><paramref name="minimum"/></c> can be satisfied,
    /// an object is returned, which should be disposed.
    /// </item>
    /// <item>
    /// If some request in <c><paramref name="minimum"/></c> cannot be satisfied,
    /// an exception is thrown and no request is made.
    /// </item>
    /// <item>
    /// If an object is returned, its set of active requests is always between
    /// <c><paramref name="minimum"/></c> and <c><paramref name="preferred"/></c>.
    /// </item>
    /// </list>
    /// </summary>
    /// <exception cref="ArgumentException">
    /// <c><paramref name="minimum"/></c> is not a subset of <c><paramref name="minimum"/></c>.
    /// </exception>
    /// <exception cref="PlatformNotSupportedException">
    /// If the current platform does not support at least one flag in <c><paramref name="preferred"/></c>,
    /// including when the client is compiled using a higher version of Caffeine library,
    /// loads a lower version at run-time,
    /// and uses a flag the loaded version does not understand.
    /// </exception>
    /// <exception cref="ThreadInterruptedException">
    /// The request is guaranteed to be cancelled if the thread is interrupted during this call.
    /// </exception>
    /// <exception cref="PowerRequestException">
    /// For any other exceptional condition in making the request.
    /// </exception>
    /// <returns>Never <c><see langword="null"/></c>.</returns>
    [MethodImpl(MethodImplOptions.NoInlining)]
    public static PowerRequest Create(PowerRequestFlags preferred, PowerRequestFlags minimum)
    {
      if ((minimum | preferred) != preferred)
        throw new ArgumentException("'" + nameof(minimum) + "' is not a subset of '" + nameof(preferred) + "'.");
#if IS_Windows_only
      return Win32.Create(preferred, minimum);
#else
      return PlatformCreate(preferred, minimum);
#endif
    }

    /// <summary>
    /// Calls <c><see cref="Create(PowerRequestFlags, PowerRequestFlags)"/></c>
    /// with <c>minimum</c> being <c><see cref="PowerRequestFlags.None"/></c>.
    /// </summary>
    public static PowerRequest TryCreate(PowerRequestFlags preferred)
    {
      return Create(preferred, PowerRequestFlags.None);
    }

    /// <summary>
    /// Calls <c><see cref="Create(PowerRequestFlags, PowerRequestFlags)"/></c>
    /// with both <c>preferred</c> and <c>minimum</c> being <c><paramref name="required"/></c>.
    /// </summary>
    public static PowerRequest Create(PowerRequestFlags required)
    {
      return Create(required, required);
    }

#if !IS_Windows_only

    private static readonly Func<PowerRequestFlags, PowerRequestFlags, PowerRequest> PlatformCreate = CreatePlatformCreate();

    private static Func<PowerRequestFlags, PowerRequestFlags, PowerRequest> CreatePlatformCreate()
    {
      // Use delegate constructors to prevent C# compiler from
      // unnecessarily caching method-group-to-delegate conversion results.
      if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        return new Func<PowerRequestFlags, PowerRequestFlags, PowerRequest>(Win32.Create);
      return new Func<PowerRequestFlags, PowerRequestFlags, PowerRequest>(NoOp.Create);
    }

#endif

  }
}
