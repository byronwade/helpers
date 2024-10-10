# Add all changes
git add .

# Check for environment variable for Ollama API URL
$OllamaAPIURL = if ($env:OLLAMA_API_URL) { $env:OLLAMA_API_URL } else { "http://localhost:11434" }

# Function to ensure Ollama is running and the model is available
function Ensure-OllamaRunning {
    Write-Host "Checking Ollama service..."
    if (!(Get-NetTCPConnection -LocalPort 11434 -ErrorAction SilentlyContinue)) {
        Write-Host "Ollama is not running. Starting Ollama service..."
        Start-Process ollama -ArgumentList "serve" -NoNewWindow
        Start-Sleep -Seconds 10  # Wait for Ollama to start
    } else {
        Write-Host "Ollama service is already running."
    }

    $modelName = "llama2"
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
    "model": "llama2",
    "prompt": f"Summarize the following git diff in a concise commit message:\n\n{diff}",
    "stream": False
}

try:
    logging.debug("Sending request to Ollama API")
    response = requests.post(sys.argv[1] + "/api/generate", json=payload, timeout=120)
    logging.debug(f"Response status code: {response.status_code}")
    response.raise_for_status()
    summary = response.json().get('response', '').strip()
    logging.debug(f"Generated summary: {summary}")
    print(summary)
except requests.exceptions.Timeout:
    logging.error("Request to Ollama API timed out")
    print("Request to Ollama API timed out")
    sys.exit(1)
except requests.exceptions.RequestException as e:
    logging.error(f"Request failed: {str(e)}")
    print(f"Request failed: {str(e)}")
    sys.exit(1)
except Exception as e:
    logging.exception("An unexpected error occurred:")
    print(f"An unexpected error occurred: {str(e)}")
    sys.exit(1)
"@

Write-Host "Writing Python script to temporary file..."
# Write the Python script to the temporary file
$pythonScript | Out-File -FilePath $pythonScriptPath -Encoding utf8

Write-Host "Executing Python script..."

# Start time
$startTime = Get-Date

# Create a job to run the Python script
$job = Start-Job -ScriptBlock {
    param($tempFile, $pythonScriptPath, $OllamaAPIURL)
    Get-Content $tempFile | python $pythonScriptPath $OllamaAPIURL 2>&1
} -ArgumentList $tempFile, $pythonScriptPath, $OllamaAPIURL

# Spinner animation
$spinner = @('|', '/', '-', '\')
$spinnerIndex = 0

# Display spinner while job is running
while ($job.State -eq 'Running') {
    $elapsedTime = (Get-Date) - $startTime
    $status = "Processing{0} Elapsed time: {1:mm\:ss}" -f $spinner[$spinnerIndex], $elapsedTime
    Write-Host "`r$status" -NoNewline
    $spinnerIndex = ($spinnerIndex + 1) % 4
    Start-Sleep -Milliseconds 100
}

# Clear the spinner line
Write-Host "`r" -NoNewline

# Get the result
$summary = Receive-Job -Job $job
Remove-Job -Job $job

$elapsedTime = (Get-Date) - $startTime
Write-Host "Python script execution completed in $($elapsedTime.TotalSeconds.ToString("F2")) seconds. Cleaning up temporary files..."

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
