# Auto-Sync to GIT.BASE (OPS Remote)
# Watches 0ut.3ox folder and commits/pushes new files
# Updated: ⧗-25.61

param(
    [switch]$Watch,
    [int]$Interval = 10
)

$RepoPath = $PSScriptRoot
$ManifestFile = Join-Path $RepoPath "FILE.MANIFEST.txt"

function Get-ReadyFiles {
    if (-not (Test-Path $ManifestFile)) {
        return @()
    }
    
    $readyFiles = @()
    Get-Content $ManifestFile | ForEach-Object {
        if ($_ -match '\|\s*READY\s*\|') {
            # Extract filename from manifest line
            $parts = $_ -split '\|'
            if ($parts.Length -ge 3) {
                $filepath = $parts[2].Trim()
                $readyFiles += $filepath
            }
        }
    }
    
    return $readyFiles
}

function Update-ManifestStatus {
    param([string]$Filepath, [string]$NewStatus)
    
    if (-not (Test-Path $ManifestFile)) {
        return
    }
    
    $content = Get-Content $ManifestFile
    $updated = $content | ForEach-Object {
        if ($_ -match [regex]::Escape($Filepath) -and $_ -match '\|\s*READY\s*\|') {
            $_ -replace '\|\s*READY\s*\|', "| $NewStatus |"
        } else {
            $_
        }
    }
    
    Set-Content -Path $ManifestFile -Value $updated
}

function Sync-ToOps {
    Write-Host "`n🔄 Checking for new files to sync..." -ForegroundColor Cyan
    
    # Change to repo directory
    Push-Location $RepoPath
    
    try {
        # Check for ready files
        $readyFiles = Get-ReadyFiles
        
        if ($readyFiles.Count -eq 0) {
            Write-Host "✓ No files ready for sync" -ForegroundColor Gray
            return
        }
        
        Write-Host "📋 Found $($readyFiles.Count) file(s) ready to sync:" -ForegroundColor Yellow
        $readyFiles | ForEach-Object { Write-Host "   - $_" -ForegroundColor White }
        
        # Git add all new/changed files
        git add .
        
        # Check if there are changes to commit
        $status = git status --porcelain
        if (-not $status) {
            Write-Host "✓ No changes to commit" -ForegroundColor Gray
            return
        }
        
        # Create commit message with file list
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $fileList = $readyFiles -join ", "
        $commitMsg = "Sync from LAUNCHPAD [$timestamp]`n`nFiles: $fileList"
        
        # Commit
        git commit -m $commitMsg
        
        # Push to ops remote
        Write-Host "🚀 Pushing to GIT.BASE (ops remote)..." -ForegroundColor Cyan
        git push ops master
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Successfully synced to GIT.BASE!" -ForegroundColor Green
            
            # Update manifest status
            foreach ($file in $readyFiles) {
                Update-ManifestStatus -Filepath $file -NewStatus "SYNCED"
            }
            
            Write-Host "📝 Updated manifest status → SYNCED" -ForegroundColor Green
        } else {
            Write-Host "❌ Push failed!" -ForegroundColor Red
        }
        
    } finally {
        Pop-Location
    }
}

# Main execution
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  GIT.BASE Auto-Sync (LAUNCHPAD → OPS Remote)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Repo: $RepoPath" -ForegroundColor Yellow
Write-Host "Remote: ops (GIT.BASE)" -ForegroundColor Yellow

if ($Watch) {
    Write-Host "Mode: WATCH (checking every $Interval seconds)" -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Gray
    
    try {
        while ($true) {
            Sync-ToOps
            Start-Sleep -Seconds $Interval
        }
    } catch {
        Write-Host "`n✋ Watch mode stopped" -ForegroundColor Yellow
    }
} else {
    Write-Host "Mode: SINGLE RUN`n" -ForegroundColor Yellow
    Sync-ToOps
}

Write-Host "`n═══════════════════════════════════════════════════`n" -ForegroundColor Cyan
