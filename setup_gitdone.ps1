# Variables
$HelperDir = "$HOME\git_helpers"
$Scripts = @("gitdone.ps1")
$OpenAIKeyPlaceholder = "your-openai-api-key-here"

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

# Remove OpenAI SDK installation
# pip install openai --user

# Set OLLAMA_API_URL environment variable
$OllamaAPIURL = Read-Host -Prompt "Enter your Ollama API URL (default: http://localhost:11434)"
if ([string]::IsNullOrWhiteSpace($OllamaAPIURL)) {
    $OllamaAPIURL = "http://localhost:11434"
}

# Set environment variable for the current user
[Environment]::SetEnvironmentVariable("OLLAMA_API_URL", $OllamaAPIURL, "User")

# Add helper directory to PATH
$existingPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($existingPath -notlike "*$HelperDir*") {
    $newPath = "$existingPath;$HelperDir"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "Added $HelperDir to user PATH."
} else {
    Write-Host "$HelperDir is already in PATH."
}

Write-Host "Setup complete! Please restart your PowerShell or Command Prompt."
