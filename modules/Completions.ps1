function Get-WinfilesCompletionCachePath {
    [CmdletBinding()]
    param()

    $localApplicationData = [Environment]::GetFolderPath('LocalApplicationData')
    if (-not $localApplicationData) {
        $localApplicationData = Join-Path -Path (
            [Environment]::GetFolderPath('UserProfile')
        ) -ChildPath '.local\state'
    }

    return Join-Path -Path $localApplicationData -ChildPath 'winfiles\completions'
}

function Update-WinfilesCompletionCache {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $cachePath = Get-WinfilesCompletionCachePath
    $definitions = @(
        @{ Name = 'gh'; Command = 'gh'; Arguments = @('completion', '-s', 'powershell') }
        @{ Name = 'fnm'; Command = 'fnm'; Arguments = @('completions', '--shell', 'powershell') }
        @{ Name = 'deno'; Command = 'deno'; Arguments = @('completions', 'powershell') }
    )

    if ($PSCmdlet.ShouldProcess($cachePath, 'Create completion cache directory')) {
        New-Item -ItemType Directory -Path $cachePath -Force | Out-Null
    }

    foreach ($definition in $definitions) {
        $command = Get-Command -Name $definition.Command -CommandType Application -ErrorAction SilentlyContinue
        if (-not $command) {
            continue
        }

        $completionText = & $command.Source @($definition.Arguments) 2>$null | Out-String
        if ($LASTEXITCODE -ne 0 -or -not $completionText.Trim()) {
            Write-Warning "Unable to generate $($definition.Name) completion."
            continue
        }

        $destination = Join-Path -Path $cachePath -ChildPath "$($definition.Name).ps1"
        if ($PSCmdlet.ShouldProcess($destination, "Write $($definition.Name) completion")) {
            Set-Content -LiteralPath $destination -Value $completionText -Encoding utf8NoBOM
        }
    }
}

$completionCachePath = Get-WinfilesCompletionCachePath
if (Test-Path -LiteralPath $completionCachePath -PathType Container) {
    Get-ChildItem -LiteralPath $completionCachePath -Filter '*.ps1' -File |
        Sort-Object -Property Name |
        ForEach-Object {
            . $_.FullName
        }
}

$wingetCompletionRegistered = Get-Variable -Name WinfilesWingetCompletionRegistered `
    -Scope Global -ErrorAction SilentlyContinue
if ($IsWindows -and
    -not $wingetCompletionRegistered -and
    (Get-Command -Name winget -CommandType Application -ErrorAction SilentlyContinue)) {
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)

        $escapedWord = $wordToComplete.Replace('"', '""')
        $escapedCommandLine = $commandAst.ToString().Replace('"', '""')
        & winget complete --word="$escapedWord" --commandline "$escapedCommandLine" `
            --position $cursorPosition |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_,
                    $_,
                    'ParameterValue',
                    $_
                )
            }
    }
    Set-Variable -Name WinfilesWingetCompletionRegistered -Value $true -Scope Global
}

Remove-Variable -Name completionCachePath, wingetCompletionRegistered -ErrorAction SilentlyContinue
