function ConvertTo-WinfilesBoolean {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if ($Value -is [bool]) {
        return $Value
    }

    if ($Value -is [string]) {
        switch -CaseSensitive ($Value) {
            'true' { return $true }
            'false' { return $false }
        }
    }

    throw "Setting '$Name' must be the Boolean value `$true or `$false."
}

function Get-WinfilesSetting {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = (
            Join-Path -Path $env:WINFILES_DIR -ChildPath 'config\settings.psd1'
        )
    )

    $settings = [ordered]@{
        DisableAliases     = $false
        DisablePrompt      = $false
        DisableModules     = $false
        DisableCompletions = $false
        DisablePredictions = $false
        DisableFzf         = $false
    }

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $fileSettings = Import-PowerShellDataFile -LiteralPath $Path
        foreach ($key in $fileSettings.Keys) {
            if (-not $settings.Contains($key)) {
                throw "Unknown setting '$key' in '$Path'."
            }

            $settings[$key] = ConvertTo-WinfilesBoolean -Value $fileSettings[$key] -Name $key
        }
    }

    $environmentOverrides = @{
        DisableAliases     = 'WINFILES_DISABLE_ALIASES'
        DisablePrompt      = 'WINFILES_DISABLE_PROMPT'
        DisableModules     = 'WINFILES_DISABLE_MODULES'
        DisableCompletions = 'WINFILES_DISABLE_COMPLETIONS'
        DisablePredictions = 'WINFILES_DISABLE_PREDICTIONS'
        DisableFzf         = 'WINFILES_DISABLE_FZF'
    }

    foreach ($key in $environmentOverrides.Keys) {
        $environmentName = $environmentOverrides[$key]
        $environmentValue = [Environment]::GetEnvironmentVariable($environmentName)
        if ($null -ne $environmentValue) {
            $settings[$key] = ConvertTo-WinfilesBoolean -Value $environmentValue -Name $environmentName
        }
    }

    return [PSCustomObject]$settings
}
