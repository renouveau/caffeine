// SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
// SPDX-License-Identifier: MIT

// This file is part of Renouveau Caffeine, available under the MIT license.
// https://github.com/renouveau/caffeine

#nullable enable

#if !IS_Windows_only

using System;
using System.Threading;

namespace Renouveau.Caffeine.PlatformPowerRequests
{
  internal sealed class NoOp : PowerRequest
  {
    /// <summary>
    /// Creates a power request for an unsupported platform.
    /// </summary>
    internal new static NoOp Create(PowerRequestFlags preferred, PowerRequestFlags minimum)
    {
      _ = preferred; // Suppress "unused parameter".
      if (minimum == PowerRequestFlags.None)
        return Instance;
      throw new PlatformNotSupportedException("No power request is currently supported on the current platform, but '"
        + nameof(minimum) + "' is not '" + nameof(PowerRequestFlags.None) + "': " + minimum.ToString());
    }

    private static readonly NoOp Instance = new NoOp();

    private NoOp() { Interlocked.Exchange(ref flags_, 0); GC.SuppressFinalize(this); }

    private protected override void Dispose(bool disposing) { }
  }
}

#endif
