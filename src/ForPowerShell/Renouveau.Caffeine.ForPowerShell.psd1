@{

# RootModule = ''
ModuleVersion = '0.0.0'
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
# RequiredAssemblies = @()
ScriptsToProcess = @('Renouveau.Caffeine.ForPowerShell.Prepare.ps1')
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
    Tags = @()
    LicenseUri = 'https://github.com/renouveau/caffeine/blob/main/LICENSE'
    ProjectUri = 'https://github.com/renouveau/caffeine'
    IconUri = 'https://raw.githubusercontent.com/renouveau/caffeine/refs/heads/main/src/ForPowerShell/icon.png'
    ReleaseNotes = ''
    # Prerelease = ''
    RequireLicenseAcceptance = $true
    # ExternalModuleDependencies = @()
  } # <-- PSData
} # <---- PrivateData

# HelpInfoURI = ''
# DefaultCommandPrefix = ''

}
