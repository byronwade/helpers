# Check if Go is installed
$goPath = Get-Command go -ErrorAction SilentlyContinue
if (-not $goPath) {
    Write-Host "Go is not installed. Installing Go..."

    # Download and install Go for Windows
    Invoke-WebRequest -Uri https://golang.org/dl/go1.18.4.windows-amd64.msi -OutFile go.msi
    Start-Process msiexec.exe -ArgumentList '/i go.msi /quiet /norestart' -Wait

    # Add Go to PATH
    $env:Path += ";C:\Go\bin"
    [Environment]::SetEnvironmentVariable("Path", $env:Path, [EnvironmentVariableTarget]::User)
} else {
    Write-Host "Go is already installed."
}

# Create the project directory
New-Item -Path $env:USERPROFILE -Name "gitdone" -ItemType "directory" -Force | Out-Null
Set-Location "$env:USERPROFILE\gitdone"

# Fetch the Go dependencies
go mod init gitdone
go get

# Build the Go program
go build -o gitdone.exe gitdone.go

# Move the binary to a directory in your PATH
Move-Item -Path ".\gitdone.exe" -Destination "$env:USERPROFILE\AppData\Local\Microsoft\WindowsApps\"

Write-Host "Setup complete. You can now run 'gitdone' from anywhere in PowerShell."
