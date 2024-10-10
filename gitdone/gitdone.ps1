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
import time

changes = sys.stdin.read()
prompt = f"Summarize the following git changes in a concise commit message:\n\n{changes}"

payload = {
    "model": "tinyllama",
    "prompt": prompt,
    "stream": False
}

try:
    start_time = time.time()
    response = requests.post("$OllamaAPIURL/api/generate", json=payload, timeout=10)
    response.raise_for_status()
    summary = response.json()['response'].strip().replace('"', '')
    end_time = time.time()
    print(json.dumps({"summary": summary, "time": end_time - start_time}))
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)
"@

# Write the Python script to the temporary file
$pythonScript | Out-File -FilePath $pythonScriptPath -Encoding utf8

# Execute the Python script with a spinner
$job = Start-Job -ScriptBlock { 
    param($pythonScriptPath, $changes)
    $changes | python $pythonScriptPath
} -ArgumentList $pythonScriptPath, $changes

Show-Spinner -Duration 10

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
