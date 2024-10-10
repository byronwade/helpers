# Add all changes
git add .

# Check for environment variable for Ollama API URL
if (-not $env:OLLAMA_API_URL) {
    Write-Host "Please set the OLLAMA_API_URL environment variable."
    exit 1
}

# Get git diff to summarize
$changes = git diff --cached

# Check if there are any changes staged
if ([string]::IsNullOrEmpty($changes)) {
    Write-Host "No changes to commit."
    exit 0
}

# Call Ollama API to summarize changes
$summary = python -c @"
import os
import requests
import json

ollama_api_url = os.getenv('OLLAMA_API_URL')

diff = '''$changes'''

payload = {
    "model": "llama2",
    "prompt": "Summarize the following git diff in a concise commit message:\n\n" + diff,
    "stream": False
}

response = requests.post(f"{ollama_api_url}/api/generate", json=payload)
response_json = response.json()

summary = response_json['response'].strip()
print(summary)
"@

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
