# Get the current directory of the setup script
$CurrentDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Variables
$ScriptPath = Join-Path $CurrentDir "gitdone.ps1"
$OllamaAPIURL = "http://localhost:11434"

# Ensure the gitdone.ps1 script exists in the current directory
if (!(Test-Path $ScriptPath)) {
    Write-Host "Error: gitdone.ps1 not found in the current directory." -ForegroundColor Red
    exit 1
}

# Set execution policy
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Write-Host "Execution policy has been set to RemoteSigned for the current user." -ForegroundColor Cyan

# Handle PowerShell profile
$profilePath = $PROFILE.CurrentUserAllHosts
if (!(Test-Path -Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force
    Write-Host "Created new PowerShell profile at $profilePath" -ForegroundColor Cyan
}

# Remove old gitdone-related entries from PowerShell profile
$profileContent = Get-Content -Path $profilePath -ErrorAction SilentlyContinue
if ($profileContent) {
    $updatedContent = $profileContent | Where-Object { $_ -notmatch 'gitdone|check_gitdone_update' }
    Set-Content -Path $profilePath -Value $updatedContent -Force
    Write-Host "Removed old gitdone-related entries from PowerShell profile." -ForegroundColor Cyan
}

# Add new alias to PowerShell profile
$aliasContent = "function gitdone { & `"$ScriptPath`" @args }"
Add-Content -Path $profilePath -Value $aliasContent
Write-Host "Function 'gitdone' added to PowerShell profile." -ForegroundColor Cyan

# Ensure Ollama is installed and running
# (Add your Ollama setup code here)

if ($?) {
    Write-Host "`nSetup completed successfully." -ForegroundColor Green
    Write-Host "Restart your terminal to use the 'gitdone' command." -ForegroundColor Yellow
    
    Write-Host "`nAdditional Information:" -ForegroundColor Magenta
    Write-Host "- GitDone script location: $ScriptPath" -ForegroundColor White
    Write-Host "- Ollama API URL: $OllamaAPIURL" -ForegroundColor White
    Write-Host "- To use GitDone, type 'gitdone' in a new terminal session" -ForegroundColor White
} else {
    Write-Host "`nSetup encountered issues. Please check the output above." -ForegroundColor Red
}