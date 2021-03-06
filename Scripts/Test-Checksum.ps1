#Requires -Version 5.0

<#
.SYNOPSIS
    Verifies the hash value for the files from a text file.

.DESCRIPTION
    This PowerShell script reads a text file generated by GNU coreutils and
    verifies the hash value for the listed files.

.PARAMETER Path
    Specifies the path to one or more checksum files.

.PARAMETER IgnoreMissing
    Indicates that the script does not fail or report status for missing files.

.PARAMETER Quiet
    Indicates that the script does not print OK for each successfully verified
    file.

.PARAMETER Status
    Indicates that the script does not output anything.

.PARAMETER Strict
    Indicates that the script throws an error for improperly formatted checksum
    lines.

.PARAMETER Warn
    Indicates that the script warns about improperly formatted checksum lines.
#>

################################################################################
# Parameters
################################################################################

[CmdletBinding()]

param (
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [ValidateScript({ Test-Path -Path $_ })]
    [Alias('FullName')]
    [String[]]
    $Path,

    [Parameter()]
    [Switch]
    $IgnoreMissing,

    [Parameter()]
    [Switch]
    $Quiet,

    [Parameter()]
    [Switch]
    $Status,

    [Parameter()]
    [Switch]
    $Strict,

    [Parameter()]
    [Switch]
    $Warn
)

################################################################################
# Execution
################################################################################

process {
    Get-Item -Path $Path | Where-Object { Test-Path -Path $_ -PathType Leaf } | ForEach-Object {
        $algorithm = ''
        $checksumFile = $_.FullName
        $checksumDirectory = $_.DirectoryName

        [System.IO.Directory]::SetCurrentDirectory($checksumDirectory)

        Write-Verbose "Checksum file: ${checksumFile}"

        Get-Content -LiteralPath $checksumFile -Encoding UTF8 | ForEach-Object `
            -Begin {
                $line = 0
                $hasError = $false
                $notFound = 0
                $notMatch = 0
                $notValid = 0
                $verified = 0
            } `
            -Process {
                $line = $line + 1

                $hash = ''
                $name = ''

                switch -regex ($_) {
                    '^(\w+)(?:\s\s|\s\*)(.+)$' { $hash, $name = $Matches[1], $Matches[2] }
                    '^(\w+) \((.+)\) = (\w+)$' { $hash, $name = $Matches[3], $Matches[2] }
                }

                if (-not $algorithm) {
                    switch ($hash.Length) {
                        32  { $algorithm = 'MD5' }
                        40  { $algorithm = 'SHA1' }
                        64  { $algorithm = 'SHA256' }
                        96  { $algorithm = 'SHA384' }
                        128 { $algorithm = 'SHA512' }
                        default { $algorithm = $false }
                    }
                    Write-Verbose "Algorithm: ${algorithm}"
                }

                if ($algorithm -and $hash -and $name) {
                    $fullName = [System.IO.Path]::GetFullPath($name)

                    if (Test-Path -LiteralPath $fullName -PathType Leaf) {
                        if ($hash -eq (Get-FileHash -LiteralPath $fullName -Algorithm $algorithm).Hash) {
                            $verified = $verified + 1
                            if (-not ($Quiet -or $Status)) { Write-Output "${name}: OK" }
                        } else {
                            $notMatch = $notMatch + 1
                            if (-not $Status) { Write-Output "${name}: FAILED" }
                        }
                    } elseif (-not $IgnoreMissing) {
                        $notFound = $notFound + 1
                        if (-not $Status) { Write-Output "${name}: FAILED open or read" }
                    }
                } else {
                    $hasError = $true
                    $notValid = $notValid + 1
                    if ($Warn) { Write-Warning "${checksumFile}: ${line}: improperly formatted ${algorithm} line" }
                }
            } `
            -End {
                if (-not $Status) {
                    switch ($notValid) {
                        { $_ -eq 1 } { Write-Warning '1 line is improperly formatted' }
                        { $_ -gt 1 } { Write-Warning "${notValid} lines are improperly formatted" }
                    }
                    switch ($notFound) {
                        { $_ -eq 1 } { Write-Warning '1 listed file could not be read' }
                        { $_ -gt 1 } { Write-Warning "${notFound} listed files could not be read" }
                    }
                    switch ($notMatch) {
                        { $_ -eq 1 } { Write-Warning '1 computed checksum did NOT match' }
                        { $_ -gt 1 } { Write-Warning "${notMatch} computed checksums did NOT match" }
                    }
                    switch ($verified) {
                        { $_ -eq 0 } { Write-Warning "${checksumFile}: no file was verified" }
                    }
                }
                if ($Strict -and $hasError) { Write-Error "${checksumFile}: improperly checksum file" }
            }
    }
}
