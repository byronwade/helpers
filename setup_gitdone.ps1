# Variables
$HelperDir = "$HOME\git_helpers"
$Scripts = @("gitdone.ps1")
$OllamaAPIURL = "http://localhost:11434"

# Create helper directory
if (!(Test-Path -Path $HelperDir)) {
    New-Item -ItemType Directory -Path $HelperDir
}

# Copy helper scripts
foreach ($script in $Scripts) {
    Copy-Item -Path $script -Destination $HelperDir
}

# Install Python if not installed
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "Python not found. Installing Python..."
    # Download Python installer
    $pythonInstaller = "$env:TEMP\python-installer.exe"
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.5/python-3.11.5-amd64.exe" -OutFile $pythonInstaller
    Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
    Remove-Item $pythonInstaller
}

# Ensure Ollama is installed and running
function Ensure-Ollama {
    if (!(Get-Command ollama -ErrorAction SilentlyContinue)) {
        Write-Host "Ollama not found. Installing Ollama..."
        # Download and install Ollama (assuming Windows)
        $installerUrl = "https://github.com/jmorganca/ollama/releases/latest/download/ollama-windows-amd64.zip"
        $zipPath = "$env:TEMP\ollama.zip"
        Invoke-WebRequest -Uri $installerUrl -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath "$env:ProgramFiles\Ollama" -Force
        $env:Path += ";$env:ProgramFiles\Ollama"
        [Environment]::SetEnvironmentVariable("Path", $env:Path, "Machine")
    }

    $modelName = "llama3.1"
    if (!(ollama list | Select-String $modelName)) {
        Write-Host "Pulling the latest $modelName model..."
        ollama pull $modelName
    } else {
        Write-Host "$modelName model is already available."
    }

    # Check if Ollama is already running
    if (!(Get-NetTCPConnection -LocalPort 11434 -ErrorAction SilentlyContinue)) {
        Write-Host "Starting Ollama service..."
        Start-Process ollama -ArgumentList "serve" -NoNewWindow
    } else {
        Write-Host "Ollama service is already running."
    }
}

Ensure-Ollama

# Set OLLAMA_API_URL environment variable
[Environment]::SetEnvironmentVariable("OLLAMA_API_URL", $OllamaAPIURL, "User")
$env:OLLAMA_API_URL = $OllamaAPIURL

# Update gitdone.ps1 with the OLLAMA_API_URL
$gitdonePath = Join-Path $HelperDir "gitdone.ps1"
$gitdoneContent = Get-Content $gitdonePath -Raw
$gitdoneContent = $gitdoneContent -replace '(?<=\$env:OLLAMA_API_URL \|\| ").*?(?=")', $OllamaAPIURL
Set-Content $gitdonePath $gitdoneContent

# Add helper directory to PATH
$existingPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($existingPath -notlike "*$HelperDir*") {
    $newPath = "$existingPath;$HelperDir"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:Path = $newPath
    Write-Host "Added $HelperDir to user PATH."
} else {
    Write-Host "$HelperDir is already in PATH."
}

# Create alias for gitdone
Set-Alias -Name gitdone -Value "$HelperDir\gitdone.ps1" -Scope Global

# Add alias to PowerShell profile
$profilePath = $PROFILE.CurrentUserAllHosts
if (!(Test-Path -Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force
}
Add-Content -Path $profilePath -Value "Set-Alias -Name gitdone -Value `"$HelperDir\gitdone.ps1`""

# Set execution policy
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

Write-Host "Setup complete! The gitdone command is now available."
Write-Host "You may need to restart your PowerShell session for all changes to take effect."
