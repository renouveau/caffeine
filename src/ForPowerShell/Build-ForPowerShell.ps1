<#

.NOTES
SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
SPDX-License-Identifier: MIT

This file is part of Renouveau Caffeine, available under the MIT license.
https://github.com/renouveau/caffeine

#>
[CmdletBinding()]
Param
(
  [ValidateSet('*', 'Debug', 'Release')]
  [string]$Configuration = '*'
)

If ($Configuration -eq '*')
{
  & "$PSScriptRoot/Build-ForPowerShell.ps1" -Configuration 'Debug';
  & "$PSScriptRoot/Build-ForPowerShell.ps1" -Configuration 'Release';
  Return;
}

# Canonicalize casing.
If ($Configuration -eq 'Debug')   { $Configuration = 'Debug';   }
If ($Configuration -eq 'Release') { $Configuration = 'Release'; }

$local:PrevError = $Error.Count;

$null = & {
Remove-Item -LiteralPath "$PSScriptRoot/bin/$Configuration" -Force -Recurse -ErrorAction 'Ignore';
New-Item -Path "$PSScriptRoot/bin/$Configuration" -Name 'PSModuleLayout' -ItemType 'Directory' -Force;
Get-ChildItem -LiteralPath "$PSScriptRoot/../Caffeine/bin/$Configuration/netstandard2.0" -Filter '*.dll' |
  Copy-Item -Destination "$PSScriptRoot/bin/$Configuration/PSModuleLayout/" -Force;
Copy-Item -LiteralPath "$PSScriptRoot/Renouveau.Caffeine.ForPowerShell.psd1" -Destination "$PSScriptRoot/bin/$Configuration/PSModuleLayout/" -Force;
Copy-Item -LiteralPath "$PSScriptRoot/Renouveau.Caffeine.ForPowerShell.Prepare.ps1" -Destination "$PSScriptRoot/bin/$Configuration/PSModuleLayout/" -Force;
Copy-Item -LiteralPath "$PSScriptRoot/../../LICENSE" -Destination "$PSScriptRoot/bin/$Configuration/PSModuleLayout/license.txt" -Force;
Copy-Item -LiteralPath "$PSScriptRoot/NOTICE" -Destination "$PSScriptRoot/bin/$Configuration/PSModuleLayout/" -Force;
Copy-Item -LiteralPath "$PSScriptRoot/icon.png" -Destination "$PSScriptRoot/bin/$Configuration/PSModuleLayout/" -Force;
};
If ($Error.Count -ne $PrevError) { Return; }

If ($Configuration -ne 'Release') { Return; }

Compress-PSResource -Path "$PSScriptRoot/bin/$Configuration/PSModuleLayout" -DestinationPath "$PSScriptRoot/bin/$Configuration";
If ($Error.Count -ne $PrevError) { Return; }

$local:NuPkgSource = @(Get-ChildItem -LiteralPath "$PSScriptRoot/bin/$Configuration" -Filter '*.nupkg');
If ($local:NuPkgSource.Count -ne 1)
{
  Write-Error "No unique *.nupkg found: $PSScriptRoot/bin/$Configuration";
  Return;
}
$NuPkgSource = $NuPkgSource[0];
$NuPkgName   = $NuPkgSource.Name;
$NuPkgSource = $NuPkgSource.FullName;

If (-not (Test-Path -LiteralPath "$PSScriptRoot/../../packed/Release"))
{
  New-Item -Path "$PSScriptRoot/../../packed" -Name 'Release' -ItemType 'Directory' | Out-Null;
}
If (-not (Test-Path -LiteralPath "$PSScriptRoot/../../packed/Release" -PathType Container))
{
  Write-Error "Not a directory: $PSScriptRoot/../../packed/Release";
  Return;
}
& "$PSScriptRoot/../../Convert-NupkgToDet.ps1" `
  -InputFile $NuPkgSource `
  -OutputFile "$PSScriptRoot/../../packed/Release/$NuPkgName" `
  -SmallestSize -Strict:$false -NonInteractive:$false;
