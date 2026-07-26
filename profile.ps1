#Requires -Version 7.0

# This file is sourced by the small, managed block that setup.ps1 adds to the
# current user's all-hosts PowerShell profile.
$env:WINFILES_DIR = [System.IO.Path]::GetFullPath($PSScriptRoot)

$_winfilesSettingsScript = Join-Path -Path $env:WINFILES_DIR -ChildPath 'modules\Settings.ps1'
. $_winfilesSettingsScript
$WinfilesSettings = Get-WinfilesSetting

$_winfilesModules = @(
    @{ Name = 'Environment.ps1'; Enabled = $true }
    @{ Name = 'PSReadLine.ps1'; Enabled = $true }
    @{ Name = 'Aliases.ps1'; Enabled = -not $WinfilesSettings.DisableAliases }
    @{ Name = 'Completions.ps1'; Enabled = -not $WinfilesSettings.DisableCompletions }
    @{ Name = 'Integrations.ps1'; Enabled = -not $WinfilesSettings.DisableModules }
    @{ Name = 'Prompt.ps1'; Enabled = -not $WinfilesSettings.DisablePrompt }
)

foreach ($_winfilesModule in $_winfilesModules) {
    if (-not $_winfilesModule.Enabled) {
        continue
    }

    $_winfilesModulePath = Join-Path -Path $env:WINFILES_DIR -ChildPath "modules\$($_winfilesModule.Name)"
    if (Test-Path -LiteralPath $_winfilesModulePath -PathType Leaf) {
        . $_winfilesModulePath
    }
}

$_winfilesLocalProfile = if ($env:WINFILES_LOCAL_PROFILE) {
    $env:WINFILES_LOCAL_PROFILE
}
else {
    Join-Path -Path ([Environment]::GetFolderPath('UserProfile')) -ChildPath '.config\winfiles\local.ps1'
}

if (Test-Path -LiteralPath $_winfilesLocalProfile -PathType Leaf) {
    . $_winfilesLocalProfile
}

Remove-Variable -Name _winfilesLocalProfile, _winfilesModule, _winfilesModulePath,
    _winfilesModules, _winfilesSettingsScript -ErrorAction SilentlyContinue
