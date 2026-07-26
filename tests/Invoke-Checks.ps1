#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$RequireTools
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path -Path $PSScriptRoot -ChildPath '..')
)

try {
    $excludedRoots = @(
        (Join-Path -Path $repositoryRoot -ChildPath '.git')
        (Join-Path -Path $repositoryRoot -ChildPath '.cache')
        (Join-Path -Path $repositoryRoot -ChildPath 'TestResults')
    )
    $sourceFiles = Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File |
        Where-Object {
            $candidate = $_
            $isExcluded = $excludedRoots |
                Where-Object {
                    $candidate.FullName.StartsWith(
                        $_,
                        [StringComparison]::OrdinalIgnoreCase
                    )
                }
            $candidate.Extension -in @('.ps1', '.psd1', '.psm1') -and -not $isExcluded
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
    if ($parseFailures.Count -gt 0) {
        throw "PowerShell parsing failed:`n$($parseFailures -join [Environment]::NewLine)"
    }
    Write-Information 'ok - PowerShell parsing' -InformationAction Continue

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-SmokeTests.ps1')

    $scriptAnalyzerModule = Get-Module -ListAvailable -Name PSScriptAnalyzer |
        Where-Object Version -GE ([version]'1.25.0') |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($scriptAnalyzerModule) {
        Import-Module -Name $scriptAnalyzerModule.Path -ErrorAction Stop
        $settingsPath = Join-Path -Path $repositoryRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
        $analysis = @(
            foreach ($sourceFile in $sourceFiles) {
                Invoke-ScriptAnalyzer -Path $sourceFile.FullName -Settings $settingsPath
            }
        )
        if ($analysis.Count -gt 0) {
            $formatted = $analysis |
                Select-Object RuleName, Severity, ScriptName, Line, Message |
                Format-Table -AutoSize |
                Out-String
            throw "PSScriptAnalyzer found issues:`n$formatted"
        }
        Write-Information 'ok - PSScriptAnalyzer' -InformationAction Continue
    }
    elseif ($RequireTools) {
        throw 'PSScriptAnalyzer is required but is not installed.'
    }
    else {
        Write-Warning 'skip - PSScriptAnalyzer is not installed'
    }

    $pesterModule = Get-Module -ListAvailable -Name Pester |
        Where-Object Version -GE ([version]'5.0.0') |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($pesterModule) {
        Import-Module -Name $pesterModule.Path -ErrorAction Stop
        $configuration = New-PesterConfiguration
        $configuration.Run.Path = Join-Path -Path $PSScriptRoot -ChildPath 'Winfiles.Tests.ps1'
        $configuration.Run.PassThru = $true
        $configuration.Output.Verbosity = 'Detailed'
        $result = Invoke-Pester -Configuration $configuration
        if ($result.FailedCount -gt 0) {
            throw "$($result.FailedCount) Pester test(s) failed."
        }
    }
    elseif ($RequireTools) {
        throw 'Pester is required but is not installed.'
    }
    else {
        Write-Warning 'skip - Pester is not installed'
    }

    $gitCommand = Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($gitCommand) {
        & $gitCommand.Source -C $repositoryRoot diff --check
        if ($LASTEXITCODE -ne 0) {
            throw 'git diff --check failed.'
        }
        Write-Information 'ok - whitespace validation' -InformationAction Continue
    }
    else {
        Write-Warning 'skip - Windows Git is not installed'
    }
    Write-Information 'All checks passed.' -InformationAction Continue
}
catch {
    Write-Error "Validation failed: $($_.Exception.Message)"
    exit 1
}
