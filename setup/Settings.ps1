function Get-WinfilesPersistedSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    $settings = [ordered]@{
        DisableAliases     = $false
        DisablePrompt      = $false
        DisableModules     = $false
        DisableCompletions = $false
        DisablePredictions = $false
        DisableFzf         = $false
    }
    $settingsPath = Join-Path -Path $RepositoryRoot -ChildPath 'config\settings.psd1'

    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        $fromFile = Import-PowerShellDataFile -LiteralPath $settingsPath
        foreach ($key in $fromFile.Keys) {
            if (-not $settings.Contains($key)) {
                throw "Unknown setting '$key' in '$settingsPath'."
            }
            if ($fromFile[$key] -isnot [bool]) {
                throw "Setting '$key' in '$settingsPath' must be a Boolean."
            }
            $settings[$key] = $fromFile[$key]
        }
    }

    return $settings
}

function Set-WinfilesSetting {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $knownKeys = @(
        'DisableAliases',
        'DisablePrompt',
        'DisableModules',
        'DisableCompletions',
        'DisablePredictions',
        'DisableFzf'
    )

    foreach ($key in $knownKeys) {
        if (-not $Settings.Contains($key) -or $Settings[$key] -isnot [bool]) {
            throw "Setting '$key' must be supplied as a Boolean."
        }
    }
    foreach ($key in $Settings.Keys) {
        if ($key -notin $knownKeys) {
            throw "Unknown setting '$key'."
        }
    }

    $settingsPath = Join-Path -Path $RepositoryRoot -ChildPath 'config\settings.psd1'
    $temporaryPath = "$settingsPath.$PID.tmp"
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('@{')
    foreach ($key in $knownKeys) {
        $value = if ($Settings[$key]) { '$true' } else { '$false' }
        $lines.Add("    $key = $value")
    }
    $lines.Add('}')

    if (-not $PSCmdlet.ShouldProcess($settingsPath, 'Write local winfiles settings')) {
        return
    }

    try {
        Set-Content -LiteralPath $temporaryPath -Value $lines -Encoding utf8NoBOM
        Move-Item -LiteralPath $temporaryPath -Destination $settingsPath -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}
