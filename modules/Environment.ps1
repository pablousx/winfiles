function Add-WinfilesPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    $separator = [System.IO.Path]::PathSeparator
    $pathEntries = @($env:PATH -split [regex]::Escape([string]$separator))
    $comparison = if ($IsWindows) {
        [StringComparison]::OrdinalIgnoreCase
    }
    else {
        [StringComparison]::Ordinal
    }

    foreach ($entry in $pathEntries) {
        if ([string]::Equals($entry.TrimEnd('\', '/'), $Path.TrimEnd('\', '/'), $comparison)) {
            return
        }
    }

    $env:PATH = "$Path$separator$env:PATH"
}

$userProfile = [Environment]::GetFolderPath('UserProfile')
$localApplicationData = [Environment]::GetFolderPath('LocalApplicationData')

Add-WinfilesPath -Path (Join-Path -Path $userProfile -ChildPath '.local\bin')
Add-WinfilesPath -Path (Join-Path -Path $localApplicationData -ChildPath 'Microsoft\WinGet\Links')

if (-not $env:PNPM_HOME) {
    $env:PNPM_HOME = Join-Path -Path $localApplicationData -ChildPath 'pnpm'
}
Add-WinfilesPath -Path $env:PNPM_HOME

if (-not $env:EDITOR) {
    if (Get-Command -Name code -CommandType Application -ErrorAction SilentlyContinue) {
        $env:EDITOR = 'code'
    }
    else {
        $env:EDITOR = 'notepad'
    }
}

if (-not $env:VISUAL) {
    $env:VISUAL = $env:EDITOR
}

Remove-Variable -Name localApplicationData, userProfile -ErrorAction SilentlyContinue
