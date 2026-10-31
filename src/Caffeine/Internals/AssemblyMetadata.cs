// SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
// SPDX-License-Identifier: MIT

// This file is part of Renouveau Caffeine, available under the MIT license.
// https://github.com/renouveau/caffeine

namespace Renouveau.Caffeine.Internals
{
  /// <summary>
  /// Provides metadata about how the assembly was compiled.
  /// </summary>
  public static partial class AssemblyMetadata
  {
#if (DURING_IntelliSense == DURING_Build)
#error Exactly one of DURING_IntelliSense and DURING_Build should be defined.
#elif DURING_Build
    public static partial string License { get; }
    public static partial string Notice { get; }
    public static partial string TargetFramework { get; }
    public static partial string Platform { get; }
    public static partial string Configuration { get; }
    public static partial string BuildToolset { get; }
    public static partial string SemanticVersionString { get; }
    public static partial uint MajorVersion { get; }
    public static partial uint MinorVersion { get; }
    public static partial uint PatchVersion { get; }
    public static partial bool IsStable { get; }
    public static partial string DeveloperDateTime { get; }
    public static partial bool WorkingTreeIsClean { get; }
    public static partial string GitCommitHash { get; }
#elif DURING_IntelliSense
#pragma warning disable CS1591 // The following code is excluded from MSBuild (no need to document).
    public static string License { get { throw null; } }
    public static string Notice { get { throw null; } }
    public static string TargetFramework { get { throw null; } }
    public static string Platform { get { throw null; } }
    public static string Configuration { get { throw null; } }
    public static string BuildToolset { get { throw null; } }
    public static string SemanticVersionString { get { throw null; } }
    public static uint MajorVersion { get { throw null; } }
    public static uint MinorVersion { get { throw null; } }
    public static uint PatchVersion { get { throw null; } }
    public static bool IsStable { get { throw null; } }
    public static string DeveloperDateTime { get { throw null; } }
    public static bool WorkingTreeIsClean { get { throw null; } }
    public static string GitCommitHash { get { throw null; } }
#pragma warning restore CS1591
#endif
  }
}
