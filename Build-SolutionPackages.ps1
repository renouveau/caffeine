<#

.NOTES
SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
SPDX-License-Identifier: MIT

This file is part of Renouveau Caffeine, available under the MIT license.
https://github.com/renouveau/caffeine

.SYNOPSIS
Builds the deliverables and creates packages in `Release` mode.

.PARAMETER Incremental
Enables incremental builds.
The script deletes `bin/Release`, `obj/Release` if this switch is not set.

#>
[CmdletBinding()]
Param
(
  [switch]$Incremental
)

$PreviousStackSize = (Get-Location -Stack).Count;
Try
{
  Push-Location -LiteralPath ([System.IO.Path]::Combine($PSScriptRoot, 'src'));
  If ((Get-Location).Path -ne [System.IO.Path]::Combine($PSScriptRoot, 'src'))
  {
    Throw 'Build-SolutionPackages.ps1: Push-Location failed.';
  }
  Write-Verbose "Build-SolutionPackages.ps1: Location = $((Get-Location).Path)";
  If (-not $Incremental)
  {
    Remove-Item ([System.IO.Path]::Combine($PSScriptRoot, 'src', '*', 'bin', 'Release')) -Force -Recurse -ErrorAction 'Ignore';
    Remove-Item ([System.IO.Path]::Combine($PSScriptRoot, 'src', '*', 'obj', 'Release')) -Force -Recurse -ErrorAction 'Ignore';
  }
  $local:NativeExitCode = 0;
  dotnet pack;
  $NativeExitCode = $LASTEXITCODE;
  If ($NativeExitCode -ne 0)
  {
    Write-Error "Build-SolutionPackages.ps1: failed with exit code $($NativeExitCode): dotnet pack";
    Return;
  }
  & './ForPowerShell/Build-ForPowerShell.ps1' -Configuration 'Release';
}
Finally
{
  $PopAttempts = 0;
  While ((Get-Location -Stack).Count -gt $PreviousStackSize)
  {
    $PopAttempts = $PopAttempts + 1;
    If ($PopAttempts -gt 8)
    {
      Write-Error 'Build-SolutionPackages.ps1: Too many attempts to Pop-Location (8 attempts made).';
      Break;
    }
    Pop-Location;
  }
  $CurrentStackSize = (Get-Location -Stack).Count;
  If ($PopAttempts -eq 1)
  {
    If ($CurrentStackSize -eq $PreviousStackSize)
    {
      Write-Verbose 'Build-SolutionPackages.ps1: Location stack size restored with Pop-Location.';
    }
    Else
    {
      Write-Warning "Build-SolutionPackages.ps1: Location stack size changed after 1 invocation of Pop-Location ($PreviousStackSize -> $CurrentStackSize).";
    }
  }
  Else
  {
    If ($CurrentStackSize -eq $PreviousStackSize)
    {
      Write-Warning "Build-SolutionPackages.ps1: Location stack size restored with $PopAttempts invocations of Pop-Location.";
    }
    Else
    {
      Write-Warning "Build-SolutionPackages.ps1: Location stack size changed after $PopAttempts invocation of Pop-Location ($PreviousStackSize -> $CurrentStackSize).";
    }
  }
}
