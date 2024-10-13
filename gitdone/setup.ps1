# Requires PowerShell 5.0 or higher
# This script sets up gitdone on Windows automatically with no user intervention.

# Function to write colored output
function Write-Color($Text, $Color) {
    Write-Host $Text -ForegroundColor $Color
}

# Function to handle errors
function Handle-Error($Message) {
    Write-Color "ERROR: $Message" Red
    exit 1
}

# Function to check for administrative privileges
function Ensure-Admin {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Color "Restarting script as Administrator..." Yellow
        Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
}

# Start script execution
Write-Color "Starting gitdone setup..." Yellow

# Ensure script is running as Administrator
Ensure-Admin

# Check if Go is installed
$goPath = Get-Command go -ErrorAction SilentlyContinue
if (-not $goPath) {
    Write-Color "Go is not installed. Installing Go..." Yellow

    # Download the latest Go MSI installer
    try {
        $goDownloadPage = Invoke-WebRequest -Uri "https://golang.org/dl/" -UseBasicParsing
        $goDownloadLink = ($goDownloadPage.Content | Select-String -Pattern 'https://go.dev/dl/go[0-9.]+.windows-amd64.msi' -AllMatches).Matches[0].Value

        if (-not $goDownloadLink) {
            Handle-Error "Failed to find the Go download link."
        }

        # Download the MSI installer
        $goMsi = "$env:TEMP\go_latest.msi"
        Write-Color "Downloading Go installer..." Yellow
        Invoke-WebRequest -Uri $goDownloadLink -OutFile $goMsi -UseBasicParsing

        # Install Go silently
        Write-Color "Installing Go..." Yellow
        Start-Process msiexec.exe -ArgumentList "/i `"$goMsi`" /qn /norestart" -Wait -NoNewWindow

        # Remove the installer
        Remove-Item $goMsi -Force

        # Add Go to PATH
        $goBinPath = "C:\Go\bin"
        [Environment]::SetEnvironmentVariable("Path", $env:Path + ";$goBinPath", [EnvironmentVariableTarget]::Machine)
        $env:Path += ";$goBinPath"

        Write-Color "Go has been installed." Green
    } catch {
        Handle-Error "Failed to install Go: $_"
    }
} else {
    Write-Color "Go is already installed." Green
}

# Verify Go installation
try {
    $goVersion = go version
    if (-not $goVersion) {
        Handle-Error "Failed to verify Go installation."
    } else {
        Write-Color "Go version: $goVersion" Green
    }
} catch {
    Handle-Error "Error verifying Go installation: $_"
}

# Determine script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Write-Color "Script directory: $scriptDir" Yellow

# Ensure gitdone.go exists in script directory
$gitdoneGoPath = Join-Path $scriptDir "gitdone.go"
if (-not (Test-Path $gitdoneGoPath)) {
    Handle-Error "gitdone.go file not found in script directory ($scriptDir)."
}

# Initialize Go module
Write-Color "Initializing Go module..." Yellow
Set-Location $scriptDir
if (-not (Test-Path "go.mod")) {
    go mod init gitdone | Out-Null
} else {
    Write-Color "Go module already initialized." Yellow
}

# Tidy dependencies
Write-Color "Tidying Go dependencies..." Yellow
go mod tidy

# Build the Go program
Write-Color "Building gitdone.exe..." Yellow
go build -o gitdone.exe $gitdoneGoPath

# Install the binary
# Choose an installation directory in PATH
$installDirs = ($env:Path).Split(';')
$installDir = $null

foreach ($dir in $installDirs) {
    if ([string]::IsNullOrWhiteSpace($dir)) { continue }
    if (Test-Path $dir -and (Get-Item $dir).Attributes -notmatch "ReadOnly" -and (Get-Item $dir).Attributes -notmatch "Hidden") {
        try {
            $testFile = Join-Path $dir "test.txt"
            New-Item -Path $testFile -ItemType File -Force -ErrorAction Stop | Out-Null
            Remove-Item $testFile -Force
            $installDir = $dir
            break
        } catch {
            continue
        }
    }
}

if (-not $installDir) {
    # If no suitable directory found, create one
    $installDir = "$env:USERPROFILE\bin"
    if (-not (Test-Path $installDir)) {
        New-Item -Path $installDir -ItemType Directory -Force | Out-Null
    }

    # Add to PATH
    [Environment]::SetEnvironmentVariable("Path", $env:Path + ";$installDir", [EnvironmentVariableTarget]::User)
    $env:Path += ";$installDir"
    Write-Color "Added $installDir to PATH." Yellow
}

# Move the binary
Write-Color "Installing gitdone.exe to $installDir..." Yellow
Move-Item -Path ".\gitdone.exe" -Destination $installDir -Force

# Verify installation
$gitdonePath = Get-Command gitdone -ErrorAction SilentlyContinue
if (-not $gitdonePath) {
    Handle-Error "gitdone installation failed."
} else {
    Write-Color "gitdone successfully installed at $gitdonePath." Green
}

Write-Color "Setup complete. You can now run 'gitdone' from anywhere in PowerShell." Green
