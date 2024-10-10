# Add all changes
git add .

# Check for environment variable for Ollama API URL
$OllamaAPIURL = if ($env:OLLAMA_API_URL) { $env:OLLAMA_API_URL } else { "http://localhost:11434" }

# Function to ensure Ollama is running and the model is available
function Ensure-OllamaRunning {
    if (!(Get-NetTCPConnection -LocalPort 11434 -ErrorAction SilentlyContinue)) {
        Write-Host "Ollama is not running. Starting Ollama service..."
        Start-Process ollama -ArgumentList "serve" -NoNewWindow
        Start-Sleep -Seconds 5  # Wait for Ollama to start
    } else {
        Write-Host "Ollama service is already running."
    }

    $modelName = "llama3.1"
    if (!(ollama list | Select-String $modelName)) {
        Write-Host "Pulling the latest $modelName model..."
        ollama pull $modelName
    }
}

# Ensure Ollama is running and the model is available
Ensure-OllamaRunning

# Get git diff to summarize
$changes = git diff --cached

# Check if there are any changes staged
if ([string]::IsNullOrEmpty($changes)) {
    Write-Host "No changes to commit."
    exit 0
}

# Write diff to temporary file
$tempFile = [System.IO.Path]::GetTempFileName()
$changes | Out-File -FilePath $tempFile -Encoding utf8

# Escape backslashes in the file path
$escapedTempFile = $tempFile -replace '\\', '\\'

# Call Ollama API to summarize changes
$summary = python -c @"
import os
import requests
import json
import sys

ollama_api_url = '$OllamaAPIURL'
temp_file = r'$escapedTempFile'

with open(temp_file, 'r', encoding='utf-8') as f:
    diff = f.read()

print("Diff content:", diff[:100] + "...")  # Debug print (first 100 characters)

payload = {
    "model": "llama3.1",
    "prompt": "Summarize the following git diff in a concise commit message:\n\n" + diff,
    "stream": False
}

try:
    response = requests.post(f"{ollama_api_url}/api/generate", json=payload)
    response_json = response.json()
    summary = response_json['response'].strip()
    print(summary)
except Exception as e:
    print(f"Error: {str(e)}", file=sys.stderr)
    sys.exit(1)
finally:
    os.remove(temp_file)
"@

# Remove temporary file
Remove-Item -Path $tempFile -ErrorAction SilentlyContinue

# If no summary is generated
if (-not $summary) {
    Write-Host "Failed to generate commit summary."
    exit 1
}

# Commit changes
git commit -m "$summary"

# Push to origin main
git push origin main

# Print success message
Write-Host "Changes committed and pushed with summary: $summary"
