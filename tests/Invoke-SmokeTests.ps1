#Requires -Version 7.0

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path -Path $PSScriptRoot -ChildPath '..')
)
$temporaryRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) `
    -ChildPath "winfiles-tests-$([guid]::NewGuid().ToString('N'))"
$originalStatePath = [Environment]::GetEnvironmentVariable('WINFILES_STATE_PATH')

function Assert-WinfilesCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

try {
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    $env:WINFILES_DIR = $repositoryRoot
    . (Join-Path -Path $repositoryRoot -ChildPath 'modules\Settings.ps1')
    . (Join-Path -Path $repositoryRoot -ChildPath 'setup\Common.ps1')
    . (Join-Path -Path $repositoryRoot -ChildPath 'setup\Modules.ps1')
    . (Join-Path -Path $repositoryRoot -ChildPath 'setup\Settings.ps1')
    . (Join-Path -Path $repositoryRoot -ChildPath 'setup\Profile.ps1')

    $env:WINFILES_STATE_PATH = Join-Path -Path $temporaryRoot `
        -ChildPath 'install-state.json'
    Add-WinfilesOwnedPackage -Id 'Example.Package'
    Add-WinfilesOwnedPackage -Id 'Example.Package'
    Add-WinfilesOwnedModule -Name 'ExampleModule' -Version '1.2.3'
    Add-WinfilesOwnedModule -Name 'ExampleModule' -Version '1.2.3'
    $state = Get-WinfilesState
    Assert-WinfilesCondition -Condition (@($state.Packages).Count -eq 1) `
        -Message 'Package ownership state was not idempotent.'
    Assert-WinfilesCondition -Condition ($state.Packages[0].Id -eq 'Example.Package') `
        -Message 'First package ownership entry was not recorded.'
    Assert-WinfilesCondition -Condition (@($state.Modules).Count -eq 1) `
        -Message 'Module ownership state was not idempotent.'

    $moduleRoot = Join-Path -Path $temporaryRoot -ChildPath 'Modules'
    $versionPath = Get-WinfilesPowerShellModuleVersionPath `
        -Name 'IncompleteTestModule' -Version '1.2.3' -ModuleRoot $moduleRoot
    New-Item -ItemType Directory -Path $versionPath -Force | Out-Null
    'partial package content' |
        Set-Content -LiteralPath (
            Join-Path -Path $versionPath -ChildPath 'IncompleteTestModule.dll'
        ) -Encoding utf8NoBOM
    Remove-WinfilesStalePowerShellModuleVersion `
        -Name 'IncompleteTestModule' -Version '1.2.3' -ModuleRoot $moduleRoot
    Assert-WinfilesCondition -Condition (-not (Test-Path -LiteralPath $versionPath)) `
        -Message 'Incomplete PowerShell module directory was not repaired.'

    $quarantinePath = Join-Path -Path $moduleRoot `
        -ChildPath '.winfiles-stale\IncompleteTestModule-1.2.3-old'
    New-Item -ItemType Directory -Path $quarantinePath -Force | Out-Null
    'stale package content' |
        Set-Content -LiteralPath (
            Join-Path -Path $quarantinePath -ChildPath 'IncompleteTestModule.dll'
        ) -Encoding utf8NoBOM
    Remove-WinfilesStalePowerShellModuleVersion `
        -Name 'IncompleteTestModule' -Version '1.2.3' -ModuleRoot $moduleRoot
    Assert-WinfilesCondition -Condition (-not (Test-Path -LiteralPath $quarantinePath)) `
        -Message 'Old PowerShell module quarantine was not cleaned.'

    $settingsPath = Join-Path -Path $temporaryRoot -ChildPath 'settings.psd1'
    @'
@{
    DisableAliases = $true
    DisableFzf = $true
}
'@ | Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM
    $settings = Get-WinfilesSetting -Path $settingsPath
    Assert-WinfilesCondition -Condition $settings.DisableAliases `
        -Message 'Settings file Boolean was not loaded.'
    Assert-WinfilesCondition -Condition (-not $settings.DisablePrompt) `
        -Message 'Default setting was not preserved.'

    try {
        $env:WINFILES_DISABLE_PROMPT = 'false'
        $overrideSettings = Get-WinfilesSetting -Path $settingsPath
        Assert-WinfilesCondition -Condition (-not $overrideSettings.DisablePrompt) `
            -Message 'Environment override was not honored.'
    }
    finally {
        Remove-Item Env:\WINFILES_DISABLE_PROMPT -ErrorAction SilentlyContinue
    }

    $invalidSettingsPath = Join-Path -Path $temporaryRoot -ChildPath 'invalid.psd1'
    '@{ UnknownSetting = $true }' |
        Set-Content -LiteralPath $invalidSettingsPath -Encoding utf8NoBOM
    $rejectedUnknownSetting = $false
    try {
        Get-WinfilesSetting -Path $invalidSettingsPath | Out-Null
    }
    catch {
        $rejectedUnknownSetting = $true
    }
    Assert-WinfilesCondition -Condition $rejectedUnknownSetting `
        -Message 'Unknown setting was accepted.'

    $settingsRepository = Join-Path -Path $temporaryRoot -ChildPath 'repository'
    New-Item -ItemType Directory -Path (
        Join-Path -Path $settingsRepository -ChildPath 'config'
    ) -Force | Out-Null
    $settingsToWrite = [ordered]@{
        DisableAliases     = $true
        DisablePrompt      = $false
        DisableModules     = $true
        DisableCompletions = $false
        DisablePredictions = $true
        DisableFzf         = $false
    }
    Set-WinfilesSetting -RepositoryRoot $settingsRepository -Settings $settingsToWrite
    $writtenSettings = Import-PowerShellDataFile -LiteralPath (
        Join-Path -Path $settingsRepository -ChildPath 'config\settings.psd1'
    )
    Assert-WinfilesCondition -Condition ($writtenSettings.Keys.Count -eq 6) `
        -Message 'Settings writer did not emit the expected keys.'

    $profilePath = Join-Path -Path $temporaryRoot -ChildPath 'profile.ps1'
    "Write-Output 'keep me'`n" |
        Set-Content -LiteralPath $profilePath -Encoding utf8NoBOM -NoNewline
    Set-WinfilesProfileLoader -ProfilePath $profilePath -RepositoryRoot $repositoryRoot
    $firstProfileContent = Get-Content -LiteralPath $profilePath -Raw
    $firstBackupCount = @(Get-ChildItem -Path "$profilePath.winfiles.bak.*").Count
    Set-WinfilesProfileLoader -ProfilePath $profilePath -RepositoryRoot $repositoryRoot
    $secondProfileContent = Get-Content -LiteralPath $profilePath -Raw
    $secondBackupCount = @(Get-ChildItem -Path "$profilePath.winfiles.bak.*").Count

    Assert-WinfilesCondition -Condition (
        ([regex]::Matches($firstProfileContent, '# >>> winfiles >>>')).Count -eq 1
    ) -Message 'Managed profile loader was not written exactly once.'
    Assert-WinfilesCondition -Condition ($firstBackupCount -eq 1) `
        -Message 'Profile backup was not created.'
    Assert-WinfilesCondition -Condition ($firstProfileContent -ceq $secondProfileContent) `
        -Message 'Profile loader installation is not idempotent.'
    Assert-WinfilesCondition -Condition ($secondBackupCount -eq 1) `
        -Message 'Idempotent profile installation created another backup.'

    Remove-WinfilesProfileLoader -ProfilePath $profilePath
    $removedProfileContent = Get-Content -LiteralPath $profilePath -Raw
    Assert-WinfilesCondition -Condition ($removedProfileContent -match 'keep me') `
        -Message 'Profile loader removal deleted unrelated content.'
    Assert-WinfilesCondition -Condition ($removedProfileContent -notmatch '# >>> winfiles >>>') `
        -Message 'Profile loader removal left the managed block behind.'

    $legacyContent = @'
fnm env --use-on-cd | Out-String | Invoke-Expression
oh-my-posh init pwsh --config "C:\theme.json" | Invoke-Expression
. "C:\Users\Someone\AppData\Local\sync-ssh\sync.ps1"
'@
    $migratedContent = Remove-WinfilesKnownInitializer -Content $legacyContent
    Assert-WinfilesCondition -Condition ($migratedContent -notmatch 'Invoke-Expression') `
        -Message 'Known legacy initializers were not removed.'
    Assert-WinfilesCondition -Condition ($migratedContent -match 'sync-ssh') `
        -Message 'Migration removed an unrelated SSH initializer.'

    $promptPath = Join-Path -Path $repositoryRoot -ChildPath 'config\oh-my-posh.json'
    $promptText = Get-Content -LiteralPath $promptPath -Raw
    $prompt = $promptText | ConvertFrom-Json
    Assert-WinfilesCondition -Condition ($prompt.version -eq 3) `
        -Message 'Oh My Posh configuration is invalid.'
    Assert-WinfilesCondition -Condition ($promptText -notmatch '"shell"\s*:\s*"bash"') `
        -Message 'Oh My Posh configuration still contains a Bash-only command.'

    $overrideNames = @(
        'WINFILES_DISABLE_ALIASES',
        'WINFILES_DISABLE_PROMPT',
        'WINFILES_DISABLE_MODULES',
        'WINFILES_DISABLE_COMPLETIONS',
        'WINFILES_DISABLE_PREDICTIONS',
        'WINFILES_DISABLE_FZF'
    )
    $originalOverrides = @{}
    try {
        foreach ($name in $overrideNames) {
            $originalOverrides[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, 'true')
        }
        $env:WINFILES_LOCAL_PROFILE = Join-Path -Path $temporaryRoot -ChildPath 'missing-local.ps1'
        . (Join-Path -Path $repositoryRoot -ChildPath 'profile.ps1')
        Assert-WinfilesCondition -Condition ($env:WINFILES_DIR -eq $repositoryRoot) `
            -Message 'Managed profile did not resolve the repository root.'
        Assert-WinfilesCondition -Condition $WinfilesSettings.DisablePrompt `
            -Message 'Managed profile did not load environment overrides.'
    }
    finally {
        foreach ($name in $overrideNames) {
            $originalValue = $originalOverrides[$name]
            if ($null -eq $originalValue) {
                Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable($name, $originalValue)
            }
        }
        Remove-Item Env:\WINFILES_LOCAL_PROFILE -ErrorAction SilentlyContinue
    }

    Write-Information 'ok - dependency-free behavioral smoke tests' -InformationAction Continue
}
catch {
    Write-Error "Smoke test failed: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($null -eq $originalStatePath) {
        Remove-Item Env:\WINFILES_STATE_PATH -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable(
            'WINFILES_STATE_PATH',
            $originalStatePath
        )
    }
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
