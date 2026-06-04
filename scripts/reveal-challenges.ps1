<# 
    REVEAL CHALLENGES — Run this tomorrow morning to go live.
    
    What it does:
    1. Copies challenges_public/CHALLENGES.html -> eventday-challenges.html
    2. Removes the gitignore line blocking it
    3. Stages everything (index.html, .gitignore, eventday-challenges.html)
    4. Commits locally
    5. STOPS and waits for your explicit "git push"
#>

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "`n=== CrashTech Challenge Reveal ===" -ForegroundColor Cyan

# 1. Copy challenge content
$src = "challenges_public\CHALLENGES.html"
$dst = "eventday-challenges.html"

if (-not (Test-Path $src)) {
    Write-Host "ERROR: $src not found. Run build-challenges-public.ps1 first." -ForegroundColor Red
    exit 1
}

Copy-Item $src $dst -Force
Write-Host "[OK] Copied $src -> $dst" -ForegroundColor Green

# 2. Remove the gitignore line
$gitignore = Get-Content .gitignore -Raw
$gitignore = $gitignore -replace "(?m)^# Event Day challenges file -- remove this line to reveal on competition day\r?\neventday-challenges\.html\r?\n", ""
Set-Content .gitignore $gitignore -NoNewline
Write-Host "[OK] Removed eventday-challenges.html from .gitignore" -ForegroundColor Green

# 3. Stage
git add eventday-challenges.html .gitignore index.html
Write-Host "[OK] Staged files" -ForegroundColor Green

# 4. Commit locally
git commit -m "Reveal competition challenges for Event Day"
Write-Host "[OK] Committed locally" -ForegroundColor Green

# 5. STOP
Write-Host "`n>>> Commit ready. Run 'git push' when you want participants to see it. <<<" -ForegroundColor Yellow
Write-Host ""
