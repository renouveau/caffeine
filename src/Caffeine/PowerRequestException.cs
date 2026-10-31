// SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
// SPDX-License-Identifier: MIT

// This file is part of Renouveau Caffeine, available under the MIT license.
// https://github.com/renouveau/caffeine

using System;

namespace Renouveau.Caffeine
{
  /// <summary>
  /// Represents an exception when making a power request.
  /// </summary>
  public sealed class PowerRequestException : Exception
  {
    /// <inheritdoc cref="Exception()"/>
    public PowerRequestException() : this("An exception occurred when making a power request to the operating system.")
    {
    }

    /// <inheritdoc cref="Exception(string)"/>
    public PowerRequestException(string message) : base(message)
    {
    }

    /// <inheritdoc cref="Exception(string, Exception)"/>
    public PowerRequestException(string message, Exception innerException) : base(message, innerException)
    {
    }
  }
}
