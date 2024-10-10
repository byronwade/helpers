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

Write-Host "Checking for changes..."
# Get git diff to summarize
$changes = git diff --cached

# Check if there are any changes staged
if ([string]::IsNullOrEmpty($changes)) {
    Write-Host "No changes to commit."
    exit 0
}

Write-Host "Changes detected. Preparing to summarize..."

# Write diff to temporary file
$tempFile = [System.IO.Path]::GetTempFileName()
$changes | Out-File -FilePath $tempFile -Encoding utf8

Write-Host "Diff written to temporary file. Preparing Python script..."

# Create a temporary Python script file
$pythonScriptPath = [System.IO.Path]::GetTempFileName() + ".py"
$pythonScript = @"
import sys
import json
import requests
import logging

logging.basicConfig(filename='gitdone_debug.log', level=logging.DEBUG)
logging.debug("Python script started")

print("Python script started")
print(f"Ollama API URL: {sys.argv[1]}")

diff = sys.stdin.read()
logging.debug(f"Received diff of length: {len(diff)}")

payload = {
    "model": "llama3.1",
    "prompt": f"Summarize the following git diff in a concise commit message:\n\n{diff}",
    "stream": False
}

try:
    logging.debug("Sending request to Ollama API")
    response = requests.post(sys.argv[1] + "/api/generate", json=payload, timeout=30)
    response.raise_for_status()
    summary = response.json().get('response', '').strip()
    logging.debug(f"Generated summary: {summary}")
    print(summary)
except requests.exceptions.Timeout:
    logging.error("Request to Ollama API timed out")
    print("Request to Ollama API timed out")
    sys.exit(1)
except Exception as e:
    logging.exception("An error occurred:")
    print(f"Error occurred: {str(e)}")
    sys.exit(1)
"@

Write-Host "Writing Python script to temporary file..."
# Write the Python script to the temporary file
$pythonScript | Out-File -FilePath $pythonScriptPath -Encoding utf8

Write-Host "Executing Python script..."
# Execute the Python script and capture the output
$summary = Get-Content $tempFile | python $pythonScriptPath $OllamaAPIURL 2>&1

Write-Host "Python script execution completed. Cleaning up temporary files..."
# Remove temporary files
Remove-Item -Path $pythonScriptPath -ErrorAction SilentlyContinue
Remove-Item -Path $tempFile -ErrorAction SilentlyContinue

if (-not $summary) {
    Write-Host "Failed to generate commit summary." -ForegroundColor Red
    exit 1
}

Write-Host "Generated commit summary: $summary" -ForegroundColor Green

Write-Host "Committing changes..."
# Commit changes
git commit -m "$summary"

Write-Host "Pushing to origin main..."
# Push to origin main
git push origin main

# Print success message
Write-Host "Changes committed and pushed with summary: $summary" -ForegroundColor Green
