param(
    [string]$ProjectRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RelativePathSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)

    if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFull += [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    $relativePath = [System.Uri]::UnescapeDataString($relativeUri.ToString())

    return $relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar
}

$patterns = @(
    'DirAccess\.open',
    'list_dir_begin',
    'get_next\(',
    'current_is_dir\(',
    'ResourceLoader\.list_directory',
    'DirAccess\.get_files_at',
    'FileAccess\.get_files_at'
)

$scriptFiles = Get-ChildItem -Path $ProjectRoot -Recurse -File -Filter *.gd |
    Where-Object {
        $_.FullName -notmatch '\\build\\' -and
        $_.FullName -notmatch '\\.godot\\'
    }

$hits = @()
foreach ($file in $scriptFiles) {
    $matchRows = Select-String -Path $file.FullName -Pattern $patterns
    foreach ($row in $matchRows) {
        # Allow explanatory comments in ServerGame where manifests intentionally replace scans.
        if ($file.Name -eq 'ServerGame.gd' -and $row.Line.TrimStart().StartsWith('#')) {
            continue
        }

        $relativePath = Get-RelativePathSafe -BasePath $ProjectRoot -TargetPath $file.FullName
        $hits += [PSCustomObject]@{
            Path = $relativePath
            Line = $row.LineNumber
            Text = $row.Line.Trim()
        }
    }
}

if ($hits.Count -gt 0) {
    Write-Host "ERROR: Runtime directory scanning patterns detected."
    Write-Host "Replace dynamic directory scans with explicit manifests for export-safe loading."
    Write-Host ""
    foreach ($hit in $hits | Sort-Object Path, Line) {
        Write-Host ("{0}:{1}: {2}" -f $hit.Path, $hit.Line, $hit.Text)
    }
    exit 1
}

Write-Host "OK: No runtime directory scanning patterns found in GDScript files."
exit 0
