#Requires -Version 7.0

<#
.SYNOPSIS
    Removes explicitly selected components installed or managed by winfiles.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()][switch]$All,
    [Parameter()][switch]$ShellProfile,
    [Parameter()][switch]$Packages,
    [Parameter()][switch]$PowerShellModules,
    [Parameter()][switch]$Settings,
    [Parameter()][switch]$CompletionCache,
    [Parameter()][switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
. (Join-Path -Path $repositoryRoot -ChildPath 'setup\Common.ps1')
. (Join-Path -Path $repositoryRoot -ChildPath 'setup\Modules.ps1')
. (Join-Path -Path $repositoryRoot -ChildPath 'setup\Profile.ps1')

try {
    $explicitSelection = $All -or $ShellProfile -or $Packages -or
        $PowerShellModules -or $Settings -or $CompletionCache
    $removeProfile = $All -or $ShellProfile
    $removePackages = $All -or $Packages
    $removeModules = $All -or $PowerShellModules
    $removeSettings = $All -or $Settings
    $removeCompletions = $All -or $CompletionCache

    if (-not $explicitSelection) {
        Write-Information '========================================' -InformationAction Continue
        Write-Information '  Winfiles Interactive Uninstall' -InformationAction Continue
        Write-Information '========================================' -InformationAction Continue

        $removeProfile = Read-WinfilesChoice -Prompt 'Remove the managed profile loader?' -Default $false
        $removePackages = Read-WinfilesChoice `
            -Prompt 'Remove packages recorded as installed by winfiles?' -Default $false
        $removeModules = Read-WinfilesChoice `
            -Prompt 'Remove modules recorded as installed by winfiles?' -Default $false
        $removeSettings = Read-WinfilesChoice -Prompt 'Remove local module settings?' -Default $false
        $removeCompletions = Read-WinfilesChoice -Prompt 'Remove completion caches?' -Default $false
    }

    if (-not ($removeProfile -or $removePackages -or $removeModules -or
            $removeSettings -or $removeCompletions)) {
        Write-WinfilesLog 'No components selected; nothing was removed.'
        return
    }

    Write-Information 'Requested removals:' -InformationAction Continue
    if ($removeProfile) { Write-WinfilesLog '  - managed PowerShell profile loader' }
    if ($removePackages) { Write-WinfilesLog '  - winfiles-owned WinGet packages' }
    if ($removeModules) { Write-WinfilesLog '  - winfiles-owned PowerShell module versions' }
    if ($removeSettings) { Write-WinfilesLog '  - local settings file' }
    if ($removeCompletions) { Write-WinfilesLog '  - generated completion cache' }

    if (-not $Force -and -not $WhatIfPreference) {
        $confirmation = Read-Host "Type 'uninstall' to continue"
        if ($confirmation -cne 'uninstall') {
            throw 'Uninstall aborted.'
        }
    }

    if ($removeProfile) {
        Remove-WinfilesProfileLoader -ProfilePath $PROFILE.CurrentUserAllHosts
    }

    $state = Get-WinfilesState

    if ($removePackages) {
        $winget = Get-Command -Name winget -CommandType Application -ErrorAction SilentlyContinue
        if (-not $winget -and @($state.Packages).Count -gt 0) {
            throw 'WinGet is required to remove packages recorded by winfiles.'
        }

        $remainingPackages = [System.Collections.Generic.List[object]]::new()
        foreach ($package in @($state.Packages)) {
            if (-not $PSCmdlet.ShouldProcess($package.Id, 'Uninstall winfiles-owned package')) {
                $remainingPackages.Add($package)
                continue
            }

            Invoke-WinfilesNativeCommand -FilePath $winget.Source -ArgumentList @(
                'uninstall',
                '--id', $package.Id,
                '--exact',
                '--source', 'winget',
                '--disable-interactivity'
            )
        }
        $state.Packages = @($remainingPackages)
    }

    if ($removeModules) {
        $remainingModules = [System.Collections.Generic.List[object]]::new()
        foreach ($module in @($state.Modules)) {
            if (-not $PSCmdlet.ShouldProcess(
                    "$($module.Name) $($module.Version)",
                    'Uninstall winfiles-owned module version'
                )) {
                $remainingModules.Add($module)
                continue
            }

            Remove-WinfilesLoadedPowerShellModule -Name $module.Name `
                -Version $module.Version
            if (Get-Command -Name Uninstall-PSResource -ErrorAction SilentlyContinue) {
                Uninstall-PSResource -Name $module.Name -Version $module.Version -ErrorAction Stop
            }
            elseif (Get-Command -Name Uninstall-Module -ErrorAction SilentlyContinue) {
                Uninstall-Module -Name $module.Name -RequiredVersion $module.Version `
                    -Force -ErrorAction Stop
            }
            else {
                throw 'Uninstall-PSResource or Uninstall-Module is required to remove modules.'
            }

            $moduleVersionPath = Get-WinfilesPowerShellModuleVersionPath `
                -Name $module.Name -Version $module.Version
            if (Test-Path -LiteralPath $moduleVersionPath) {
                throw "Module '$($module.Name) $($module.Version)' was only partially removed. " +
                    "Close other PowerShell sessions and rerun uninstall."
            }
        }
        $state.Modules = @($remainingModules)
    }

    if ($removeSettings) {
        $settingsPath = Join-Path -Path $repositoryRoot -ChildPath 'config\settings.psd1'
        if ((Test-Path -LiteralPath $settingsPath -PathType Leaf) -and
            $PSCmdlet.ShouldProcess($settingsPath, 'Remove local winfiles settings')) {
            Remove-Item -LiteralPath $settingsPath -Force
        }
    }

    if ($removeCompletions) {
        . (Join-Path -Path $repositoryRoot -ChildPath 'modules\Completions.ps1')
        $completionPath = Get-WinfilesCompletionCachePath
        if ((Test-Path -LiteralPath $completionPath -PathType Container) -and
            $PSCmdlet.ShouldProcess($completionPath, 'Remove generated completion cache')) {
            Remove-Item -LiteralPath $completionPath -Recurse -Force
        }
    }

    if ($removePackages -or $removeModules) {
        $statePath = Get-WinfilesStatePath
        if (@($state.Packages).Count -eq 0 -and @($state.Modules).Count -eq 0) {
            if ((Test-Path -LiteralPath $statePath -PathType Leaf) -and
                $PSCmdlet.ShouldProcess($statePath, 'Remove empty winfiles ownership record')) {
                Remove-Item -LiteralPath $statePath -Force
            }
        }
        elseif ($PSCmdlet.ShouldProcess($statePath, 'Update winfiles ownership record')) {
            Save-WinfilesState -State $state
        }
    }

    Write-WinfilesLog 'Uninstall flow complete. Unrelated profile content was left unchanged.'
}
catch {
    Write-Error "Winfiles uninstall failed: $($_.Exception.Message)"
    exit 1
}
