<#

SPDX-FileCopyrightText: Copyright 2026 Ji Luo, all rights reserved.
SPDX-License-Identifier: MIT

This file is part of Renouveau Caffeine, available under the MIT license.
https://github.com/renouveau/caffeine

#>

& { [CmdletBinding()] Param()

$local:clrv = [System.Environment]::Version;

If ($false)
{
  # This fake branch improves Git diff when adding future .NET versions.
}
ElseIf ($clrv.Major -ge 7)
{
  $clrv = 'net7.0';
}
ElseIf ($clrv -ge [System.Version]::new(4, 0, 30319, 42000) -and
  $PSVersionTable.PSEdition -eq 'Desktop' -and
  [System.Version]::new((Get-Item -LiteralPath ([object].Assembly.Location)).VersionInfo.ProductVersion) -ge [System.Version]::new(4, 6, 1))
{
  $clrv = 'net461';
}
Else
{
  Write-Error 'RnvPs.Caffeine: This module requires .NET Framework 4.6.1+ or .NET 7.0+.';
  Return;
}

Write-Verbose "RnvPs.Caffeine: CLR = $clrv";

Add-Type -LiteralPath ([System.IO.Path]::Combine($PSScriptRoot, $clrv, 'Renouveau.Caffeine.dll'));

} -ErrorAction 'Stop' | Out-Null;

Function Invoke-CommandAwake
{
<#
.SYNOPSIS
Runs a script block while requesting that the system idle timers not time out.

.DESCRIPTION
Before the script block is invoked, `Invoke-CommandAwake` makes persistent power request(s) so that the system do not idle while the script runs.  When the script completes (normally or exceptionally), the request(s) is/are cancelled.  The command-related parameters are similar to the simplest overload of `Invoke-Command`.

.LINK
https://github.com/renouveau/caffeine

.PARAMETER NoIdleSleep
Prevents the system from sleeping automatically.
- This is supported on Windows.  If Connected Standby is enabled and the device on battery power, this request is ignored 5 minutes after the system idle timer times out.
- This is not supported elsewhere.

.PARAMETER NoIdleDisplay
Prevents the display from being turn off automatically.
- This is supported on Windows.
- This is not supported elsewhere.

.PARAMETER NoSleep
Prevents the system from entering sleep even if the user initiates it.
- This is supported on Windows.  However, it is ignored unless the system uses S3 sleep.
- This is not supported elsewhere.

.PARAMETER Permissive
Runs the command even if one or more requests are not supported.  By default, the execution fails immediately if one or more requests are not supported.  Specifying this switch does not allow the command to run when the request(s) fail(s) for other reasons (such as a failure of native API call).

.PARAMETER NoUsage
Do not output usage hints to the warning stream when an unusual usage is detected.

.PARAMETER ScriptBlock
See `InProcess` parameter set of `Invoke-Command`.

.PARAMETER ArgumentList
See `InProcess` parameter set of `Invoke-Command`.

.PARAMETER InputObject
See `InProcess` parameter set of `Invoke-Command`, except this parameter does not take value from the pipeline.

.EXAMPLE
# Prevent display/computer from idling until Ctrl+C.
Invoke-CommandAwake -NoIdleSleep -NoIdleDisplay { while ($true) { Start-Sleep 60; } };

.EXAMPLE
# Run a benchmark across commits and save the results.
# Cool down the computer before each execution.
# Prevent the computer from sleeping during the cooldown.
Invoke-CommandAwake -NoIdleSleep -NoIdleDisplay {
  $commits = @('a', 'b', 'c');
  0..($commits.Count - 1) | ForEach-Object {
    git checkout ($commits[$_]) --;
    dotnet build -c Release;
    Start-Sleep 600;
    Push-Location './Benchmarks/bin/Release/net10.0';
    ./Benchmarks --filter *bench1*;
    Rename-Item 'BenchmarkDotNet.Artifacts' "BenchmarkDotNet.Artifacts-$_-$($commits[$_])";
    Pop-Location;
  };
};

#>
[CmdletBinding(PositionalBinding=$false)]
Param
(
  [Parameter(Mandatory=$true,Position=0)]
  [Alias('Command')]
  [scriptblock]$ScriptBlock,
  [Alias('Args')]
  [object[]]$ArgumentList,
  [PSObject]$InputObject,
  [switch]$NoUsage,
  [switch]$NoIdleSleep,
  [switch]$NoIdleDisplay,
  [switch]$NoSleep,
  [switch]$Permissive
)

$private:preferred = [Renouveau.Caffeine.PowerRequestFlags]::None;
If ($NoIdleSleep)   { $preferred = $preferred -bor [Renouveau.Caffeine.PowerRequestFlags]::DoNotIdleSleep;   }
If ($NoIdleDisplay) { $preferred = $preferred -bor [Renouveau.Caffeine.PowerRequestFlags]::DoNotIdleDisplay; }
If ($NoSleep)       { $preferred = $preferred -bor [Renouveau.Caffeine.PowerRequestFlags]::DoNotSleep;       }
$private:minimum = $preferred;
If ($Permissive) { $minimum = [Renouveau.Caffeine.PowerRequestFlags]::None; }
$private:request = $null;

If ($preferred -eq [Renouveau.Caffeine.PowerRequestFlags]::None -and -not $NoUsage)
{
  If (((@('NoIdleSleep', 'NoIdleDisplay', 'NoSleep') | ForEach-Object {
    If ($PSBoundParameters.ContainsKey($_)) { '1' } Else { '' }
  }) -join '') -eq '')
  {
    Write-Warning "No power request switch is specified and the command will run without any power request.`n         Did you forget to specify a switch?";
  }
}

$private:CurrErrActionPref = $ErrorActionPreference;
$local:ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop;
Try
{
  $private:request = [Renouveau.Caffeine.PowerRequest]::Create($preferred, $minimum);
  If ($request.ActiveRequests -ne $preferred)
  {
    Write-Warning "Invoke-CommandAwake: FEWER active requests: $($request.ActiveRequests)";
  }
  Else
  {
    Write-Verbose "Invoke-CommandAwake: active requests: $($request.ActiveRequests)";
  }
  If ($request -ne $null)
  {
    & { [CmdletBinding()] Param()
      Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -InputObject $InputObject;
    } -ErrorAction $CurrErrActionPref;
  }
}
Finally
{
  If ($request -ne $null)
  {
    $request.Dispose();
  }
}

}

Export-ModuleMember -Function 'Invoke-CommandAwake';
