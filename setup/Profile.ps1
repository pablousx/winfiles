$script:WinfilesProfileBeginMarker = '# >>> winfiles >>>'
$script:WinfilesProfileEndMarker = '# <<< winfiles <<<'

function Backup-WinfilesFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path
    )

    $timestamp = Get-Date -Format 'yyyyMMddHHmmssfff'
    $backupPath = "$Path.winfiles.bak.$timestamp"
    Copy-Item -LiteralPath $Path -Destination $backupPath
    return $backupPath
}

function Remove-WinfilesKnownInitializer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )

    $patterns = @(
        '(?m)^[ \t]*fnm[ \t]+env[ \t]+--use-on-cd[ \t]*\|[ \t]*Out-String[ \t]*\|[ \t]*Invoke-Expression[ \t]*\r?\n?'
        '(?m)^[ \t]*oh-my-posh[ \t]+init[ \t]+pwsh[ \t]+--config[ \t]+.+?\|[ \t]*Invoke-Expression[ \t]*\r?\n?'
        '(?m)^[ \t]*if[ \t]*\([ \t]*Test-Path[ \t]+[''"]~[/\\]\.inshellisense[/\\]init[/\\]powershell[/\\]init\.ps1[''"].*?\)[ \t]*\{[ \t]*\.[ \t]+~[/\\]\.inshellisense[/\\]init[/\\]powershell[/\\]init\.ps1[ \t]*\}[ \t]*\r?\n?'
        '(?ms)^[ \t]*#f45873b3-b655-43a6-b217-97c00aa0db58 PowerToys CommandNotFound module[ \t]*\r?\n.*?^[ \t]*#f45873b3-b655-43a6-b217-97c00aa0db58[ \t]*\r?\n?'
    )

    $result = $Content
    foreach ($pattern in $patterns) {
        $result = [regex]::Replace($result, $pattern, '')
    }

    return $result
}

function Get-WinfilesProfileWithoutLoader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )

    $hasBegin = $Content.Contains($script:WinfilesProfileBeginMarker)
    $hasEnd = $Content.Contains($script:WinfilesProfileEndMarker)
    if ($hasBegin -ne $hasEnd) {
        throw 'The PowerShell profile contains an incomplete winfiles loader block.'
    }
    if (-not $hasBegin) {
        return $Content
    }

    $pattern = '(?ms)^[ \t]*' +
        [regex]::Escape($script:WinfilesProfileBeginMarker) +
        '[ \t]*\r?\n.*?^[ \t]*' +
        [regex]::Escape($script:WinfilesProfileEndMarker) +
        '[ \t]*\r?\n?'

    return [regex]::Replace($Content, $pattern, '')
}

function Set-WinfilesTextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )

    $directory = Split-Path -Path $Path -Parent
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporaryPath = "$Path.$PID.tmp"
    try {
        Set-Content -LiteralPath $temporaryPath -Value $Content -Encoding utf8NoBOM -NoNewline
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Set-WinfilesProfileLoader {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProfilePath,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$RepositoryRoot,

        [Parameter()]
        [switch]$MigrateKnownInitializers
    )

    $currentContent = if (Test-Path -LiteralPath $ProfilePath -PathType Leaf) {
        Get-Content -LiteralPath $ProfilePath -Raw
    }
    else {
        ''
    }

    $baseContent = Get-WinfilesProfileWithoutLoader -Content $currentContent
    if ($MigrateKnownInitializers) {
        $baseContent = Remove-WinfilesKnownInitializer -Content $baseContent
    }

    $escapedRoot = $RepositoryRoot.Replace("'", "''")
    $newLine = [Environment]::NewLine
    $loaderBlock = @(
        $script:WinfilesProfileBeginMarker
        "`$env:WINFILES_DIR = '$escapedRoot'"
        '$_winfilesProfile = Join-Path -Path $env:WINFILES_DIR -ChildPath ''profile.ps1'''
        'if (Test-Path -LiteralPath $_winfilesProfile -PathType Leaf) {'
        '    . $_winfilesProfile'
        '}'
        'Remove-Variable -Name _winfilesProfile -ErrorAction SilentlyContinue'
        $script:WinfilesProfileEndMarker
    ) -join $newLine

    $trimmedBase = $baseContent.TrimEnd("`r", "`n")
    $newContent = if ($trimmedBase) {
        "$trimmedBase$newLine$newLine$loaderBlock$newLine"
    }
    else {
        "$loaderBlock$newLine"
    }

    if ($newContent -ceq $currentContent) {
        Write-WinfilesLog "The winfiles loader is already current in '$ProfilePath'."
        return
    }

    if (-not $PSCmdlet.ShouldProcess($ProfilePath, 'Back up and update PowerShell profile loader')) {
        return
    }

    if (Test-Path -LiteralPath $ProfilePath -PathType Leaf) {
        $backupPath = Backup-WinfilesFile -Path $ProfilePath
        Write-WinfilesLog "Backed up '$ProfilePath' to '$backupPath'."
    }

    Set-WinfilesTextFile -Path $ProfilePath -Content $newContent
}

function Invoke-WinfilesKnownProfileMigration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProfilePath
    )

    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
        return
    }

    $currentContent = Get-Content -LiteralPath $ProfilePath -Raw
    $newContent = Remove-WinfilesKnownInitializer -Content $currentContent
    if ($newContent -ceq $currentContent) {
        return
    }

    if (-not $PSCmdlet.ShouldProcess(
            $ProfilePath,
            'Back up profile and remove known initializers now managed by winfiles'
        )) {
        return
    }

    $backupPath = Backup-WinfilesFile -Path $ProfilePath
    Write-WinfilesLog "Backed up '$ProfilePath' to '$backupPath'."
    Set-WinfilesTextFile -Path $ProfilePath -Content $newContent
}

function Remove-WinfilesProfileLoader {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProfilePath
    )

    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
        Write-WinfilesLog "PowerShell profile '$ProfilePath' does not exist."
        return
    }

    $currentContent = Get-Content -LiteralPath $ProfilePath -Raw
    $newContent = Get-WinfilesProfileWithoutLoader -Content $currentContent
    if ($newContent -ceq $currentContent) {
        Write-WinfilesLog "No winfiles loader was found in '$ProfilePath'."
        return
    }

    if (-not $PSCmdlet.ShouldProcess($ProfilePath, 'Back up profile and remove winfiles loader')) {
        return
    }

    $backupPath = Backup-WinfilesFile -Path $ProfilePath
    Write-WinfilesLog "Backed up '$ProfilePath' to '$backupPath'."
    Set-WinfilesTextFile -Path $ProfilePath -Content $newContent
}
