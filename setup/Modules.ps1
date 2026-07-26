function Get-WinfilesPowerShellModuleVersionPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d+(\.\d+){1,3}([-.][A-Za-z0-9]+)?$')]
        [string]$Version,

        [Parameter()]
        [string]$ModuleRoot
    )

    if (-not $ModuleRoot) {
        $documentsPath = [Environment]::GetFolderPath('MyDocuments')
        if (-not $documentsPath) {
            throw 'The current user Documents directory could not be resolved.'
        }

        $ModuleRoot = Join-Path -Path $documentsPath -ChildPath 'PowerShell\Modules'
    }

    return Join-Path -Path $ModuleRoot -ChildPath "$Name\$Version"
}

function Remove-WinfilesLoadedPowerShellModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d+(\.\d+){1,3}([-.][A-Za-z0-9]+)?$')]
        [string]$Version
    )

    $requiredVersion = [version]$Version
    $loadedModules = Get-Module -Name $Name -All |
        Where-Object Version -EQ $requiredVersion
    foreach ($loadedModule in @($loadedModules)) {
        Remove-Module -ModuleInfo $loadedModule -Force -ErrorAction Stop
    }
}

function Remove-WinfilesStalePowerShellModuleVersion {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d+(\.\d+){1,3}([-.][A-Za-z0-9]+)?$')]
        [string]$Version,

        [Parameter()]
        [string]$ModuleRoot
    )

    $versionPath = Get-WinfilesPowerShellModuleVersionPath -Name $Name `
        -Version $Version -ModuleRoot $ModuleRoot
    $moduleNamePath = Split-Path -Path $versionPath -Parent
    $resolvedModuleRoot = Split-Path -Path $moduleNamePath -Parent
    $quarantineRoot = Join-Path -Path $resolvedModuleRoot `
        -ChildPath '.winfiles-stale'
    if (Test-Path -LiteralPath $quarantineRoot -PathType Container) {
        $quarantinePrefix = "$Name-$Version-"
        $oldQuarantines = Get-ChildItem -LiteralPath $quarantineRoot -Directory |
            Where-Object Name -Like "$quarantinePrefix*"
        foreach ($oldQuarantine in @($oldQuarantines)) {
            if (-not $PSCmdlet.ShouldProcess(
                    $oldQuarantine.FullName,
                    'Remove quarantined PowerShell module directory'
                )) {
                continue
            }

            try {
                Remove-Item -LiteralPath $oldQuarantine.FullName `
                    -Recurse -Force -ErrorAction Stop
            }
            catch {
                Write-Verbose "Quarantined module directory is still locked: " +
                    "$($oldQuarantine.FullName)"
            }
        }
    }

    if (-not (Test-Path -LiteralPath $versionPath -PathType Container)) {
        return
    }

    $requiredVersion = [version]$Version
    $installed = Get-Module -ListAvailable -Name $Name |
        Where-Object Version -EQ $requiredVersion |
        Select-Object -First 1
    if ($installed) {
        return
    }

    if (-not $PSCmdlet.ShouldProcess(
            $versionPath,
            'Remove incomplete PowerShell module version'
        )) {
        return
    }

    Remove-WinfilesLoadedPowerShellModule -Name $Name -Version $Version
    try {
        Remove-Item -LiteralPath $versionPath -Recurse -Force -ErrorAction Stop
    }
    catch {
        $removalMessage = $_.Exception.Message
        $quarantinePath = Join-Path -Path $quarantineRoot -ChildPath (
            "$Name-$Version-$([guid]::NewGuid().ToString('N'))"
        )
        try {
            New-Item -ItemType Directory -Path $quarantineRoot -Force | Out-Null
            Move-Item -LiteralPath $versionPath -Destination $quarantinePath `
                -ErrorAction Stop
        }
        catch {
            throw "Cannot repair the incomplete module '$Name $Version' at " +
                "'$versionPath'. Removal failed: $removalMessage. Moving the " +
                "locked directory aside also failed: $($_.Exception.Message)"
        }

        Write-Warning "Moved locked incomplete module files to '$quarantinePath'. " +
            'A later setup run will remove them after the locking process exits.'
        return
    }

    Write-WinfilesLog "Removed incomplete module directory '$versionPath'."
}

function Install-WinfilesPowerShellModule {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter()]
        [switch]$IncludeDevelopment
    )

    $manifest = Get-WinfilesModuleManifest -RepositoryRoot $RepositoryRoot
    $modules = @($manifest.Runtime)
    if ($IncludeDevelopment) {
        $modules += @($manifest.Development)
    }

    foreach ($module in $modules) {
        $requiredVersion = [version]$module.Version
        $installed = Get-Module -ListAvailable -Name $module.Name |
            Where-Object Version -EQ $requiredVersion |
            Select-Object -First 1
        if ($installed) {
            Write-WinfilesLog "$($module.Name) $requiredVersion is already installed."
            continue
        }

        Remove-WinfilesStalePowerShellModuleVersion -Name $module.Name `
            -Version $module.Version

        if (-not $PSCmdlet.ShouldProcess(
                "$($module.Name) $requiredVersion",
                'Install PowerShell module for the current user'
            )) {
            continue
        }

        if (Get-Command -Name Install-PSResource -ErrorAction SilentlyContinue) {
            Install-PSResource -Name $module.Name -Version $module.Version `
                -Scope CurrentUser -Repository PSGallery -TrustRepository -ErrorAction Stop
        }
        elseif (Get-Command -Name Install-Module -ErrorAction SilentlyContinue) {
            Install-Module -Name $module.Name -RequiredVersion $module.Version `
                -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
        }
        else {
            throw 'Install-PSResource or Install-Module is required to install PowerShell modules.'
        }

        Add-WinfilesOwnedModule -Name $module.Name -Version $module.Version
    }
}
