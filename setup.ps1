#Requires -Version 7.0

<#
.SYNOPSIS
    Installs and configures the native Windows terminal environment.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter()][switch]$All,
    [Parameter()][switch]$Core,
    [Parameter()][switch]$Fnm,
    [Parameter()][switch]$ShellProfile,
    [Parameter()][switch]$PowerShellModules,
    [Parameter()][switch]$Completions,
    [Parameter()][switch]$ConfigureModules,
    [Parameter()][switch]$MigrateExistingProfile,
    [Parameter()][switch]$EnableAliases,
    [Parameter()][switch]$DisableAliases,
    [Parameter()][switch]$EnablePrompt,
    [Parameter()][switch]$DisablePrompt,
    [Parameter()][switch]$EnableModules,
    [Parameter()][switch]$DisableModules,
    [Parameter()][switch]$EnableCompletions,
    [Parameter()][switch]$DisableCompletions,
    [Parameter()][switch]$EnablePredictions,
    [Parameter()][switch]$DisablePredictions,
    [Parameter()][switch]$EnableFzf,
    [Parameter()][switch]$DisableFzf,
    [Parameter()]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$NodeVersion = '24.12.0'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$env:WINFILES_DIR = $repositoryRoot

foreach ($scriptName in @(
        'Common.ps1',
        'Core.ps1',
        'Fnm.ps1',
        'Modules.ps1',
        'Settings.ps1',
        'Profile.ps1'
    )) {
    . (Join-Path -Path $repositoryRoot -ChildPath "setup\$scriptName")
}

function Assert-WinfilesSwitchPair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$Enable,
        [Parameter(Mandatory)][bool]$Disable,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Enable -and $Disable) {
        throw "-Enable$Name and -Disable$Name cannot be used together."
    }
}

try {
    Assert-WinfilesSwitchPair -Enable $EnableAliases -Disable $DisableAliases -Name Aliases
    Assert-WinfilesSwitchPair -Enable $EnablePrompt -Disable $DisablePrompt -Name Prompt
    Assert-WinfilesSwitchPair -Enable $EnableModules -Disable $DisableModules -Name Modules
    Assert-WinfilesSwitchPair -Enable $EnableCompletions -Disable $DisableCompletions -Name Completions
    Assert-WinfilesSwitchPair -Enable $EnablePredictions -Disable $DisablePredictions -Name Predictions
    Assert-WinfilesSwitchPair -Enable $EnableFzf -Disable $DisableFzf -Name Fzf

    $settingsSwitchWasUsed = $EnableAliases -or $DisableAliases -or
        $EnablePrompt -or $DisablePrompt -or
        $EnableModules -or $DisableModules -or
        $EnableCompletions -or $DisableCompletions -or
        $EnablePredictions -or $DisablePredictions -or
        $EnableFzf -or $DisableFzf

    $componentSwitchWasUsed = $All -or $Core -or $Fnm -or $ShellProfile -or
        $PowerShellModules -or $Completions -or $ConfigureModules -or
        $MigrateExistingProfile -or $settingsSwitchWasUsed
    $interactive = -not $componentSwitchWasUsed

    $installCore = $All -or $Core
    $installFnm = $All -or $Fnm
    $installProfile = $All -or $ShellProfile
    $installModules = $All -or $PowerShellModules
    $refreshCompletions = $All -or $Completions
    $writeSettings = $ConfigureModules -or $settingsSwitchWasUsed
    $migrateProfiles = $MigrateExistingProfile

    $settings = Get-WinfilesPersistedSetting -RepositoryRoot $repositoryRoot

    if ($interactive) {
        Write-Information '========================================' -InformationAction Continue
        Write-Information '  Winfiles Interactive Setup' -InformationAction Continue
        Write-Information '========================================' -InformationAction Continue

        $installCore = Read-WinfilesChoice -Prompt '1. Install missing core command-line tools?'
        $installFnm = Read-WinfilesChoice -Prompt '2. Configure FNM and Node.js?'
        $installModules = Read-WinfilesChoice -Prompt '3. Install pinned PowerShell modules?'
        $installProfile = Read-WinfilesChoice -Prompt '4. Install the managed profile loader?'
        $refreshCompletions = Read-WinfilesChoice -Prompt '5. Refresh native completion caches?'
        $migrateProfiles = Read-WinfilesChoice `
            -Prompt '6. Migrate known FNM, prompt, CommandNotFound, and Inshellisense initializers?' `
            -Default $false

        Write-Information 'Module configuration:' -InformationAction Continue
        $settings.DisableAliases = -not (
            Read-WinfilesChoice -Prompt '  Enable aliases and helper functions?' `
                -Default (-not $settings.DisableAliases)
        )
        $settings.DisablePrompt = -not (
            Read-WinfilesChoice -Prompt '  Enable the Oh My Posh prompt?' `
                -Default (-not $settings.DisablePrompt)
        )
        $settings.DisableModules = -not (
            Read-WinfilesChoice -Prompt '  Enable PowerShell integrations?' `
                -Default (-not $settings.DisableModules)
        )
        $settings.DisableCompletions = -not (
            Read-WinfilesChoice -Prompt '  Enable native completion caches?' `
                -Default (-not $settings.DisableCompletions)
        )
        $settings.DisablePredictions = -not (
            Read-WinfilesChoice -Prompt '  Enable PSReadLine predictions?' `
                -Default (-not $settings.DisablePredictions)
        )
        $settings.DisableFzf = -not (
            Read-WinfilesChoice -Prompt '  Enable PSFzf integration?' `
                -Default (-not $settings.DisableFzf)
        )
        $writeSettings = $true

        Write-Information '----------------------------------------' -InformationAction Continue
        Write-WinfilesLog "Core tools:             $installCore"
        Write-WinfilesLog "FNM and Node.js:        $installFnm"
        Write-WinfilesLog "PowerShell modules:     $installModules"
        Write-WinfilesLog "Managed profile loader: $installProfile"
        Write-WinfilesLog "Completion cache:       $refreshCompletions"
        Write-WinfilesLog "Profile migration:      $migrateProfiles"
        Write-Information '----------------------------------------' -InformationAction Continue

        if (-not (Read-WinfilesChoice -Prompt 'Proceed with these settings?')) {
            throw 'Setup aborted.'
        }
    }
    else {
        if ($EnableAliases) { $settings.DisableAliases = $false }
        if ($DisableAliases) { $settings.DisableAliases = $true }
        if ($EnablePrompt) { $settings.DisablePrompt = $false }
        if ($DisablePrompt) { $settings.DisablePrompt = $true }
        if ($EnableModules) { $settings.DisableModules = $false }
        if ($DisableModules) { $settings.DisableModules = $true }
        if ($EnableCompletions) { $settings.DisableCompletions = $false }
        if ($DisableCompletions) { $settings.DisableCompletions = $true }
        if ($EnablePredictions) { $settings.DisablePredictions = $false }
        if ($DisablePredictions) { $settings.DisablePredictions = $true }
        if ($EnableFzf) { $settings.DisableFzf = $false }
        if ($DisableFzf) { $settings.DisableFzf = $true }
    }

    if ($writeSettings) {
        Set-WinfilesSetting -RepositoryRoot $repositoryRoot -Settings $settings
    }
    else {
        Write-WinfilesLog 'Keeping the existing local module settings.'
    }

    if ($installCore) {
        Install-WinfilesCore -RepositoryRoot $repositoryRoot
    }
    else {
        Write-WinfilesLog 'Skipping core tools.'
    }

    if ($installFnm) {
        Install-WinfilesFnm -RepositoryRoot $repositoryRoot -NodeVersion $NodeVersion
    }
    else {
        Write-WinfilesLog 'Skipping FNM and Node.js.'
    }

    if ($installModules) {
        Install-WinfilesPowerShellModule -RepositoryRoot $repositoryRoot -IncludeDevelopment
    }
    else {
        Write-WinfilesLog 'Skipping PowerShell modules.'
    }

    if ($refreshCompletions) {
        . (Join-Path -Path $repositoryRoot -ChildPath 'modules\Completions.ps1')
        Update-WinfilesCompletionCache
    }
    else {
        Write-WinfilesLog 'Skipping completion cache refresh.'
    }

    if ($installProfile) {
        Set-WinfilesProfileLoader -ProfilePath $PROFILE.CurrentUserAllHosts `
            -RepositoryRoot $repositoryRoot `
            -MigrateKnownInitializers:$migrateProfiles
    }
    else {
        Write-WinfilesLog 'Skipping the managed profile loader.'
    }

    if ($migrateProfiles) {
        Invoke-WinfilesKnownProfileMigration -ProfilePath $PROFILE.CurrentUserCurrentHost
    }

    Write-WinfilesLog 'Setup complete. Restart PowerShell or run: reload'
}
catch {
    Write-Error "Winfiles setup failed: $($_.Exception.Message)"
    exit 1
}
