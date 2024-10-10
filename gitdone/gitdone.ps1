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

# Function to display spinner
function Show-Spinner {
    param (
        [int]$Duration
    )
    $spinner = @('|', '/', '-', '\')
    $startTime = Get-Date
    $elapsedTime = [TimeSpan]::Zero

    while ($elapsedTime.TotalSeconds -lt $Duration) {
        $spinnerChar = $spinner[$elapsedTime.Seconds % $spinner.Length]
        Write-Host "`rProcessing $spinnerChar Elapsed time: $($elapsedTime.ToString('mm\:ss'))" -NoNewline
        Start-Sleep -Milliseconds 100
        $elapsedTime = (Get-Date) - $startTime
    }
    Write-Host "`r" -NoNewline
}

# Ensure Ollama is running
Ensure-OllamaRunning

# Get git diff to summarize
$changes = git diff --cached --name-status

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
import time
import re

def parse_git_diff(diff):
    files_changed = re.findall(r'(\w+)\s+(.+)', diff)
    return files_changed

changes = sys.stdin.read()
files_changed = parse_git_diff(changes)

summary = f"Changed {len(files_changed)} file(s): "
summary += ", ".join([f"{action} {file}" for action, file in files_changed[:3]])
if len(files_changed) > 3:
    summary += f" and {len(files_changed) - 3} more"

prompt = f"Based on the following git changes, write a concise and meaningful commit message (max 50 characters, no quotes):\n\n{summary}\n\nCommit message:"

payload = {
    "model": "tinyllama",
    "prompt": prompt,
    "stream": False
}

try:
    start_time = time.time()
    response = requests.post("$OllamaAPIURL/api/generate", json=payload, timeout=30)
    response.raise_for_status()
    commit_message = response.json()['response'].strip()
    commit_message = commit_message[:50].rstrip()  # Ensure the message is no longer than 50 characters and remove trailing spaces
    end_time = time.time()
    print(json.dumps({"summary": commit_message, "time": end_time - start_time}))
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)
"@

# Write the Python script to the temporary file
$pythonScript | Out-File -FilePath $pythonScriptPath -Encoding utf8

# Execute the Python script
$result = $changes | python $pythonScriptPath | ConvertFrom-Json

# Remove temporary file
Remove-Item -Path $pythonScriptPath -ErrorAction SilentlyContinue

if ($result.error) {
    Write-Host "Failed to generate commit summary: $($result.error)" -ForegroundColor Red
    exit 1
}

$summary = $result.summary
$processingTime = [math]::Round($result.time, 2)

Write-Host "Commit message generated in $processingTime seconds."
Write-Host "Summary of changes:"
git diff --cached --stat
Write-Host "Generated commit message: $summary"

Write-Host "Committing changes..."
git commit -m "$summary"

$commitSuccess = $?
if (-not $commitSuccess) {
    Write-Host "Failed to commit changes. Please check your git configuration." -ForegroundColor Red
    exit 1
}

Write-Host "Pushing to origin main..."
git push origin main

$pushSuccess = $?
if (-not $pushSuccess) {
    Write-Host "Failed to push changes. Please check your git configuration and remote repository." -ForegroundColor Red
    exit 1
}

Write-Host "Changes committed and pushed with summary: $summary" -ForegroundColor Green
