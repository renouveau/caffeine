<#

.NOTES
SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
SPDX-License-Identifier: MIT

This file is part of Renouveau Neat, available under the MIT license.
https://github.com/renouveau/neat

.SYNOPSIS
Tests whether the project/solution is suitable for creating NuGet package(s).

.DESCRIPTION

`Test-GoodForPacking.ps1` can be invoked either as part of the build process or interactively.  The kind of invocation is determined by the parameter set (Interactive, Building).

A project/solution is suitable for packing if and only if it is considered stable and inside a Git repository and the working tree is clean.

When invoked interactively, projects unsuitable for packing are written to the warning stream.

When invoked as part of the build process, the process is exited by the script, so it should be invoked in a dedicated process.  A non-zero exit code indicates the project is unsuitable for packing, and prevents the build process from proceeding.  It is required that the PowerShell process running this script be started in the project directory.

.PARAMETER Project
(Interactive.)  The project(s) to test.  By default, all non-auxiliary projects are tested.

.PARAMETER PretendGitRepo
(Interactive.)  Skips the check that the directory is a Git repository.

.PARAMETER PretendTreeClean
(Interactive.)  Skips the check that the working tree is clean.

.PARAMETER PretendStable
(Interactive.)  Whether the projects should be considered to have `ps1_IsStable` set to `true`.  This avoids having to editing `*.csproj` and committing.  See `Write-AssemblyMetadata.ps1`.

.PARAMETER IsStable
(Building.)  Indicates whether the assembly *can be* considered stable.  If built outside a Git repository or the working tree is dirty, the assembly is still not considered stable regardless of this switch.  See `Write-AssemblyMetadata.ps1`.

.EXAMPLE

./Path/To/Test-GoodForPacking.ps1 -PretendStable

This checks whether each project is suitable for packing barring the `ps1_IsStable` property set on the projects.

.EXAMPLE

./Path/To/Test-GoodForPacking.ps1 -IsStable:$false

This is a possible invocation from MSBuild by setting

```csproj
<Exec Command="powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Unrestricted -Command ./Path/To/Test-GoodForPacking.ps1 -IsStableText $(ps1_IsStable)" WorkingDirectory="$(MSBuildProjectDirectory)" />
```

where `ps1_IsStable` is a custom property that is either `true` or `false`.

#>
[CmdletBinding(PositionalBinding=$false, DefaultParameterSetName='Interactive')]
Param
(
  [Parameter(ParameterSetName='Interactive', Position=1)]
  [string[]]$Project = @('*'),
  [Parameter(ParameterSetName='Interactive')]
  [Alias('SkipGit')]
  [switch]$PretendGitRepo,
  [Parameter(ParameterSetName='Interactive')]
  [Alias('SkipDirty')]
  [switch]$PretendTreeClean,
  [Parameter(ParameterSetName='Interactive')]
  [Alias('SkipStable')]
  [switch]$PretendStable,
  [Parameter(ParameterSetName='Building', Mandatory=$true)]
  [ValidateSet('true', 'false')]
  [string]$IsStableText
)

Begin { If ($PSCmdlet.ParameterSetName -eq 'Interactive')
{

$AllProjects = @(Get-ChildItem ([System.IO.Path]::Combine($PSScriptRoot, 'src', '*', '*.csproj')));
If ($AllProjects.Count -ne 0)
{
  $ProjectCounter = 0;
  $AllProjects = $AllProjects | ForEach-Object { [pscustomobject]@{
    'dir' = $_.Directory.Name;
    'file' = $_.Name;
    'id' = ++$ProjectCounter
  } };
}
$ResolvedProjects = [System.Collections.Generic.List[object]]::new();
$ResolvedProjectsDeDup = [System.Collections.Generic.HashSet[int]]::new();

$SkipAuxProjects = $false;
If ($Project.Count -eq 1 -and $Project[0] -eq '*')
{
  $ResolvedProjects = $AllProjects;
  $SkipAuxProjects = $true;
}
Else
{
  $MultiMatchAlign = [regex]::new('^( +\[)(.*?\])', 'Multiline');
  ForEach ($Proj In $Project)
  {
    $MatchCount = 0;
    $MultiMatchText = "Test-GoodForPacking.ps1: Multiple matches for $Proj.`n";
    ForEach ($MaybeMatch In $AllProjects)
    {
      If ($MaybeMatch.dir -eq $Proj -or $MaybeMatch.file -eq "$Proj.csproj")
      {
        $MatchCount = $MatchCount + 1;
        $MultiMatchText += "         [$MatchCount] $($MaybeMatch.dir)/$($MaybeMatch.file)`n";
        If ($ResolvedProjectsDeDup.Add($MaybeMatch.id))
        {
          $ResolvedProjects.Add($MaybeMatch);
        }
      }
    }
    If ($MatchCount -eq 0)
    {
      Write-Error "Test-GoodForPacking.ps1: Unknown project $Proj.";
    }
    ElseIf ($MatchCount -ne 1)
    {
      $MultiMatchLengthStats = $MultiMatchAlign.Matches($MultiMatchText) | ForEach-Object { $_.Length } | Measure-Object -Maximum -Minimum;
      If ($MultiMatchLengthStats.Maximum -gt $MultiMatchLengthStats.Minimum)
      {
        $MultiMatchLengthStats = $MultiMatchLengthStats.Maximum;
        $MultiMatchText = $MultiMatchAlign.Replace($MultiMatchText, [System.Text.RegularExpressions.MatchEvaluator]{
          $args[0].Groups[1].Value + ' ' * ($MultiMatchLengthStats - $args[0].Length) + $args[0].Groups[2].Value
        });
      }
      Write-Verbose $MultiMatchText;
    }
  }
}

$CommitHash = $null;
$TreeIsClean = $false;
Push-Location $PSScriptRoot -ErrorAction 'Stop';
Try
{
  $CommitHash = (@(git rev-parse --verify HEAD 2>$null) -join ' ').Trim().ToLowerInvariant();
  $TreeIsClean = -not (@(git status --porcelain 2>&1) -join '').Trim().Length;
}
Finally
{
  Pop-Location;
}
If (-not [regex]::new('^[0-9a-f]{40}$').IsMatch($CommitHash))
{
  If (-not $PretendGitRepo)
  {
    Write-Warning 'Test-GoodForPacking.ps1: Not inside a Git repository --- never considered stable.';
    Return;
  }
  Write-Verbose 'Test-GoodForPacking.ps1: Pretending but not inside a Git repository.';
}
If (-not $TreeIsClean)
{
  If (-not $PretendTreeClean)
  {
    Write-Warning 'Test-GoodForPacking.ps1: Working tree is dirty --- never considered stable.';
    Return;
  }
  Write-Verbose 'Test-GoodForPacking.ps1: Pretending but working tree is dirty.';
}

$ps1_IsStable_Regex = [regex]::new('<ps1_IsStable>');
$ps1_IsStableTrue_Regex = [regex]::new('<ps1_IsStable>true</ps1_IsStable>');
$ps1_AuxProjectDir_Regex = [regex]::new('^([A-Za-z][A-Za-z0-9]*\.)*(Tests(\.net[0-9]+)?|Benchmarks)$');
$ps1_AuxProjectFile_Regex = [regex]::new('^([A-Za-z][A-Za-z0-9]*\.)*(Tests(\.net[0-9]+)?|Benchmarks)\.csproj$');

ForEach ($ResProj In $ResolvedProjects)
{
  $CsProjXml = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($PSScriptRoot, 'src', $ResProj.dir, $ResProj.file), [System.Text.Encoding]::UTF8);
  $ps1_IsStable_Count = $ps1_IsStable_Regex.Matches($CsProjXml).Count;
  If ($ps1_IsStable_Count -ne 1)
  {
    If ($SkipAuxProjects -and $ps1_AuxProjectDir_Regex.IsMatch($ResProj.dir) -and $ps1_AuxProjectFile_Regex.IsMatch($ResProj.file))
    {
      Write-Verbose "Test-GoodForPacking.ps1: Skipping auxiliary project $($ResProj.dir)/$($ResProj.file)";
      Continue;
    }
    Write-Warning "Test-GoodForPacking.ps1: No unique <ps1_IsStable> for $($ResProj.dir)/$($ResProj.file)";
    Continue;
  }
  $ps1_IsStable_Count = $ps1_IsStableTrue_Regex.Matches($CsProjXml).Count;
  If ($ps1_IsStable_Count -ne 1)
  {
    If (-not $PretendStable)
    {
      Write-Warning "Test-GoodForPacking.ps1: ps1_IsStable = false for $($ResProj.dir)/$($ResProj.file)";
      Continue;
    }
    Write-Verbose "Test-GoodForPacking.ps1: Pretending but ps1_IsStable = false for $($ResProj.dir)/$($ResProj.file)";
  }
}

} }

End { If ($PSCmdlet.ParameterSetName -eq 'Building')
{

$PwshWrkLoc = (Get-Location).Path;
$ProcCurDir = [System.Environment]::CurrentDirectory;
If ($PwshWrkLoc -ne $ProcCurDir)
{
  'Test-GoodForPacking.ps1: PowerShell working location must match process current directory.';
  Exit 1;
}

If ($IsStableText -ne 'true')
{
  'Test-GoodForPacking.ps1: ps1_IsStable = false.';
  Exit 2;
}

$CommitHash = (@(git rev-parse --verify HEAD 2>$null) -join ' ').Trim().ToLowerInvariant();
$TreeIsClean = -not (@(git status --porcelain) -join '').Trim().Length;
If (-not [regex]::new('^[0-9a-f]{40}$').IsMatch($CommitHash))
{
  'Test-GoodForPacking.ps1: Not inside a Git repository --- never considered stable.';
  Exit 3;
}
If (-not $TreeIsClean)
{
  'Test-GoodForPacking.ps1: Working tree is dirty --- never considered stable.';
  Exit 4;
}

If ($Error.Count -ne 0)
{
  'Test-GoodForPacking.ps1: One or more unexpected errors occurred.';
  $Error;
  Exit -1;
}

Exit 0;

} }
