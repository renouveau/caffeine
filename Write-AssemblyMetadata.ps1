<#

.NOTES
SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
SPDX-License-Identifier: MIT

This file is part of Renouveau Neat, available under the MIT license.
https://github.com/renouveau/neat

.SYNOPSIS
Auto-generates assembly metadata based on build parameters and version control status.

.DESCRIPTION

`Write-AssemblyMetadata.ps1` must be invoked in a dedicated process (it will use `Exit` to indicate success/failure), often as part of MSBuild process.  The script must be invoked from the project directory (having at least one `*.csproj` file) and both the process working directory and PowerShell current location must be set to it.  No parameter is positional and most parameters are mandatory.

- If parameter validation fails inside the script, it sets the exit code to minus the ordinal number of that parameter (the first parameter, with ordinal number 0, needs no validation, so the exit code is below -1 in this case).
- If any error is detected, it sets the exit code to be at least 101.
- If any unexpected error occurred, it sets the exit code to 100.
- If no error is encountered, it sets the exit code to 0.
- Before exiting with non-zero code, it outputs some information about the failure to the output stream.

The script generates a C# code file containing the following metadata (`public static partial` read-only properties): License, Notice, TargetFramework, Platform, Configuration, BuildToolset, SemanticVersionString, (optional) SemanticVersion, MajorVersion, MinorVersion, PatchVersion, IsStable, DeveloperDateTime, WorkingTreeIsClean, GitCommitHash.  It also sets `AssemblyFileVersion`, `AssemblyInformationalVersion`, `AssemblyVersion` attributes on the assembly.

The semantic version is formed as follows.  Let `A`/`B`/`C` be major/minor/patch version numbers (possibly modified by this script), `H` the current Git commit hash, `TZ` a date and time (in UTC) formatted as `yyyyMMdd'T'HHmmss'Z'`, and `CD` either `clean` or `dirty`.

- When built in a clean working tree in a Git repository and considered stable, it is `A.B.C+git.H`.  (This is the only case when the version number is not modified by the script.)
- Otherwise, when built in a Git repository, it is `A.B.C-devTZ+CD.git.H`.
- Otherwise, it is `A.B.C-devTZ`.

When built in a clean working tree in a Git repository, `TZ` is the later of the author/committer dates; otherwise, it is the current date and time.

.PARAMETER IsStable
Indicates whether the assembly *can be* considered stable.  If built outside a Git repository or the working tree is dirty, the assembly is still not considered stable regardless of this switch.

.PARAMETER OutputFile
The relative path to the output file.  This path cannot contain space --- passing space on the command line to `PowerShell.exe` on Windows in a way that leads to correct parsing into `[string]` is very hard, and the script simply forbids trying it.  This path is often relative, like `'obj/Debug/net10.0/AssemblyMetadata.g.cs'`.

.PARAMETER Namespace
The `namespace` for the assembly metadata `static class`.  Only ASCII letters, numbers, and underscore are allowed in each component namespace.

.PARAMETER ClassName
The name of the assembly metadata `static class`.  Only ASCII letters, numbers, and underscore are allowed.

.PARAMETER Version
The latest stable version number, in the format of `'major.minor.patch'`.  The patch version number is incremented by 1 inside the script if the assembly is not considered stable, so that the version formed by the script is considered newer than the latest stable version.

.PARAMETER TargetFramework
The target framework moniker.  Only ASCII letters, numbers, underscore, full stop, and hyphen-minus are allowed.

.PARAMETER Platform
The CPU platform.  Only ASCII letters, numbers, underscore, full stop, and hyphen-minus are allowed.

.PARAMETER Configuration
The configuration (Debug/Release).  Only ASCII letters, numbers, underscore, full stop, and hyphen-minus are allowed.

.PARAMETER BuildToolset
The build toolset (e.g., MSBuild 18, .NET SDK 10).  Only ASCII letters, numbers, full stop, comma, hyphen-minus, and space are allowed.

.PARAMETER UseNeatSemVer200
Whether the field `SemanticVersion` of type `Renouveau.Neat.SemVer200` should be generated.

.EXAMPLE

./Path/To/Write-AssemblyMetadata.ps1 -s:$false -o 'obj/Debug/net10.0/AssemblyMetadata.g.cs' -ns 'Company.Product.Feature.Internals' -v '1.2.3' -tfm 'net10.0' -p 'AnyCPU' -c 'Debug' -b 'MSBuild 18, .NET SDK 10'

This is a possible invocation from MSBuild by setting

```csproj
<Exec Command="powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Unrestricted -Command ./Path/To/Write-AssemblyMetadata.ps1 $(ps1_IsStableSwitch) -o '$(IntermediateOutputPath)AssemblyMetadata.g.cs' -ns '$(RootNamespace).Internals' -v '$(Version)' -tfm '$(TargetFramework)' -p '$(Platform)' -c '$(Configuration)' -b %22'MSBuild $(MSBuildVersion), .NET SDK $(NETCoreSdkVersion)'%22" WorkingDirectory="$(MSBuildProjectDirectory)" />
```

where `ps1_IsStableSwitch` is a custom property that is either `-IsStable` or empty.

#>
[CmdletBinding(PositionalBinding=$false)]
Param
(
  [Alias('s')][Parameter()]
  [switch]$IsStable,
  [Alias('o')][Parameter(Mandatory)]
  [string]$OutputFile,
  [Alias('ns')][Parameter(Mandatory)]
  [string]$Namespace,
  [Alias('cn')][Parameter()]
  [string]$ClassName = 'AssemblyMetadata',
  [Alias('v')][Parameter(Mandatory)]
  [string]$Version,
  [Alias('tfm')][Parameter(Mandatory)]
  [string]$TargetFramework,
  [Alias('p')][Parameter(Mandatory)]
  [string]$Platform,
  [Alias('c')][Parameter(Mandatory)]
  [string]$Configuration,
  [Alias('b')][Parameter(Mandatory)]
  [string]$BuildToolset,
  [Alias('sv200')][Parameter()]
  [switch]$UseNeatSemVer200
)

$ErrorActionPreference = 'SilentlyContinue';

# Parse and validate arguments.

If ($OutputFile.Contains(' '))
{
  'Write-AssemblyMetadata.ps1: OutputFile cannot contain space.';
  $OutputFile;
  Exit -1;
}

If (-not [regex]::new('^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$').IsMatch($Namespace))
{
  'Write-AssemblyMetadata.ps1: Namespace must match /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$/.';
  $Namespace;
  Exit -2;
}

If (-not [regex]::new('^[A-Za-z_][A-Za-z0-9_]*$').IsMatch($ClassName))
{
  'Write-AssemblyMetadata.ps1: ClassName must match /^[A-Za-z_][A-Za-z0-9_]*$/.';
  $ClassName;
  Exit -3;
}

$MajorMinorPatch = $Version.Split([char[]]@('.'[0]));
If ($MajorMinorPatch.Count -ne 3)
{
  "Write-AssemblyMetadata.ps1: Version must be in the form of 'major.minor.patch'.";
  $Version;
  Exit -4;
}
$Major = [uint32]0;
$Minor = [uint32]0;
$Patch = [uint32]0;
Try
{
  $Major = [uint32]::Parse($MajorMinorPatch[0], [System.Globalization.NumberStyles]::None, [cultureinfo]::InvariantCulture);
  $Minor = [uint32]::Parse($MajorMinorPatch[1], [System.Globalization.NumberStyles]::None, [cultureinfo]::InvariantCulture);
  $Patch = [uint32]::Parse($MajorMinorPatch[2], [System.Globalization.NumberStyles]::None, [cultureinfo]::InvariantCulture);
}
Catch
{
  'Write-AssemblyMetadata.ps1: Version components must be [uint32].';
  $Version;
  $_;
  Exit -4;
}
$SemVerNumbers = $Major.ToString([cultureinfo]::InvariantCulture) +
  '.' + $Minor.ToString([cultureinfo]::InvariantCulture) +
  '.' + $Patch.ToString([cultureinfo]::InvariantCulture);
If ($SemVerNumbers -ne $Version)
{
  'Write-AssemblyMetadata.ps1: Version components cannot have leading zeros.';
  $Version;
  $SemVerNumbers;
  Exit -4;
}

If (-not [regex]::new('^[A-Za-z0-9_\.-]+$').IsMatch($TargetFramework))
{
  'Write-AssemblyMetadata.ps1: TargetFramework must match /^[A-Za-z0-9_\.-]+$/.';
  $TargetFramework;
  Exit -5;
}

If (-not [regex]::new('^[A-Za-z0-9_\.-]+$').IsMatch($Platform))
{
  'Write-AssemblyMetadata.ps1: Platform must match /^[A-Za-z0-9_\.-]+$/.';
  $Platform;
  Exit -6;
}

If (-not [regex]::new('^[A-Za-z0-9_\.-]+$').IsMatch($Configuration))
{
  'Write-AssemblyMetadata.ps1: Configuration must match /^[A-Za-z0-9_\.-]+$/.';
  $Configuration;
  Exit -7;
}

If (-not [regex]::new('^[A-Za-z0-9\., -]+$').IsMatch($BuildToolset))
{
  'Write-AssemblyMetadata.ps1: BuildToolset must match /^[A-Za-z0-9\., -]+$/.';
  $BuildToolset;
  Exit -8;
}

# Validate PowerShell working location and process current directory.

$PwshWrkLoc = (Get-Location).Path;
$ProcCurDir = [System.Environment]::CurrentDirectory;
If ($PwshWrkLoc -ne $ProcCurDir)
{
  'Write-AssemblyMetadata.ps1: PowerShell working location must match process current directory.';
  "PowerShell working location: $PwshWrkLoc";
  "Process  current  directory: $ProcCurDir";
  Exit 101;
}
If (-not (Test-Path .\*.csproj -PathType Leaf))
{
  'Write-AssemblyMetadata.ps1: There is no `*.csproj` file here.';
  Exit 102;
}

# Detect Git repository statistics.

$CommitHash = (@(git rev-parse --verify HEAD 2>$null) -join ' ').Trim().ToLowerInvariant();
$CommitHash_CSharp = '"' + $CommitHash + '"';
If (-not [regex]::new('^[0-9a-f]{40}$').IsMatch($CommitHash))
{
  $CommitHash = $null;
  $CommitHash_CSharp = 'null';
}

$TreeIsClean = $false;
$TreeIsClean_CSharp = 'false';
If ($CommitHash -ne $null -and (@(git status --porcelain) -join '').Trim().Length -eq 0)
{
  $TreeIsClean = $true;
  $TreeIsClean_CSharp ='true';
}

$DateTimeNow = [datetime]::UtcNow;
$DateTimeGit = $DateTimeNow;
If ($CommitHash -ne $null)
{
  $DateTimeGitTwo = (@(git log '--max-count=1' '--pretty=format:%at,%ct' $CommitHash) -join '').Split([char[]]@(','[0]));
  If ($DateTimeGitTwo.Count -ne 2)
  {
    'Write-AssemblyMetadata.ps1: Detected Git commit, but author/committer dates are not exactly two components.';
    $DateTimeGitTwo;
    Exit 103;
  }
  Try
  {
    $DateTimeGitAuthor    = [long]::Parse($DateTimeGitTwo[0], [System.Globalization.NumberStyles]::None, [cultureinfo]::InvariantCulture);
    $DateTimeGitCommitter = [long]::Parse($DateTimeGitTwo[1], [System.Globalization.NumberStyles]::None, [cultureinfo]::InvariantCulture);
    $DateTimeGit = [System.Math]::Max($DateTimeGitAuthor, $DateTimeGitCommitter);
    $DateTimeGit = [datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc).AddTicks($DateTimeGit * [long]10000000);
  }
  Catch
  {
    'Write-AssemblyMetadata.ps1: Failed to parse Git author/committer dates.';
    $DateTimeGitTwo;
    $_;
    Exit 104;
  }
}
$DateTimeNow_String = $DateTimeNow.ToString("yyyyMMdd'T'HHmmss'Z'", [cultureinfo]::InvariantCulture);
$DateTimeGit_String = $DateTimeGit.ToString("yyyyMMdd'T'HHmmss'Z'", [cultureinfo]::InvariantCulture);

# Create the metadata.

$DevDateTime        = $DateTimeNow;
$DevDateTime_String = $DateTimeNow_String;
$DevDateTime_CSharp = '"' + $DevDateTime_String + '"';
$SemVerExtras = $null;
$IsActuallyStable = $false;
$IsActuallyStable_CSharp = 'false';
If (-not $IsStable -or $CommitHash -eq $null -or -not $TreeIsClean)
{
  # $Version is the last stable version number.
  # We are after the last stable version, so the output version should be > $Version.
  # We are also not stable, so the output version should have a prerelease part.
  # Per semantic versioning comparison rules, we bump up $Patch and add prerelease tag.
  $Patch += 1;
  $SemVerNumbers = $Major.ToString([cultureinfo]::InvariantCulture) +
    '.' + $Minor.ToString([cultureinfo]::InvariantCulture) +
    '.' + $Patch.ToString([cultureinfo]::InvariantCulture);
  If ($CommitHash -eq $null)
  {
    $SemVerExtras = "-dev$DevDateTime_String";
  }
  ElseIf (-not $TreeIsClean)
  {
    $SemVerExtras = "-dev$DevDateTime_String+dirty.git.$CommitHash";
  }
  Else
  {
    $DevDateTime        = $DateTimeGit;
    $DevDateTime_String = $DateTimeGit_String;
    $DevDateTime_CSharp = '"' + $DevDateTime_String + '"';
    $SemVerExtras = "-dev$DevDateTime_String+clean.git.$CommitHash";
  }
}
Else
{
  $DevDateTime        = $DateTimeGit;
  $DevDateTime_String = $DateTimeGit_String;
  $DevDateTime_CSharp = '"' + $DevDateTime_String + '"';
  $SemVerExtras = "+git.$CommitHash";
  $IsActuallyStable = $true;
  $IsActuallyStable_CSharp = 'true';
}

$License = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($PSScriptRoot, 'LICENSE'), [System.Text.Encoding]::UTF8);
$License_CSharp = '"' + [regex]::Replace($License, '([^ !#-Z^-~]|\[|\])', [System.Text.RegularExpressions.MatchEvaluator]{
  [string]::Format('\u{0:x4}', [uint16]$args[0].Value[0]);
}) + '"';

$Notice = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($PwshWrkLoc, 'NOTICE'), [System.Text.Encoding]::UTF8);
$Notice_CSharp = '"' + [regex]::Replace($Notice, '([^ !#-Z^-~]|\[|\])', [System.Text.RegularExpressions.MatchEvaluator]{
  [string]::Format('\u{0:x4}', [uint16]$args[0].Value[0]);
}) + '"';

$UniqueSuffix = ([System.Security.Cryptography.SHA1]::Create().ComputeHash(
  [System.Text.Encoding]::UTF8.GetBytes($Namespace + '|' + $ClassName + '|' + $TargetFramework + '|' + $Platform + '|' + $Configuration + '|' + $BuildToolset + '|' + $SemVerNumbers + $SemVerExtras)
) | ForEach-Object { $_.ToString('x2', [cultureinfo]::InvariantCulture) }) -join '';

$AssemblyMetadata = (& {
'// Auto-generated by `Write-AssemblyMetadata.ps1`.'
'using System.Reflection;'
If ($UseNeatSemVer200)
{
''
'using SemVerT = Renouveau.Neat.SemVer200;'
}
''
'[assembly: AssemblyFileVersion("' + $SemVerNumbers + '")]'
'[assembly: AssemblyInformationalVersion("' + $SemVerNumbers + $SemVerExtras + '")]'
'[assembly: AssemblyVersion("' + $SemVerNumbers + '")]'
''
'namespace ' + $Namespace
'{'
'  public static partial class ' + $ClassName
'  {'
'    /// <summary>'
'    /// The full license text.'
'    /// </summary>'
'    public static partial string License { get { return ' + $License_CSharp + '; } }'
''
'    /// <summary>'
'    /// The full notice text.'
'    /// </summary>'
'    public static partial string Notice { get { return ' + $Notice_CSharp + '; } }'
''
'    /// <summary>'
'    /// The <see href="https://learn.microsoft.com/en-us/dotnet/standard/frameworks">target framework moniker</see> for which this assembly is compiled.'
'    /// </summary>'
'    public static partial string TargetFramework { get { return "' + $TargetFramework + '"; } }'
''
'    /// <summary>'
'    /// The CPU platform for which this assembly is compiled.'
'    /// </summary>'
'    public static partial string Platform { get { return "' + $Platform + '"; } }'
''
'    /// <summary>'
'    /// <c>Debug</c> or <c>Release</c> for which this assembly is compiled.'
'    /// </summary>'
'    public static partial string Configuration { get { return "' + $Configuration + '"; } }'
''
'    /// <summary>'
'    /// The toolset building this assembly.'
'    /// </summary>'
'    public static partial string BuildToolset { get { return "' + $BuildToolset + '"; } }'
''
'    /// <summary>'
'    /// The full semantic version 2.0.0 string of this assembly.'
'    /// </summary>'
'    public static partial string SemanticVersionString { get { return "' + $SemVerNumbers + $SemVerExtras + '"; } }'
If ($UseNeatSemVer200)
{
''
'    private static readonly SemVerT SemanticVersion_' + $UniqueSuffix + '_ = SemVerT.Parse(SemanticVersionString);'
''
'    /// <summary>'
'    /// The semantic version 2.0.0 object of this assembly.'
'    /// </summary>'
'    public static partial SemVerT SemanticVersion { get { return SemanticVersion_' + $UniqueSuffix + '_; } }'
}
''
'    /// <summary>'
'    /// The major version number per semantic versioning 2.0.0.'
'    /// </summary>'
'    public static partial uint MajorVersion { get { return ' + $Major.ToString([cultureinfo]::InvariantCulture) + 'u; } }'
''
'    /// <summary>'
'    /// The minor version number per semantic versioning 2.0.0.'
'    /// </summary>'
'    public static partial uint MinorVersion { get { return ' + $Minor.ToString([cultureinfo]::InvariantCulture) + 'u; } }'
''
'    /// <summary>'
'    /// The patch version number per semantic versioning 2.0.0.'
'    /// </summary>'
'    public static partial uint PatchVersion { get { return ' + $Patch.ToString([cultureinfo]::InvariantCulture) + 'u; } }'
''
'    /// <summary>'
'    /// Indicates whether this assembly is considered a stable version.'
'    /// It is considered stable if and only if'
'    /// the <c>ps1_IsStable</c> MSBuild macro is <c>true</c>'
'    /// and'
'    /// the assembly was built in a clean working tree in a Git repository.'
'    /// </summary>'
'    public static partial bool IsStable { get { return ' + $IsActuallyStable_CSharp + '; } }'
''
'    /// <summary>'
'    /// If the assembly was built in a clean working tree in a Git repository,'
'    /// this field is the UTC date and time of the later of author/committer dates,'
"    /// formatted as <c>yyyyMMdd'T'HHmmss'Z'</c>."
'    /// Otherwise, this field is the UTC date and time when the assembly was built.'
'    /// </summary>'
'    public static partial string DeveloperDateTime { get { return ' + $DevDateTime_CSharp + '; } }'
''
'    /// <summary>'
'    /// Indicates whether the working tree was clean.'
'    /// If the assembly was built outside a Git repository, this field is <c><see langword="false"/></c>.'
'    /// For a stable version, this field is always <c><see langword="true"/></c>.'
'    /// </summary>'
'    public static partial bool WorkingTreeIsClean { get { return ' + $TreeIsClean_CSharp + '; } }'
''
'    /// <summary>'
'    /// If the assembly was built outside a Git repository, this field is <c><see langword="null"/></c>.'
'    /// Otherwise, this field is the 40-character Git commit hash in lower case.'
'    /// </summary>'
'    public static partial string GitCommitHash { get { return ' + $CommitHash_CSharp + '; } }'
'  }'
'}'
''
}) -join "`n";

# The intermediate output directory might not exist
# when invoked from `dotnet pack` in a newly cloned repository.

$OutputFile = [System.IO.Path]::Combine($ProcCurDir, $OutputFile);
$IntermediateOutputPath = [System.IO.Path]::GetDirectoryName($OutputFile);

If (-not (Test-Path -LiteralPath $IntermediateOutputPath))
{
  New-Item $IntermediateOutputPath -Type Directory -Force -ErrorAction Ignore | Out-Null;
}
If (-not (Test-Path -LiteralPath $IntermediateOutputPath -Type Container))
{
  'Write-AssemblyMetadata.ps1: Intermediate output path does not exist, is not a directory, or could not be created.';
  $IntermediateOutputPath;
  Exit 105;
}

Try
{
  $ShouldWriteFile = $true;
  [byte[]]$MetadataBytes = [System.Text.Encoding]::UTF8.GetBytes($AssemblyMetadata);
  If (Test-Path -LiteralPath $OutputFile -Type Leaf)
  {
    If ((Get-Item -LiteralPath $OutputFile).Length -eq $MetadataBytes.Length)
    {
      $OldHash = (Get-FileHash -LiteralPath $OutputFile -Algorithm SHA256).Hash;
      $Hasher = [System.Security.Cryptography.SHA256]::Create();
      $NewHash = ($Hasher.ComputeHash($MetadataBytes) | ForEach-Object { $_.ToString('X2', [cultureinfo]::InvariantCulture) }) -join '';
      $Hasher.Dispose();
      If ($OldHash -eq $NewHash)
      {
        $ShouldWriteFile = $false;
      }
    }
  }
  If ($ShouldWriteFile)
  {
    [System.IO.File]::WriteAllBytes($OutputFile, $MetadataBytes);
  }
}
Catch
{
  'Write-AssemblyMetadata.ps1: Failed to overwrite the output file.';
  $_;
  Exit 106;
}

If ($Error.Count -ne 0)
{
  'Write-AssemblyMetadata.ps1: One or more unexpected errors occurred.';
  $Error;
  Exit 100;
}

Exit 0;
