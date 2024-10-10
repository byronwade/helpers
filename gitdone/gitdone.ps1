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

# Create a temporary Python script file
$pythonScriptPath = [System.IO.Path]::GetTempFileName() + ".py"
$pythonScript = @"
import sys
import json
import requests

print("Python script started")
print(f"Ollama API URL: {sys.argv[1]}")

diff = sys.stdin.read()
print(f"Received diff of length: {len(diff)}")

payload = {
    "model": "llama3.1",
    "prompt": f"Summarize the following git diff in a concise commit message:\n\n{diff}",
    "stream": False
}

try:
    response = requests.post(sys.argv[1] + "/api/generate", json=payload, timeout=30)
    response.raise_for_status()
    summary = response.json().get('response', '').strip()
    print(f"Generated summary: {summary}")
except requests.exceptions.Timeout:
    print("Request to Ollama API timed out")
    sys.exit(1)
except Exception as e:
    print(f"Error occurred: {str(e)}")
    sys.exit(1)

print(summary)
"@

# Write the Python script to the temporary file
$pythonScript | Out-File -FilePath $pythonScriptPath -Encoding utf8

# Execute the Python script and capture the output
$summary = Get-Content $tempFile | python -c "$pythonScript" $OllamaAPIURL 2>&1

# Remove temporary Python script file
Remove-Item -Path $pythonScriptPath -ErrorAction SilentlyContinue

if (-not $summary) {
    Write-Host "Failed to generate commit summary." -ForegroundColor Red
    exit 1
}

Write-Host "Generated commit summary: $summary" -ForegroundColor Green

# Remove temporary diff file
Remove-Item -Path $tempFile -ErrorAction SilentlyContinue

# Commit changes
git commit -m "$summary"

# Push to origin main
git push origin main

# Print success message
Write-Host "Changes committed and pushed with summary: $summary" -ForegroundColor Green
