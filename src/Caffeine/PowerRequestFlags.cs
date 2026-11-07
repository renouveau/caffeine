// SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
// SPDX-License-Identifier: MIT

// This file is part of Renouveau Caffeine, available under the MIT license.
// https://github.com/renouveau/caffeine

using System;

#pragma warning disable CA1028 // Allow uint-based enum.
#pragma warning disable CA1711 // Allow `Flags` suffix.

namespace Renouveau.Caffeine
{
  /// <summary>
  /// Represents a combination of power requests.
  /// </summary>
  [Flags]
  public enum PowerRequestFlags : uint
  {
    /// <summary>
    /// No request is made.
    /// </summary>
    None = 0x0,
    /// <summary>
    /// Prevents the system from idling to sleep.
    /// <list type="bullet">
    /// <item>
    /// This flag is supported on Windows.
    /// If Connected Standby is enabled and the device is on battery,
    /// this request is ignored by Windows
    /// 5 minutes after the sleep idle timer expires.
    /// </item>
    /// <item>This flag is unsupported elsewhere.</item>
    /// </list>
    /// </summary>
    DoNotIdleSleep = 0x1,
    /// <summary>
    /// Prevents the system from idling to turn off the display.
    /// <list type="bullet">
    /// <item>
    /// This flag is supported on Windows.
    /// </item>
    /// <item>This flag is unsupported elsewhere.</item>
    /// </list>
    /// </summary>
    DoNotIdleDisplay = 0x2,
    /// <summary>
    /// Prevents the system from idling to switch off the disk.
    /// This flag is not useful for SSD.
    /// <list type="bullet">
    /// <item>This flag is not supported on any platform.</item>
    /// </list>
    /// </summary>
    DoNotIdleDisk = 0x4,
    /// <summary>
    /// Prevents the system from sleeping even if the user initiates a sleep,
    /// such as closing the lid of the laptop or (Windows) choosing Sleep in Start.
    /// <list type="bullet">
    /// <item>
    /// This flag is supported on Windows.
    /// If S3 sleep is not enabled, this flag is ignored by Windows.
    /// </item>
    /// </list>
    /// </summary>
    DoNotSleep = 0x40,
  }
}

#pragma warning restore CA1711
#pragma warning restore CA1028
