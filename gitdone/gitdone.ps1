# Add all changes
git add .

# Check for environment variable for Ollama API URL
$OllamaAPIURL = if ($env:OLLAMA_API_URL) { $env:OLLAMA_API_URL } else { "http://localhost:11434" }

# Function to ensure Ollama is running
function Ensure-OllamaRunning {
    if (!(Get-NetTCPConnection -LocalPort 11434 -ErrorAction SilentlyContinue)) {
        Write-Host "Ollama is not running. Starting Ollama service..."
        Start-Process ollama -ArgumentList "serve" -NoNewWindow
        Start-Sleep -Seconds 5  # Wait for Ollama to start
    } else {
        Write-Host "Ollama service is already running."
    }
}

# Ensure Ollama is running
Ensure-OllamaRunning

# Get git diff to summarize
$changes = git diff --cached --stat

# Check if there are any changes staged
if ([string]::IsNullOrEmpty($changes)) {
    Write-Host "No changes to commit."
    exit 0
}

Write-Host "Generating commit message..."

# Create a temporary Python script file
$pythonScriptPath = [System.IO.Path]::GetTempFileName() + ".py"
$pythonScript = @"
import sys
import requests
import json

changes = sys.stdin.read()
prompt = f"Summarize the following git changes in a concise commit message (max 50 characters):\n\n{changes}"

payload = {
    "model": "tinyllama",
    "prompt": prompt,
    "stream": False
}

try:
    response = requests.post("$OllamaAPIURL/api/generate", json=payload, timeout=30)
    response.raise_for_status()
    summary = response.json()['response'].strip()
    print(summary)
except Exception as e:
    print(f"Error: {str(e)}")
    sys.exit(1)
"@

# Write the Python script to the temporary file
$pythonScript | Out-File -FilePath $pythonScriptPath -Encoding utf8

# Execute the Python script
$summary = $changes | python $pythonScriptPath

# Remove temporary file
Remove-Item -Path $pythonScriptPath -ErrorAction SilentlyContinue

if (-not $summary) {
    Write-Host "Failed to generate commit summary." -ForegroundColor Red
    exit 1
}

Write-Host "Committing changes..."
git commit -m $summary

Write-Host "Pushing to origin main..."
git push origin main

Write-Host "Changes committed and pushed with summary: $summary" -ForegroundColor Green
