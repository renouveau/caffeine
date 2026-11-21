// SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
// SPDX-License-Identifier: MIT

// This file is part of Renouveau Caffeine, available under the MIT license.
// https://github.com/renouveau/caffeine

#nullable enable

using System;

namespace Renouveau.Caffeine.PlatformPowerRequests
{
  internal sealed class Win32 : PowerRequest
  {
    private protected sealed override void PreventOutsiders() { }

    /// <summary>
    /// Creates a power request for Windows 7 or later.
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

    private Win32(PowerRequestFlags flags)
    {
      throw new NotImplementedException();
    }

    public sealed override void Dispose()
    {
      throw new NotImplementedException();
    }
  }
}
