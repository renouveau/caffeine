// SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
// SPDX-License-Identifier: MIT

// This file is part of Renouveau Caffeine, available under the MIT license.
// https://github.com/renouveau/caffeine

#if !IS_Windows_only

using System;

namespace Renouveau.Caffeine.PlatformPowerRequests
{
  internal sealed class NoOp : PowerRequest
  {
    private protected sealed override void PreventOutsiders() { }

    /// <summary>
    /// Creates a power request for an unsupported platform.
    /// </summary>
    internal new static NoOp Create(string? reason, PowerRequestFlags preferred, PowerRequestFlags minimum)
    {
      _ = preferred; // Suppress "unused parameter".
      if (minimum == PowerRequestFlags.None)
        return new NoOp(Win32.SanitizeReason(reason));
      // Use the least strict sanitization policy. ^^^
      throw new PlatformNotSupportedException("No power request is currently supported on the current platform, but '"
        + nameof(minimum) + "' is not '" + nameof(PowerRequestFlags.None) + "': " + minimum.ToString());
    }

    private NoOp(string reason) : base(reason) { }

    public sealed override void Dispose() { }
  }
}

#endif
