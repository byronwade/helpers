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

# Get the Git username
$userName = git config user.name

Write-Host "Generating commit message..."

# Create a temporary Python script file
$pythonScriptPath = [System.IO.Path]::GetTempFileName() + ".py"
$pythonScript = @"
import sys
import requests
import json
import time
import random

def generate_commit_message(changes, user_name, max_retries=3):
    prompt = f"""You are a highly skilled developer and commit message generator. Generate a concise, professional commit message for the provided git diff. The message should:

1. Begin with the current authorized user's name: {user_name}.
2. Clearly state the files changed.
3. Briefly summarize the types of changes made in each file (e.g., added functionality, refactored code, fixed bugs).
4. Be concise and easy to understand.
5. Do NOT include any statistics or line numbers.

Format the commit message as follows:

{user_name} made changes in:
- [filename]: [brief description of changes]
- [filename]: [brief description of changes]

Ensure the message is professional and focuses on the nature of the changes, not the quantity."""

    payload = {
        "model": "codellama",
        "prompt": prompt,
        "stream": False
    }

    for attempt in range(max_retries):
        try:
            start_time = time.time()
            response = requests.post("$OllamaAPIURL/api/generate", json=payload, timeout=30)
            response.raise_for_status()
            summary = response.json().get('response', '').strip().replace('"', '').replace('\n', ' ')
            end_time = time.time()
            if summary:
                return {"summary": summary, "time": end_time - start_time}
        except Exception as e:
            if attempt == max_retries - 1:
                return {"error": str(e)}
            time.sleep(random.uniform(1, 3))  # Random delay before retry

changes = sys.stdin.read()
user_name = sys.argv[1]  # Get the username from the command line argument
result = generate_commit_message(changes, user_name)
print(json.dumps(result))
"@

# Write the Python script to the temporary file
$pythonScript | Out-File -FilePath $pythonScriptPath -Encoding utf8

# Execute the Python script with a spinner
$job = Start-Job -ScriptBlock { 
    param($pythonScriptPath, $changes, $userName)
    $changes | python $pythonScriptPath $userName
} -ArgumentList $pythonScriptPath, $changes, $userName

Show-Spinner -Duration 40  # Increased duration to account for retries

$result = Receive-Job -Job $job -Wait | ConvertFrom-Json
Remove-Job -Job $job

# Remove temporary file
Remove-Item -Path $pythonScriptPath -ErrorAction SilentlyContinue

if ($result.error) {
    Write-Host "Failed to generate commit summary: $($result.error)" -ForegroundColor Red
    $summary = Read-Host "Please enter a commit message manually"
} else {
    $summary = $result.summary
    $processingTime = [math]::Round($result.time, 2)
    Write-Host "Commit message generated in $processingTime seconds."
    Write-Host "Generated commit message: $summary"
}

# Ensure the commit message is not empty
if (-not [string]::IsNullOrWhiteSpace($summary)) {
    Write-Host "Committing changes..."
    git commit -m "$summary" > $null 2>&1

    $commitSuccess = $?
    if (-not $commitSuccess) {
        Write-Host "Failed to commit changes. Please check your git configuration." -ForegroundColor Red
        exit 1
    }

    Write-Host "Pushing to origin main..."
    git push origin main > $null 2>&1

    $pushSuccess = $?
    if (-not $pushSuccess) {
        Write-Host "Failed to push changes. Please check your git configuration and remote repository." -ForegroundColor Red
        exit 1
    }

    Write-Host "Changes committed and pushed with summary: $summary" -ForegroundColor Green
} else {
    Write-Host "Commit message is empty. Aborting commit." -ForegroundColor Red
}