function Write-WinfilesLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Information $Message -InformationAction Continue
}

function Read-WinfilesChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Prompt,

        [Parameter()]
        [bool]$Default = $true
    )

    $defaultText = if ($Default) { 'yes' } else { 'no' }
    while ($true) {
        $answer = (Read-Host "$Prompt (yes [y], no [n]) [$defaultText]").Trim().ToLowerInvariant()
        if (-not $answer) {
            return $Default
        }

        switch ($answer) {
            { $_ -in @('y', 'yes') } { return $true }
            { $_ -in @('n', 'no') } { return $false }
            default { Write-Warning "Invalid option '$answer'. Use 'y' or 'n'." }
        }
    }
}

function Invoke-WinfilesNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter()]
        [object[]]$ArgumentList = @()
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "'$FilePath' exited with code $LASTEXITCODE."
    }
}

function Get-WinfilesStatePath {
    [CmdletBinding()]
    param()

    if ($env:WINFILES_STATE_PATH) {
        return [System.IO.Path]::GetFullPath($env:WINFILES_STATE_PATH)
    }

    $stateRoot = [Environment]::GetFolderPath('LocalApplicationData')
    if (-not $stateRoot) {
        $stateRoot = if ($env:XDG_STATE_HOME) {
            $env:XDG_STATE_HOME
        }
        else {
            Join-Path -Path ([Environment]::GetFolderPath('UserProfile')) -ChildPath '.local\state'
        }
    }

    return Join-Path -Path $stateRoot -ChildPath 'winfiles\install-state.json'
}

function Get-WinfilesState {
    [CmdletBinding()]
    param()

    $statePath = Get-WinfilesStatePath
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return [ordered]@{
            Packages = @()
            Modules  = @()
        }
    }

    $state = Get-Content -LiteralPath $statePath -Raw |
        ConvertFrom-Json -AsHashtable
    if (-not $state.ContainsKey('Packages')) {
        $state.Packages = @()
    }
    if (-not $state.ContainsKey('Modules')) {
        $state.Modules = @()
    }

    return $state
}

function Save-WinfilesState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State
    )

    $statePath = Get-WinfilesStatePath
    $stateDirectory = Split-Path -Path $statePath -Parent
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null

    $temporaryPath = "$statePath.$PID.tmp"
    try {
        $State |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $temporaryPath -Encoding utf8NoBOM
        Move-Item -LiteralPath $temporaryPath -Destination $statePath -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Add-WinfilesOwnedPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Id
    )

    $state = Get-WinfilesState
    $alreadyRecorded = @($state.Packages) |
        Where-Object { $_.Id -eq $Id }
    if ($alreadyRecorded) {
        return
    }

    $state.Packages = @($state.Packages) + @(@{ Id = $Id })
    Save-WinfilesState -State $state
}

function Add-WinfilesOwnedModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d+(\.\d+){1,3}([-.][A-Za-z0-9]+)?$')]
        [string]$Version
    )

    $state = Get-WinfilesState
    $alreadyRecorded = @($state.Modules) |
        Where-Object { $_.Name -eq $Name -and $_.Version -eq $Version }
    if ($alreadyRecorded) {
        return
    }

    $state.Modules = @($state.Modules) + @(@{ Name = $Name; Version = $Version })
    Save-WinfilesState -State $state
}

function Get-WinfilesPackageManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    $path = Join-Path -Path $RepositoryRoot -ChildPath 'config\packages.psd1'
    return Import-PowerShellDataFile -LiteralPath $path
}

function Get-WinfilesModuleManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    $path = Join-Path -Path $RepositoryRoot -ChildPath 'config\modules.psd1'
    return Import-PowerShellDataFile -LiteralPath $path
}
