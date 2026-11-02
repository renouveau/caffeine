@{

RootModule = 'RnvPs.Caffeine.psm1'
ModuleVersion = '0.1.1'
# CompatiblePSEditions = @()
GUID = '22b8071a-405b-41e3-961f-be03c1ce8a26'

Author = 'Ji Luo'
CompanyName = 'Renouveau'
Copyright = 'Copyright © 2026 Ji Luo, all rights reserved.'
Description = 'Enables requesting the system idle timers not time out so that long-running tasks continue uninterrupted.'

PowerShellVersion = '5.1'
# PowerShellHostName = ''
# PowerShellHostVersion = ''
# DotNetFrameworkVersion = ''
# ClrVersion = ''
# ProcessorArchitecture = ''

# RequiredModules = @()
RequiredAssemblies = @('Renouveau.Caffeine.dll')
# ScriptsToProcess = @()
# TypesToProcess = @()
# FormatsToProcess = @()
# NestedModules = @()

FunctionsToExport = @('Invoke-CommandAwake')
CmdletsToExport = @()
VariablesToExport = @()
AliasesToExport = @()
# DscResourcesToExport = @()

# ModuleList = @()
# FileList = @()

PrivateData = @{
  PSData = @{
    Tags = @('awake', 'sleep', 'idle', 'display', 'screen', 'power-management', 'windows')
    LicenseUri = 'https://github.com/renouveau/caffeine/blob/main/LICENSE'
    ProjectUri = 'https://github.com/renouveau/caffeine'
    IconUri = 'https://raw.githubusercontent.com/renouveau/caffeine/refs/heads/main/src/ForPowerShell/icon.png'
    ReleaseNotes = 'Improved thread-safety during shutdown/unload in .NET Framework. Currently only supporting Windows.'
    # Prerelease = ''
    RequireLicenseAcceptance = $true
    # ExternalModuleDependencies = @()
  } # <-- PSData
} # <---- PrivateData

# HelpInfoURI = ''
# DefaultCommandPrefix = ''

}
