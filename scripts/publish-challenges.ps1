# Publish challenges_public/ to participants.
#
# Source of truth: challenges_public/ (built by build-challenges-public.ps1).
# This script NEVER reads from challenges/. It cannot leak secret content.
#
# Modes:
#   IntoMainRepo  - copy challenges_public/* into ./<DestFolderName>/ and
#                   git add + commit on the current branch.
#   SeparateRepo  - copy challenges_public/* into -Target (git init optional).
#   Zip           - zip challenges_public/* into -Output.
#
# Default: -DryRun (report only).

[CmdletBinding(DefaultParameterSetName="Dry")]
param(
    [Parameter(ParameterSetName="Dry")]
    [switch]$DryRun,

    [Parameter(Mandatory, ParameterSetName="Run")]
    [ValidateSet("IntoMainRepo","SeparateRepo","Zip")]
    [string]$Mode,

    [Parameter(ParameterSetName="Run")]
    [string]$Target,

    [Parameter(ParameterSetName="Run")]
    [string]$Output,

    [Parameter(ParameterSetName="Run")]
    [string]$GithubUrl,

    [Parameter(ParameterSetName="Run")]
    [string]$DestFolderName = "challenges_release"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$PublicRootAbs = Join-Path $RepoRoot "challenges_public"
$SecretRootAbs = Join-Path $RepoRoot "challenges"

$SecretSubstringPatterns = @(
    "challenges_secret",
    "challenges/challenges.md",
    "/.pio/",
    "/db/",
    "/incremental_db/",
    "/output_files/",
    "/simulation/",
    "/organizer/",
    "secrets.h"
)

function Invoke-Guards {
    if (-not (Test-Path $PublicRootAbs)) {
        throw "challenges_public/ does not exist. Run scripts/build-challenges-public.ps1 first."
    }
    $files = Get-ChildItem -Path $PublicRootAbs -Recurse -File
    if ($files.Count -eq 0) {
        throw "challenges_public/ is empty. Run scripts/build-challenges-public.ps1 first."
    }

    Write-Host "Running publication guards..." -ForegroundColor Cyan

    # 1. Pattern check on every staged file path.
    $bad = @()
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($PublicRootAbs.Length).Replace('\','/')
        foreach ($p in $SecretSubstringPatterns) {
            if ($rel -like "*$p*") {
                $bad += [pscustomobject]@{ File=$rel; Reason="pattern $p" }
                break
            }
        }
    }
    if ($bad.Count -gt 0) {
        Write-Host "ABORT: secret-pattern matches inside challenges_public/" -ForegroundColor Red
        $bad | ForEach-Object { Write-Host "  $($_.File)  [$($_.Reason)]" -ForegroundColor Red }
        throw "Guard failed."
    }

    # 2. Byte-identity check for stub-mode challenges.
    # If a file under challenges_public/<name>/<rel> is byte-identical to
    # challenges/<name>/<rel> AND there is no challenges/<name>/.public/<rel>
    # alongside it, that is a leak from full-mode mirror logic. Allowed only
    # for known "full" mode challenges (we approximate by: a .public sibling
    # exists at all for this challenge = stub mode).
    if (Test-Path $SecretRootAbs) {
        $stubLeaks = @()
        $challengeFolders = Get-ChildItem -Path $PublicRootAbs -Directory
        foreach ($cf in $challengeFolders) {
            $name = $cf.Name
            $secretBase = Join-Path $SecretRootAbs $name
            $overrideBase = Join-Path $secretBase ".public"
            if (-not (Test-Path $overrideBase)) { continue }   # full mode, skip

            Get-ChildItem -Path $cf.FullName -Recurse -File | ForEach-Object {
                $rel = $_.FullName.Substring($cf.FullName.Length).TrimStart('\','/')
                $secretTwin = Join-Path $secretBase $rel
                if (-not (Test-Path $secretTwin)) { return }
                $a = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
                $b = (Get-FileHash $secretTwin -Algorithm SHA256).Hash
                if ($a -eq $b) { $stubLeaks += "$name/$rel" }
            }
        }
        if ($stubLeaks.Count -gt 0) {
            Write-Host "ABORT: stub file byte-identical to secret source:" -ForegroundColor Red
            $stubLeaks | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            throw "Guard failed."
        }
    }

    Write-Host ("  OK. {0} files ready to publish from challenges_public/." -f $files.Count) -ForegroundColor Green
    return $files
}

function Invoke-IntoMainRepo {
    param($Files, [string]$DestFolderName)

    if ($DestFolderName -eq "challenges") {
        throw "Refusing -DestFolderName='challenges' (would collide with the secret tree). Use e.g. -DestFolderName challenges_release."
    }

    $destAbs = Join-Path $RepoRoot $DestFolderName
    if (Test-Path $destAbs) { Remove-Item $destAbs -Recurse -Force }
    Copy-Item -Path $PublicRootAbs -Destination $destAbs -Recurse

    git add -- $DestFolderName | Out-Null

    $staged = git diff --cached --name-only
    $leaks = $staged | Where-Object {
        foreach ($p in $SecretSubstringPatterns) { if ($_ -like "*$p*") { return $true } }
        $false
    }
    if ($leaks) {
        Write-Host "ABORT: secret pattern in staged files." -ForegroundColor Red
        $leaks | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        git reset HEAD | Out-Null
        throw "Publication aborted. Nothing committed."
    }

    git commit -m "Publish challenges -- event start" | Out-Host
    Write-Host ""
    Write-Host "Committed to '$DestFolderName/' on main." -ForegroundColor Green
    Write-Host "Review: git show --stat HEAD" -ForegroundColor Green
    Write-Host "Push:   git push origin main" -ForegroundColor Green
    Write-Host "Tag:    git tag v2026-challenges-open ; git push origin v2026-challenges-open" -ForegroundColor Green
}

function Invoke-SeparateRepo {
    param($Files, [string]$Target, [string]$GithubUrl)

    if (-not $Target) { throw "-Target is required for SeparateRepo mode." }
    if (Test-Path $Target) { throw "$Target already exists. Pick a fresh path." }

    Copy-Item -Path $PublicRootAbs -Destination $Target -Recurse
    Push-Location $Target
    try {
        git init -b main | Out-Null
        if ($GithubUrl) { git remote add origin $GithubUrl }
        git add . | Out-Null
        git commit -m "Initial challenge release" | Out-Null
        Write-Host ""
        Write-Host "Separate repo prepared at: $Target" -ForegroundColor Green
        if ($GithubUrl) {
            Write-Host "Push: cd '$Target'; git push -u origin main" -ForegroundColor Green
        }
    } finally {
        Pop-Location
    }
}

function Invoke-Zip {
    param($Files, [string]$Output)

    if (-not $Output) { throw "-Output is required for Zip mode." }
    $outDir = Split-Path $Output
    if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    if (Test-Path $Output) { Remove-Item $Output }
    Compress-Archive -Path (Join-Path $PublicRootAbs "*") -DestinationPath $Output -Force
    $sizeMb = (Get-Item $Output).Length / 1MB
    Write-Host ""
    Write-Host ("Zip created: {0} ({1:N1} MB)" -f $Output, $sizeMb) -ForegroundColor Green
}

$files = Invoke-Guards
if ($PSCmdlet.ParameterSetName -eq "Dry") {
    Write-Host ""
    Write-Host "DRY RUN. Nothing was modified." -ForegroundColor Cyan
    Write-Host "Rerun with -Mode IntoMainRepo / SeparateRepo / Zip to publish." -ForegroundColor Cyan
    return
}

switch ($Mode) {
    "IntoMainRepo"  { Invoke-IntoMainRepo  -Files $files -DestFolderName $DestFolderName }
    "SeparateRepo"  { Invoke-SeparateRepo  -Files $files -Target $Target -GithubUrl $GithubUrl }
    "Zip"           { Invoke-Zip           -Files $files -Output $Output }
}
