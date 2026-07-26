BeforeAll {
    $script:RepositoryRoot = [System.IO.Path]::GetFullPath(
        (Join-Path -Path $PSScriptRoot -ChildPath '..')
    )
    $env:WINFILES_DIR = $script:RepositoryRoot

    . (Join-Path -Path $script:RepositoryRoot -ChildPath 'modules\Settings.ps1')
    . (Join-Path -Path $script:RepositoryRoot -ChildPath 'setup\Common.ps1')
    . (Join-Path -Path $script:RepositoryRoot -ChildPath 'setup\Modules.ps1')
    . (Join-Path -Path $script:RepositoryRoot -ChildPath 'setup\Settings.ps1')
    . (Join-Path -Path $script:RepositoryRoot -ChildPath 'setup\Profile.ps1')

    $script:OverrideNames = @(
        'WINFILES_DISABLE_ALIASES',
        'WINFILES_DISABLE_PROMPT',
        'WINFILES_DISABLE_MODULES',
        'WINFILES_DISABLE_COMPLETIONS',
        'WINFILES_DISABLE_PREDICTIONS',
        'WINFILES_DISABLE_FZF'
    )
    $script:OriginalOverrides = @{}
    foreach ($name in $script:OverrideNames) {
        $script:OriginalOverrides[$name] = [Environment]::GetEnvironmentVariable($name)
        Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
    }
    $script:OriginalStatePath = [Environment]::GetEnvironmentVariable(
        'WINFILES_STATE_PATH'
    )
    Remove-Item Env:\WINFILES_STATE_PATH -ErrorAction SilentlyContinue
}

AfterAll {
    foreach ($name in $script:OverrideNames) {
        $originalValue = $script:OriginalOverrides[$name]
        if ($null -eq $originalValue) {
            Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable($name, $originalValue)
        }
    }
    if ($null -eq $script:OriginalStatePath) {
        Remove-Item Env:\WINFILES_STATE_PATH -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable(
            'WINFILES_STATE_PATH',
            $script:OriginalStatePath
        )
    }
}

Describe 'PowerShell source' {
    It 'parses every PowerShell source and data file' {
        $sourceFiles = Get-ChildItem -LiteralPath $script:RepositoryRoot -Recurse -File |
            Where-Object {
                $_.Extension -in @('.ps1', '.psd1', '.psm1') -and
                $_.FullName -notlike (
                    (Join-Path -Path $script:RepositoryRoot -ChildPath '.cache') + '*'
                ) -and
                $_.FullName -notlike (
                    (Join-Path -Path $script:RepositoryRoot -ChildPath '.git') + '*'
                )
            }

        $parseFailures = [System.Collections.Generic.List[string]]::new()
        foreach ($sourceFile in $sourceFiles) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $sourceFile.FullName,
                [ref]$tokens,
                [ref]$errors
            )
            foreach ($parseError in $errors) {
                $parseFailures.Add(
                    "$($sourceFile.FullName):$($parseError.Extent.StartLineNumber): $($parseError.Message)"
                )
            }
        }

        $parseFailures | Should -BeNullOrEmpty
    }

    It 'contains no hard-coded user profile path' {
        $sourceFiles = Get-ChildItem -LiteralPath $script:RepositoryRoot -Recurse -File |
            Where-Object {
                $_.Extension -in @('.ps1', '.psd1', '.json') -and
                $_.FullName -notlike (
                    (Join-Path -Path $script:RepositoryRoot -ChildPath '.cache') + '*'
                ) -and
                $_.FullName -notlike (
                    (Join-Path -Path $script:RepositoryRoot -ChildPath '.git') + '*'
                )
            }
        $forbiddenPath = 'C:' + [System.IO.Path]::DirectorySeparatorChar +
            'Users' + [System.IO.Path]::DirectorySeparatorChar + 'Pablo'
        $pathMatches = $sourceFiles |
            Select-String -Pattern $forbiddenPath -SimpleMatch

        $pathMatches | Should -BeNullOrEmpty
    }

    It 'contains valid Oh My Posh JSON without Bash-only commands' {
        $promptPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'config\oh-my-posh.json'
        $promptText = Get-Content -LiteralPath $promptPath -Raw
        $prompt = $promptText | ConvertFrom-Json

        $prompt.version | Should -Be 3
        $promptText | Should -Not -Match '"shell"\s*:\s*"bash"'
    }
}

Describe 'Settings' {
    It 'uses defaults and accepts file values' {
        $settingsPath = Join-Path -Path $TestDrive -ChildPath 'settings.psd1'
        @'
@{
    DisableAliases = $true
    DisableFzf = $true
}
'@ | Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM

        $settings = Get-WinfilesSetting -Path $settingsPath

        $settings.DisableAliases | Should -BeTrue
        $settings.DisableFzf | Should -BeTrue
        $settings.DisablePrompt | Should -BeFalse
    }

    It 'lets literal environment values override the settings file' {
        $settingsPath = Join-Path -Path $TestDrive -ChildPath 'override.psd1'
        '@{ DisablePrompt = $true }' |
            Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM

        try {
            $env:WINFILES_DISABLE_PROMPT = 'false'
            (Get-WinfilesSetting -Path $settingsPath).DisablePrompt | Should -BeFalse
        }
        finally {
            Remove-Item Env:\WINFILES_DISABLE_PROMPT -ErrorAction SilentlyContinue
        }
    }

    It 'rejects unknown settings and nonliteral Boolean overrides' {
        $settingsPath = Join-Path -Path $TestDrive -ChildPath 'invalid.psd1'
        '@{ UnknownSetting = $true }' |
            Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM

        { Get-WinfilesSetting -Path $settingsPath } | Should -Throw '*Unknown setting*'

        try {
            $env:WINFILES_DISABLE_PROMPT = 'yes'
            { Get-WinfilesSetting -Path (
                    Join-Path -Path $TestDrive -ChildPath 'missing.psd1'
                ) } | Should -Throw '*must be the Boolean value*'
        }
        finally {
            Remove-Item Env:\WINFILES_DISABLE_PROMPT -ErrorAction SilentlyContinue
        }
    }

    It 'writes only the supported settings atomically' {
        $repository = Join-Path -Path $TestDrive -ChildPath 'settings-repository'
        New-Item -ItemType Directory -Path (
            Join-Path -Path $repository -ChildPath 'config'
        ) -Force | Out-Null
        $settings = [ordered]@{
            DisableAliases     = $true
            DisablePrompt      = $false
            DisableModules     = $true
            DisableCompletions = $false
            DisablePredictions = $true
            DisableFzf         = $false
        }

        Set-WinfilesSetting -RepositoryRoot $repository -Settings $settings
        $written = Import-PowerShellDataFile -LiteralPath (
            Join-Path -Path $repository -ChildPath 'config\settings.psd1'
        )

        $written.DisableAliases | Should -BeTrue
        $written.DisablePrompt | Should -BeFalse
        $written.Keys.Count | Should -Be 6
    }
}

Describe 'Ownership state' {
    It 'records the first package and keeps package and module entries unique' {
        $env:WINFILES_STATE_PATH = Join-Path -Path $TestDrive `
            -ChildPath 'install-state.json'

        Add-WinfilesOwnedPackage -Id 'Example.Package'
        Add-WinfilesOwnedPackage -Id 'Example.Package'
        Add-WinfilesOwnedModule -Name 'ExampleModule' -Version '1.2.3'
        Add-WinfilesOwnedModule -Name 'ExampleModule' -Version '1.2.3'
        $state = Get-WinfilesState

        @($state.Packages).Count | Should -Be 1
        $state.Packages[0].Id | Should -BeExactly 'Example.Package'
        @($state.Modules).Count | Should -Be 1
        $state.Modules[0].Name | Should -BeExactly 'ExampleModule'
        $state.Modules[0].Version | Should -BeExactly '1.2.3'
    }
}

Describe 'PowerShell module installation recovery' {
    It 'removes an incomplete module version directory' {
        $moduleRoot = Join-Path -Path $TestDrive -ChildPath 'Modules'
        $versionPath = Get-WinfilesPowerShellModuleVersionPath `
            -Name 'IncompleteTestModule' -Version '1.2.3' -ModuleRoot $moduleRoot
        New-Item -ItemType Directory -Path $versionPath -Force | Out-Null
        'partial package content' |
            Set-Content -LiteralPath (
                Join-Path -Path $versionPath -ChildPath 'IncompleteTestModule.dll'
            ) -Encoding utf8NoBOM

        Remove-WinfilesStalePowerShellModuleVersion `
            -Name 'IncompleteTestModule' -Version '1.2.3' -ModuleRoot $moduleRoot

        Test-Path -LiteralPath $versionPath | Should -BeFalse
    }

    It 'cleans a previous module quarantine when it is no longer locked' {
        $moduleRoot = Join-Path -Path $TestDrive -ChildPath 'QuarantinedModules'
        $quarantinePath = Join-Path -Path $moduleRoot `
            -ChildPath '.winfiles-stale\IncompleteTestModule-1.2.3-old'
        New-Item -ItemType Directory -Path $quarantinePath -Force | Out-Null
        'stale package content' |
            Set-Content -LiteralPath (
                Join-Path -Path $quarantinePath -ChildPath 'IncompleteTestModule.dll'
            ) -Encoding utf8NoBOM

        Remove-WinfilesStalePowerShellModuleVersion `
            -Name 'IncompleteTestModule' -Version '1.2.3' -ModuleRoot $moduleRoot

        Test-Path -LiteralPath $quarantinePath | Should -BeFalse
    }
}

Describe 'Managed profile loader' {
    It 'preserves content, creates a backup, and is idempotent' {
        $profilePath = Join-Path -Path $TestDrive -ChildPath 'profile.ps1'
        "Write-Output 'keep me'`n" |
            Set-Content -LiteralPath $profilePath -Encoding utf8NoBOM -NoNewline

        Set-WinfilesProfileLoader -ProfilePath $profilePath `
            -RepositoryRoot $script:RepositoryRoot
        $firstContent = Get-Content -LiteralPath $profilePath -Raw
        $firstBackups = @(Get-ChildItem -Path "$profilePath.winfiles.bak.*")

        Set-WinfilesProfileLoader -ProfilePath $profilePath `
            -RepositoryRoot $script:RepositoryRoot
        $secondContent = Get-Content -LiteralPath $profilePath -Raw
        $secondBackups = @(Get-ChildItem -Path "$profilePath.winfiles.bak.*")

        $firstContent | Should -Match "Write-Output 'keep me'"
        ([regex]::Matches($firstContent, '# >>> winfiles >>>')).Count | Should -Be 1
        $firstBackups.Count | Should -Be 1
        $secondContent | Should -BeExactly $firstContent
        $secondBackups.Count | Should -Be 1
    }

    It 'migrates only recognized initializers' {
        $content = @'
fnm env --use-on-cd | Out-String | Invoke-Expression
oh-my-posh init pwsh --config "C:\theme.json" | Invoke-Expression
if ( Test-Path '~/.inshellisense/init/powershell/init.ps1' -PathType Leaf ) { . ~/.inshellisense/init/powershell/init.ps1 }
. "C:\Users\Someone\AppData\Local\sync-ssh\sync.ps1"
'@

        $migrated = Remove-WinfilesKnownInitializer -Content $content

        $migrated | Should -Not -Match 'Invoke-Expression'
        $migrated | Should -Match 'sync-ssh'
    }

    It 'removes only the managed loader block' {
        $profilePath = Join-Path -Path $TestDrive -ChildPath 'removal-profile.ps1'
        "Write-Output 'keep me'`n" |
            Set-Content -LiteralPath $profilePath -Encoding utf8NoBOM -NoNewline
        Set-WinfilesProfileLoader -ProfilePath $profilePath `
            -RepositoryRoot $script:RepositoryRoot

        Remove-WinfilesProfileLoader -ProfilePath $profilePath
        $content = Get-Content -LiteralPath $profilePath -Raw

        $content | Should -Match "Write-Output 'keep me'"
        $content | Should -Not -Match '# >>> winfiles >>>'
    }
}

Describe 'Profile smoke test' {
    It 'loads with every optional component disabled' {
        try {
            foreach ($name in $script:OverrideNames) {
                [Environment]::SetEnvironmentVariable($name, 'true')
            }
            $env:WINFILES_LOCAL_PROFILE = Join-Path -Path $TestDrive -ChildPath 'missing-local.ps1'

            . (Join-Path -Path $script:RepositoryRoot -ChildPath 'profile.ps1')

            $env:WINFILES_DIR | Should -Be $script:RepositoryRoot
            $WinfilesSettings.DisablePrompt | Should -BeTrue
        }
        finally {
            foreach ($name in $script:OverrideNames) {
                Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
            }
            Remove-Item Env:\WINFILES_LOCAL_PROFILE -ErrorAction SilentlyContinue
        }
    }
}
