<#

.NOTES
SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
SPDX-License-Identifier: MIT

This file is part of Renouveau Neat, available under the MIT license.
https://github.com/renouveau/neat

.SYNOPSIS
Removes non-deterministic information produced by NuGet packager from a NuGet package.

.DESCRIPTION

`Convert-NupkgToDet.ps1` can be invoked either as part of the build process or interactively.  The kind of invocation is determined by the switch `NonInteractive`.

The script should be invoked from an appropriate Git repository.  It does the following.

- Edit `/[Content_Types].xml` (sort the descendants) if it exists.
- Compute a hash based on the contents (except `*.psmdcp` and `/_rels/.rels`).
- Find and update the unique `*.psmdcp` to indicate that the package has been modified by the script (this operation is idempotent).
- Rename the unique `*.psmdcp` to a name based on the hash.
- Edit `/_rels/.rels` to use relation identifiers based on the hash.
- Edit `/_rels/.rels` to reflect the new name of `*.psmdcp`.
- Repack the files (with a date/time based on the Git version control, if one is available).

The date/time is the later of author/committer date of the current commit if the working tree is clean.  Otherwise, the current date/time is used and the output will not be deterministic.

When invoked as part of the build process, the process is exited by the script, so it should be invoked in a dedicated process.  A non-zero exit code indicates conversion has failed and usually makes the build process report such failure.

.PARAMETER InputFile
Path to the package to be made deterministic.

.PARAMETER OutputFile
Path to the output package.

.PARAMETER SmallestSize
If set, the script uses `SmallestSize` compression level if it is available in the current .NET runtime.

.PARAMETER Strict
If set, the script abandons the operation if it the working location is not in a Git repository or has a dirty working tree.

.PARAMETER NonInteractive
Indicates that the script is called from the build process.

.EXAMPLE

./Path/To/Convert-NupkgToDet.ps1 -InputFile a.nupkg -OutputFile b.nupkg -Debug -Verbose

.EXAMPLE

./Path/To/Convert-NupkgToDet.ps1 -i 'bin/Release/My.Library.1.0.0.nupkg' -o 'bin/Release/MyLibrary.1.0.0.nupkg' -sz -s -ni

This is a possible invocation from MSBuild by setting

```csproj
<Exec Command="powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Unrestricted -Command ./Path/To/Convert-NupkgToDet.ps1 -i '$(OutputPath)$(PackageId).$(PackageVersion).nupkg' -o '$(OutputPath)$(PackageId).$(PackageVersion).nupkg' -sz -s -ni" WorkingDirectory="$(MSBuildProjectDirectory)" />
```

The input/output files can be the same.

#>
[CmdletBinding(PositionalBinding=$false)]
Param
(
  [Parameter(Mandatory=$true)]
  [Alias('i')]
  [string]$InputFile,
  [Parameter(Mandatory=$true)]
  [Alias('o')]
  [string]$OutputFile,
  [Alias('sz')]
  [switch]$SmallestSize,
  [Alias('s')]
  [switch]$Strict,
  [Alias('ni')]
  [switch]$NonInteractive
)

Begin
{

$CompressionLevel = 'Optimal';

# Load necessary types and resolve compression level.

Add-Type -AssemblyName 'System.IO.Compression' | Out-Null;
If ($PSVersionTable.PSEdition -eq 'Desktop')
{
  Add-Type -AssemblyName 'System.IO.Compression.FileSystem' | Out-Null;
  Add-Type -AssemblyName 'System.Xml.Linq' | Out-Null;
}
Else
{
  Add-Type -AssemblyName 'System.IO.Compression.ZipFile' | Out-Null;
  Add-Type -AssemblyName 'System.Xml.XDocument' | Out-Null;
  If ($SmallestSize)
  {
    $CompressionLevel = 'SmallestSize';
  }
}

$CompressionLevel = [System.IO.Compression.CompressionLevel]$CompressionLevel;

# Reliably passing from MSBuild file names
# containing multiple spaces or quotation marks
# is complicated (escaping), so we back off.

If ($NonInteractive)
{
  $RegexSimplePath = [regex]::new('^([a-zA-Z0-9_()$@!~`#%&+=;,/-]|\.|\\)+[a-zA-Z0-9_()$@!~`#%&+=;,-]$');
  If (-not $RegexSimplePath.IsMatch($InputFile))
  {
    "Convert-NupkgToDet.ps1: (NonInteractive) InputFile does not match $($RegexSimplePath.ToString())`n$InputFile";
    Exit -1;
  }
  If (-not $RegexSimplePath.IsMatch($OutputFile))
  {
    "Convert-NupkgToDet.ps1: (NonInteractive) OutputFile does not match $($RegexSimplePath.ToString())`n$OutputFile";
    Exit -2;
  }
}

# Resolve input file path.

$InputFiles = @(Get-Item $InputFile);
$Msg = 'Convert-NupkgToDet.ps1: Ambiguous input file.';
If ($InputFiles.Count -ne 1)
{
  If ($NonInteractive)
  {
    $Msg;
    Exit -3;
  }
  Write-Error $Msg;
  Return;
}
$InputFile = $InputFiles[0].FullName;
Write-Debug "Convert-NupkgToDet.ps1: Resolved input file to`n$InputFile";

# Detect Git commit and working tree cleanness.

$CommitHash = (@(git rev-parse --verify HEAD 2>$null) -join ' ').Trim().ToLowerInvariant();
If (-not [regex]::new('^[0-9a-f]{40}$').IsMatch($CommitHash))
{
  $CommitHash = $null;
}
$TreeIsClean = $false
If ($CommitHash -ne $null)
{
  $TreeIsClean = -not (@(git status --porcelain) -join '').Trim().Length;
}

# Resolve the date time to use.

$DateTime = [datetime]::new(2026, 1, 3, 0, 0, 0, [System.DateTimeKind]'Utc');
$Msg = 'Convert-NupkgToDet.ps1: Not inside a Git repository or working tree is dirty.';
If (-not $TreeIsClean)
{
  If ($NonInteractive)
  {
    $Msg;
    If ($Strict)
    {
      Exit 1;
    }
  }
  ElseIf ($Strict)
  {
    Write-Error $Msg;
    Return;
  }
  Else
  {
    Write-Warning $Msg;
  }
}
Else
{
  $DateTimeGitTwo = (@(git log '--max-count=1' '--pretty=format:%at,%ct' $CommitHash) -join '').Split([char[]]@(','[0]));
  If ($DateTimeGitTwo.Count -ne 2)
  {
    $Msg = "Convert-NupkgToDet.ps1: Detected Git commit with clean working tree, but author/committer dates are not exactly two components: $($DateTimeGitTwo -join ',')";
    If ($NonInteractive)
    {
      $Msg;
      If ($Strict)
      {
        Exit 2;
      }
    }
    ElseIf ($Strict)
    {
      Write-Error $Msg;
      Return;
    }
    Else
    {
      Write-Warning $Msg;
    }
  }
  Try
  {
    $DateTimeGitAuthor    = [long]::Parse($DateTimeGitTwo[0], [System.Globalization.NumberStyles]::None, [cultureinfo]::InvariantCulture);
    $DateTimeGitCommitter = [long]::Parse($DateTimeGitTwo[1], [System.Globalization.NumberStyles]::None, [cultureinfo]::InvariantCulture);
    $DateTimeGit = [System.Math]::Max($DateTimeGitAuthor, $DateTimeGitCommitter);
    $DateTimeGit = [datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc).AddTicks($DateTimeGit * [long]10000000);
    $DateTime = $DateTimeGit;
  }
  Catch
  {
    $Msg = "Convert-NupkgToDet.ps1: Failed to parse Git author/committer dates: $($DateTimeGitTwo -join ',')";
    If ($NonInteractive)
    {
      $Msg;
      $_;
      If ($Strict)
      {
        Exit 3;
      }
    }
    ElseIf ($Strict)
    {
      Write-Error -Message $Msg -Exception $($_.Exception);
      Return;
    }
    Else
    {
      Write-Warning $Msg;
      Write-Warning $($_.Exception);
    }
  }
}

Try
{
  # Extract the package and provide a chance of inspection.
  $TempDir = [System.IO.Path]::Combine(
    [System.IO.Path]::GetTempPath(),
    [Guid]::NewGuid().ToString('n')
  ).Replace([System.IO.Path]::DirectorySeparatorChar, '/');
  New-Item $TempDir -Type 'Directory' | Out-Null;
  Write-Verbose "Convert-NupkgToDet.ps1: Using temporary directory`n$TempDir";
  [System.IO.Compression.ZipFile]::ExtractToDirectory($InputFile, $TempDir, [System.Text.Encoding]::UTF8);
  # Hash all stable files and find out the *.psmdcp file.
  Write-Debug 'Convert-NupkgToDet.ps1: Extracted package, about to compute hash.';
  $Psmdcp = $null;
  $Hasher = [System.Security.Cryptography.SHA256]::Create();
  $BigStream = [System.IO.MemoryStream]::new();
  # `-Force` is necessary to see files starting with `.` on *nix,
  # notably `/_rels/.rels`.
  $Files = @(Get-ChildItem -LiteralPath $TempDir -Recurse -File -Force);
  $Files = @($Files.FullName.Replace([System.IO.Path]::DirectorySeparatorChar, '/'));
  [array]::Sort($Files, [System.StringComparer]::Ordinal);
  ForEach ($File In $Files)
  {
    If (-not $File.StartsWith($TempDir + '/'))
    {
      Throw "Unexpected file name (casing?) $File";
    }
    ElseIf ($File -eq "$TempDir/[Content_Types].xml")
    {
      Write-Debug 'Convert-NupkgToDet.ps1: About to load and edit [Content_Types].xml.';
      $ContentTypesXml = [System.Xml.Linq.XDocument]::Load($File);
      # Write-Output materializes the collection.
      $ContentTypesDefaults = @($ContentTypesXml.Root.Elements($ContentTypesXml.Root.GetDefaultNamespace() + 'Default') | Write-Output);
      $ContentTypesOverrides = @($ContentTypesXml.Root.Elements($ContentTypesXml.Root.GetDefaultNamespace() + 'Override') | Write-Output);
      # Remove all of them and ensure they're the only ones.
      $ContentTypesDefaults | ForEach-Object { If ($_ -ne $null) { $_.Remove() } } | Out-Null;
      $ContentTypesOverrides | ForEach-Object { If ($_ -ne $null) { $_.Remove() } } | Out-Null;
      $ContentTypesRemaining = @($ContentTypesXml.Root.Elements() | Write-Output);
      If ($ContentTypesRemaining.Count -ne 0)
      {
        Throw 'Unknown elements in [Content_Types].xml';
      }
      # Sort and re-add.
      [array]::Sort($ContentTypesDefaults, [System.Comparison[object]] {
        Param ($first, $second)
        Return ([System.StringComparer]::Ordinal.Compare($first.ToString(), $second.ToString()));
      });
      [array]::Sort($ContentTypesOverrides, [System.Comparison[object]] {
        Param ($first, $second)
        Return ([System.StringComparer]::Ordinal.Compare($first.ToString(), $second.ToString()));
      });
      $ContentTypesXml.Root.Add($ContentTypesDefaults);
      $ContentTypesXml.Root.Add($ContentTypesOverrides);
      Write-Debug 'Convert-NupkgToDet.ps1: About to save [Content_Types].xml.';
      $ContentTypesXml.Save($File);
      # Hash the contents. (See last branch below.)
      $PartHash = $Hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($File.Substring($TempDir.Length + 1)));
      $BigStream.Write($PartHash, 0, $PartHash.Count);
      $PartHash = $Hasher.ComputeHash([System.IO.File]::ReadAllBytes($File));
      $BigStream.Write($PartHash, 0, $PartHash.Count);
    }
    ElseIf ($File.ToUpperInvariant().EndsWith('.PSMDCP'))
    {
      If ($Psmdcp -ne $null)
      {
        Throw 'More than one *.psmdcp found.';
      }
      $Psmdcp = $File;
    }
    ElseIf ($File -ne "$TempDir/_rels/.rels")
    {
      # Hash of file name, then followed by hash of file content.
      $PartHash = $Hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($File.Substring($TempDir.Length + 1)));
      $BigStream.Write($PartHash, 0, $PartHash.Count);
      $PartHash = $Hasher.ComputeHash([System.IO.File]::ReadAllBytes($File));
      $BigStream.Write($PartHash, 0, $PartHash.Count);
    }
  }
  If ($Psmdcp -eq $null)
  {
    Throw 'No *.psmdcp found.';
  }
  $PkgAbsPsmdcp = $Psmdcp.Substring($TempDir.Length);
  # Hash of juxtaposed hashes of length 64.
  # First 32 characters are used for the name of *.psmdcp.
  # Next a few characters are used for relation identifiers.
  # The number of characters used depends on the number of relation identifiers.
  If ($BigStream.Length -ne ($Files.Count - 2) * 64 -or $BigStream.Position -ne $BigStream.Length)
  {
    Throw 'Unexpected length/location of stream of hashes.';
  }
  If ($BigStream.Seek(0, 'Begin') -ne 0)
  {
    Throw 'Could not rewind stream of hashes to the beginning.';
  }
  $Hash = [System.BitConverter]::ToString($Hasher.ComputeHash($BigStream)).Replace('-', '').ToLowerInvariant();
  # The script below does ZIP packing, which could run for a while.
  # Stop referencing the MemoryStream to allow its memory be reclaimed.
  $BigStream = $null;
  $Hasher.Dispose();
  If ($Hash.Length -ne 64)
  {
    Throw 'Unexpected hash length (should be 64 characters long).';
  }
  Write-Verbose "non-meta content hash = $Hash";
  Write-Verbose "    new *.psmdcp name = $($Hash.Substring(0, 32)).psmdcp";
  # Edit the *.psmdcp file to keep track of last modification.
  $ScriptIdentifier = 'Convert-NupkgToDet.ps1, Hash=';
  $ScriptIdentifier += (Get-FileHash -LiteralPath "$PSScriptRoot/Convert-NupkgToDet.ps1" -Algorithm SHA256).Hash.ToLowerInvariant();
  $ScriptIdentifier += ', PSVersion=' + $PSVersionTable.PSVersion.ToString();
  $ScriptIdentifier += ', CLRVersion=' + [System.Environment]::Version.ToString();
  Write-Debug "Convert-NupkgToDet.ps1: About to edit *.psmdcp at`n$Psmdcp`nto add script identifier`n$ScriptIdentifier";
  [System.IO.File]::WriteAllBytes($Psmdcp, [System.Text.Encoding]::UTF8.GetBytes([regex]::Replace(
    [System.IO.File]::ReadAllText($Psmdcp, [System.Text.Encoding]::UTF8),
    '<lastModifiedBy>(Convert-NupkgToDet.ps1,[^;]*;)?',
    '<lastModifiedBy>' + $ScriptIdentifier + ';'
  )));
  # Rename the *.psmdcp file.
  Write-Debug "Convert-NupkgToDet.ps1: About to rename *.psmdcp at`n$Psmdcp";
  Rename-Item -LiteralPath $Psmdcp -NewName "$($Hash.Substring(0, 32)).psmdcp";
  $NewPsmdcp = $Psmdcp.Substring($TempDir.Length);
  $NewPsmdcp = [regex]::Replace($NewPsmdcp, '/[^/]*?\.[Pp][Ss][Mm][Dd][Cc][Pp]$', '/' + $Hash.Substring(0, 32) + '.psmdcp');
  # Edit relation XML.
  Write-Debug 'Convert-NupkgToDet.ps1: About to load and edit relation XML.';
  $RelationXml = [System.Xml.Linq.XDocument]::Load("$TempDir/_rels/.rels");
  $Relations = $RelationXml.Root.Elements($RelationXml.Root.GetDefaultNamespace() + 'Relationship') | Write-Output;
  # ^^^ Write-Output is necessary to materialize the enumerable.
  $RelationIdPrefix = 20;
  If ($Relations.Count -gt 4096)
  {
    Throw 'Too many relations (at most 4096).';
  }
  If ($Relations.Count -le 2048) { ++$RelationIdPrefix; }
  If ($Relations.Count -le 1024) { ++$RelationIdPrefix; }
  If ($Relations.Count -le  512) { ++$RelationIdPrefix; }
  If ($Relations.Count -le  256) { ++$RelationIdPrefix; }
  If ($Relations.Count -le  128) { ++$RelationIdPrefix; }
  If ($Relations.Count -le   64) { ++$RelationIdPrefix; }
  If ($Relations.Count -le   32) { ++$RelationIdPrefix; }
  If ($Relations.Count -le   16) { ++$RelationIdPrefix; }
  If ($Relations.Count -le    8) { ++$RelationIdPrefix; }
  If ($Relations.Count -le    4) { ++$RelationIdPrefix; }
  If ($Relations.Count -le    2) { ++$RelationIdPrefix; }
  If ($Relations.Count -le    1) { ++$RelationIdPrefix; }
  $RelationIdPrefix = $Hash.Substring(32, $RelationIdPrefix).ToUpperInvariant();
  $RelationIdSuffixFormat = 'X' + (33 - $RelationIdPrefix.Length).ToString();
  Write-Verbose "   (reminder) hash = $Hash";
  Write-Verbose "relation ID prefix =                                 $RelationIdPrefix";
  Write-Verbose "     suffix format = $RelationIdSuffixFormat, then remove first character";
  $Edited = $false;
  $RelationIndex = 0;
  # relation ID = R + (part of overall hash) + (index of relation)
  ForEach ($Relation In $Relations)
  {
    If ($Relation.Attribute('Target').Value -eq $PkgAbsPsmdcp)
    {
      If ($Edited)
      {
        Throw 'Multiple *.psmdcp in relation XML.';
      }
      $Edited = $true;
      $Relation.Attribute('Target').Value = $NewPsmdcp;
    }
    $RelationIdSuffix = $RelationIndex.ToString($RelationIdSuffixFormat).Substring(1);
    $Relation.Attribute('Id').Value = 'R' + $RelationIdPrefix + $RelationIdSuffix;
    ++$RelationIndex;
  }
  If (-not $Edited)
  {
    Throw 'Did not find *.psmdcp in relation XML.';
  }
  Write-Debug 'Convert-NupkgToDet.ps1: About to save relation XML.';
  $RelationXml.Save("$TempDir/_rels/.rels");
  # Repack the files.
  Write-Debug 'Convert-NupkgToDet.ps1: About to repack files.';
  $TempZip = "$TempDir/$([Guid]::NewGuid().ToString('n')).zip";
  $NewZip = [System.IO.Compression.ZipArchive]::new([System.IO.File]::Create($TempZip), 'Create', $false, [System.Text.Encoding]::UTF8);
  ForEach ($File In $Files)
  {
    $Entry = $null;
    If ($File.ToUpperInvariant().EndsWith('.PSMDCP'))
    {
      $File = $TempDir + $NewPsmdcp;
      $Entry = $NewZip.CreateEntry($NewPsmdcp.Substring(1), $CompressionLevel);
    }
    Else
    {
      $Entry = $NewZip.CreateEntry($File.Substring($TempDir.Length + 1), $CompressionLevel);
    }
    $Entry.LastWriteTime = $DateTime;
    $EntryStream = $Entry.Open();
    $FileStream = [System.IO.File]::OpenRead($File);
    $FileStream.CopyTo($EntryStream);
    $FileStream.Close();
    $EntryStream.Close();
  }
  $NewZip.Dispose();
  # Move file to destination.
  Write-Debug "Convert-NupkgToDet.ps1: About to move`n$TempZip`n  to`n$OutputFile";
  Move-Item -LiteralPath $TempZip -Destination $OutputFile -Force;
  # Clean up the mess if there's no need to do a postmortem analysis.
  Write-Debug "Convert-NupkgToDet.ps1: About to delete temporary directory`n$TempDir";
  Remove-Item -LiteralPath $TempDir -Force -Recurse;
}
Catch
{
  $Msg = 'Convert-NupkgToDet.ps1: An exception occurred.';
  If ($NonInteractive)
  {
    $Msg;
    $_;
    Exit 4;
  }
  Write-Error -Message $Msg -Exception $($_.Exception);
}

If ($Strict -and $Error.Count -ne 0)
{
  'Convert-NupkgToDet.ps1: One or more unexpected errors occurred.';
  $Error;
  Exit -1;
}

If ($NonInteractive)
{
  "Convert-NupkgToDet.ps1: Successfully converted`n   NuGet-created package  $InputFile`nto deterministic package  $(Resolve-Path $OutputFile)";
}

}
