# Build challenges_public/ from challenges/.
#
# Two publication modes per challenge:
#   full  - Mirror challenges/<name>/ to challenges_public/<name>/,
#           filtering out build artifacts. Used when the source code IS the
#           intended starter (e.g. fp8-adder, speed-loopback).
#   stub  - Copy ONLY challenges/<name>/.public/ to challenges_public/<name>/.
#           Never reads any other file from the secret folder.
#           Used when the secret folder contains the full solution.
#
# Optional: challenges/.public/CHALLENGES.md is copied to
# challenges_public/CHALLENGES.md if present (the public challenge brief).
#
# Usage:
#   .\scripts\build-challenges-public.ps1            # build with summary
#   .\scripts\build-challenges-public.ps1 -DryRun    # report only

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Strict   # abort on any stub-mode challenge missing .public/
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

# ---------------------------------------------------------------------------
# Roster -- edit this when the event challenge list changes.
# ---------------------------------------------------------------------------
$Roster = @(
    @{ Name = "fp8-adder";       Mode = "full" }
    @{ Name = "speed-loopback";  Mode = "full" }
    @{ Name = "accel-cube";      Mode = "stub" }
    @{ Name = "fft-freq";        Mode = "stub" }
    @{ Name = "fft-freq-ip";     Mode = "stub" }
    @{ Name = "fpga-voltmeter";  Mode = "stub" }
    @{ Name = "pc-fluppy";       Mode = "stub" }
    @{ Name = "press-right";     Mode = "stub" }
    @{ Name = "volt-meter";      Mode = "stub" }
)

# Filesystem patterns excluded from "full" mode mirroring.
$ExcludeDirs = @(
    ".pio", "db", "incremental_db", "output_files", "simulation",
    "__pycache__", ".public", "work"
)
$ExcludeExts = @(
    ".pyc", ".qws", ".sof", ".pof", ".bak", ".rpt", ".jdi",
    ".sld", ".smsg", ".done", ".db_info", ".summary", ".pin"
)
$ExcludeFiles = @(
    "secrets.h", "transcript"
)
$ExcludeFileWildcards = @(
    "compile_*.txt", "compile_*.log"
)

function Test-PathExcluded {
    param([string]$RelPath)
    $parts = $RelPath -split '[\\/]'
    foreach ($p in $parts) {
        if ($ExcludeDirs -contains $p) { return $true }
    }
    $leaf = [System.IO.Path]::GetFileName($RelPath)
    if ($ExcludeFiles -contains $leaf) { return $true }
    foreach ($pat in $ExcludeFileWildcards) {
        if ($leaf -like $pat) { return $true }
    }
    $ext = [System.IO.Path]::GetExtension($RelPath).ToLower()
    if ($ExcludeExts -contains $ext) { return $true }
    return $false
}

function Copy-FilteredTree {
    param([string]$From, [string]$To)
    $count = 0
    $skipped = 0
    Get-ChildItem -Path $From -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($From.Length).TrimStart('\','/')
        if (Test-PathExcluded $rel) { $skipped++; return }
        $dest = Join-Path $To $rel
        $destDir = Split-Path $dest
        if (-not (Test-Path $destDir)) {
            if (-not $DryRun) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        }
        if (-not $DryRun) { Copy-Item -Path $_.FullName -Destination $dest -Force }
        $count++
    }
    return @{ Copied = $count; Skipped = $skipped }
}

function Test-AntiLeak {
    # Final guard: for every file under challenges_public/<name> belonging to
    # a "stub" challenge, the file's bytes must NOT equal the bytes of any
    # same-relative-path file under challenges/<name>/ outside of .public/.
    # That detects copy-paste accidents in the stub.
    param([string]$Name, [string]$PublicRoot, [string]$SecretRoot)

    $leaks = @()
    Get-ChildItem -Path $PublicRoot -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($PublicRoot.Length).TrimStart('\','/')
        $secretTwin = Join-Path $SecretRoot $rel
        if ((Test-Path $secretTwin) -and -not ($secretTwin -like "*\.public\*")) {
            $publicHash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
            $secretHash = (Get-FileHash $secretTwin -Algorithm SHA256).Hash
            if ($publicHash -eq $secretHash) {
                $leaks += $rel
            }
        }
    }
    return $leaks
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$PublicRootAbs = Join-Path $RepoRoot "challenges_public"
$ChallengesAbs = Join-Path $RepoRoot "challenges"

if (-not (Test-Path $ChallengesAbs)) {
    throw "challenges/ folder not found. Nothing to build."
}

Write-Host "Building challenges_public/ from challenges/..." -ForegroundColor Cyan
if ($DryRun) { Write-Host "(DRY RUN -- no files will be written)" -ForegroundColor Yellow }

# Wipe + recreate the staging tree.
if (-not $DryRun) {
    if (Test-Path $PublicRootAbs) { Remove-Item $PublicRootAbs -Recurse -Force }
    New-Item -ItemType Directory -Path $PublicRootAbs | Out-Null
}

$summary = @()
$hardErrors = @()

foreach ($entry in $Roster) {
    $name = $entry.Name
    $mode = $entry.Mode
    $secretDir = Join-Path $ChallengesAbs $name
    $publicDir = Join-Path $PublicRootAbs $name
    $publicOverride = Join-Path $secretDir ".public"

    if (-not (Test-Path $secretDir)) {
        Write-Host ("  [{0,-16}] MISSING in challenges/" -f $name) -ForegroundColor Red
        $hardErrors += "$name : missing source folder"
        continue
    }

    switch ($mode) {
        "full" {
            if (Test-Path $publicOverride) {
                Write-Host ("  [{0,-16}] WARNING: .public/ exists but mode=full. Ignoring .public/." -f $name) -ForegroundColor Yellow
            }
            $r = Copy-FilteredTree -From $secretDir -To $publicDir
            $summary += [pscustomobject]@{
                Challenge=$name; Mode=$mode; Copied=$r.Copied; Skipped=$r.Skipped; Status="ok"
            }
            Write-Host ("  [{0,-16}] full  -> {1,4} files copied, {2,4} filtered" -f $name, $r.Copied, $r.Skipped) -ForegroundColor Green
        }
        "stub" {
            if (-not (Test-Path $publicOverride)) {
                $msg = "stub mode but $secretDir\.public\ does not exist"
                Write-Host ("  [{0,-16}] SKIP  -- {1}" -f $name, $msg) -ForegroundColor DarkYellow
                $summary += [pscustomobject]@{
                    Challenge=$name; Mode=$mode; Copied=0; Skipped=0; Status="missing-.public"
                }
                if ($Strict) { $hardErrors += "$name : $msg" }
                continue
            }
            $r = Copy-FilteredTree -From $publicOverride -To $publicDir
            # Anti-leak guard
            if (-not $DryRun) {
                $leaks = Test-AntiLeak -Name $name -PublicRoot $publicDir -SecretRoot $secretDir
                if ($leaks.Count -gt 0) {
                    foreach ($l in $leaks) {
                        $hardErrors += "$name : leak -- $l is byte-identical to the secret source"
                    }
                }
            }
            $summary += [pscustomobject]@{
                Challenge=$name; Mode=$mode; Copied=$r.Copied; Skipped=$r.Skipped; Status="ok"
            }
            Write-Host ("  [{0,-16}] stub  -> {1,4} files copied from .public/" -f $name, $r.Copied) -ForegroundColor Green
        }
        default {
            $hardErrors += "$name : unknown mode '$mode'"
        }
    }
}

# Top-level public brief.
# Single source of truth: challenges/challenges.md.
# We strip the "SECRET / DO NOT FORWARD" banner and the editor template block
# on the fly, then render an HTML version next to it.
$masterBrief = Join-Path $ChallengesAbs "challenges.md"
if (Test-Path $masterBrief) {
    $mdOut = Join-Path $PublicRootAbs "CHALLENGES.md"
    $htmlOut = Join-Path $PublicRootAbs "CHALLENGES.html"

    if (-not $DryRun) {
        $raw = Get-Content $masterBrief -Raw -Encoding UTF8

        # Strip the SECRET blockquote block (contiguous lines starting with "> ").
        $sanitized = [regex]::Replace(
            $raw,
            '(?ms)^> # SECRET - DO NOT FORWARD.*?(?=\r?\n\r?\n---)',
            ''
        )
        # Strip the HTML template comment block.
        $sanitized = [regex]::Replace(
            $sanitized,
            '(?s)<!-- Template for each challenge:.*?-->',
            ''
        )
        # Collapse 3+ blank lines into 2.
        $sanitized = [regex]::Replace($sanitized, "(\r?\n){3,}", "`r`n`r`n")
        # Collapse consecutive --- horizontal rules into one.
        $sanitized = [regex]::Replace($sanitized, "(?m)^---\s*\r?\n\s*\r?\n---\s*$", "---")
        $sanitized = $sanitized.TrimStart()

        # Write UTF-8 without BOM.
        [System.IO.File]::WriteAllText($mdOut, $sanitized, [System.Text.UTF8Encoding]::new($false))

        # Render markdown -> HTML using the project Python env.
        $python = Join-Path $RepoRoot "env\Scripts\python.exe"
        if (Test-Path $python) {
            $renderScript = Join-Path $PSScriptRoot "_render_md_to_html.py"
            & $python $renderScript $mdOut $htmlOut
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  [CHALLENGES.html ] render failed (exit $LASTEXITCODE)" -ForegroundColor Yellow
            } else {
                Write-Host "  [CHALLENGES.html ] rendered from CHALLENGES.md" -ForegroundColor Green
            }
        } else {
            Write-Host "  [CHALLENGES.html ] skipped (no env\Scripts\python.exe)" -ForegroundColor DarkYellow
        }
    }
    Write-Host "  [CHALLENGES.md   ] generated from challenges/challenges.md (sanitized)" -ForegroundColor Green
} else {
    Write-Host "  [CHALLENGES.md   ] not found (challenges/challenges.md). Skipping." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
$summary | Format-Table -AutoSize | Out-Host

if ($hardErrors.Count -gt 0) {
    Write-Host "ERRORS:" -ForegroundColor Red
    $hardErrors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    if (-not $DryRun) {
        # On real builds, blow away the partial staging tree to avoid shipping a leak.
        if (Test-Path $PublicRootAbs) { Remove-Item $PublicRootAbs -Recurse -Force }
        Write-Host "challenges_public/ wiped due to errors." -ForegroundColor Red
    }
    throw "Build failed with $($hardErrors.Count) error(s)."
}

Write-Host "Build OK." -ForegroundColor Green
if ($DryRun) {
    Write-Host "(Dry run; no files written.)" -ForegroundColor Yellow
} else {
    Write-Host "Output: $PublicRootAbs" -ForegroundColor Green
    Write-Host "Next:   .\scripts\publish-challenges.ps1 -DryRun" -ForegroundColor Green
}
