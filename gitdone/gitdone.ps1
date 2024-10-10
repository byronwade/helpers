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
import subprocess

def get_detailed_changes():
    try:
        diff_output = subprocess.check_output(['git', 'diff', '--cached', '--stat'], universal_newlines=True)
        detailed_output = subprocess.check_output(['git', 'diff', '--cached'], universal_newlines=True)
        return diff_output, detailed_output
    except subprocess.CalledProcessError:
        return "", ""

diff_summary, detailed_changes = get_detailed_changes()

prompt = f"Based on the following git changes, write a concise and accurate commit message (max 50 characters, no quotes):\n\nSummary:\n{diff_summary}\n\nDetailed changes:\n{detailed_changes[:500]}...\n\nCommit message:"

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
    commit_message = commit_message[:50].rstrip()
    end_time = time.time()
    print(json.dumps({"summary": commit_message, "time": end_time - start_time}))
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)
"@

# Write the Python script to the temporary file
$pythonScript | Out-File -FilePath $pythonScriptPath -Encoding utf8

# Execute the Python script with a spinner
$job = Start-Job -ScriptBlock { 
    param($pythonScriptPath)
    & python $pythonScriptPath
} -ArgumentList $pythonScriptPath

Show-Spinner -Duration 30

$result = Receive-Job -Job $job -Wait | ConvertFrom-Json
Remove-Job -Job $job

# Remove temporary file
Remove-Item -Path $pythonScriptPath -ErrorAction SilentlyContinue

if ($result.error) {
    Write-Host "Failed to generate commit summary: $($result.error)" -ForegroundColor Red
    exit 1
}

$summary = $result.summary
$processingTime = [math]::Round($result.time, 2)

Write-Host "Commit message generated in $processingTime seconds."
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
