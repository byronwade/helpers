# Requires PowerShell 5.0 or higher
# This script sets up gitdone on Windows automatically with no user intervention.

# Function to write colored output
function Write-Color($Text, $Color) {
    Write-Host $Text -ForegroundColor $Color
}

# Function to handle errors
function Handle-Error($Message) {
    Write-Color "ERROR: $Message" Red
    # Create error log file
    $errorLog = Join-Path $env:TEMP "gitdone_setup_error.log"
    $Message | Out-File $errorLog -Append
    Write-Color "Error details written to: $errorLog" Yellow
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

# Check if Go is installed
$goPath = Get-Command go -ErrorAction SilentlyContinue
if (-not $goPath) {
    Write-Color "Go is not installed. Installing Go..." Yellow

    # Download the latest Go MSI installer
    try {
        $goDownloadPage = Invoke-WebRequest -Uri "https://golang.org/dl/" -UseBasicParsing
        $goDownloadLink = ($goDownloadPage.Links | Where-Object {$_.href -like "*.windows-amd64.msi"} | Select-Object -First 1).href

        if (-not $goDownloadLink) {
            Handle-Error "Failed to find the Go download link."
        }

        # Ensure the download link is absolute
        if (-not $goDownloadLink.StartsWith("http")) {
            $goDownloadLink = "https://golang.org$goDownloadLink"
        }

        # Download the MSI installer
        $goMsi = "$env:TEMP\go_latest.msi"
        Write-Color "Downloading Go installer from $goDownloadLink..." Yellow
        Invoke-WebRequest -Uri $goDownloadLink -OutFile $goMsi -UseBasicParsing

        # Install Go silently
        Write-Color "Installing Go..." Yellow
        $installProcess = Start-Process msiexec.exe -ArgumentList "/i `"$goMsi`" /qn /norestart" -Wait -NoNewWindow -PassThru

        if ($installProcess.ExitCode -ne 0) {
            Handle-Error "Go installation failed with exit code: $($installProcess.ExitCode)"
        }

        # Remove the installer
        Remove-Item $goMsi -Force

        # Add Go to PATH
        $goBinPath = "C:\Go\bin"
        [Environment]::SetEnvironmentVariable("Path", $env:Path + ";$goBinPath", [EnvironmentVariableTarget]::Machine)
        $env:Path += ";$goBinPath"

        Write-Color "Go has been installed." Green
    } catch {
        Handle-Error "Failed to install Go: $_`nStack Trace: $($_.ScriptStackTrace)"
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
try {
    go build -o gitdone.exe $gitdoneGoPath
    if (-not (Test-Path ".\gitdone.exe")) {
        Handle-Error "Build completed but gitdone.exe not found"
    }
    Write-Color "Build completed successfully" Green
} catch {
    Handle-Error "Failed to build gitdone.exe: $_"
}

# Install the binary
# Choose an installation directory in PATH
$installDir = "$env:USERPROFILE\.local\bin"  # Default to user's local bin

# Create installation directory if it doesn't exist
if (-not (Test-Path $installDir)) {
    try {
        New-Item -Path $installDir -ItemType Directory -Force | Out-Null
        Write-Color "Created installation directory: $installDir" Green
    } catch {
        Handle-Error "Failed to create installation directory: $_"
    }
}

# Ensure directory is in PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
if ($userPath -notlike "*$installDir*") {
    try {
        [Environment]::SetEnvironmentVariable(
            "Path", 
            "$userPath;$installDir", 
            [EnvironmentVariableTarget]::User
        )
        $env:Path = "$env:Path;$installDir"
        Write-Color "Added $installDir to PATH." Green
    } catch {
        Handle-Error "Failed to update PATH: $_"
    }
}

# Move the binary
Write-Color "Installing gitdone.exe to $installDir..." Yellow
$targetPath = Join-Path $installDir "gitdone.exe"

# Remove existing file if it exists
if (Test-Path $targetPath) {
    try {
        Remove-Item $targetPath -Force
        Write-Color "Removed existing gitdone.exe" Yellow
    } catch {
        Handle-Error "Failed to remove existing gitdone.exe: $_"
    }
}

try {
    Move-Item -Path ".\gitdone.exe" -Destination $targetPath -Force -ErrorAction Stop
    Write-Color "Moved gitdone.exe to $targetPath" Green
} catch {
    Handle-Error "Failed to move gitdone.exe to $installDir. Error: $_"
}

# Create a PowerShell profile if it doesn't exist
$profileDir = Split-Path $PROFILE
if (-not (Test-Path $profileDir)) {
    New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $PROFILE)) {
    New-Item -Path $PROFILE -ItemType File -Force | Out-Null
}

# Remove any existing gitdone alias or function from profile
if (Test-Path $PROFILE) {
    $profileContent = Get-Content $PROFILE -Raw
    $profileContent = $profileContent -replace "(?ms)function gitdone.*?}\r?\n?", ""
    $profileContent = $profileContent -replace "Set-Alias.*gitdone.*\r?\n?", ""
    Set-Content $PROFILE $profileContent
}

# Add the installation directory to the current session PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + 
            [System.Environment]::GetEnvironmentVariable("Path", "User")

# Create a function in PowerShell profile to run gitdone.exe
$functionContent = @"

# GitDone function
function Invoke-GitDone {
    try {
        & "$targetPath" @args
    } catch {
        Write-Error "Error running gitdone: `$_"
    }
}
Set-Alias -Name gitdone -Value Invoke-GitDone
"@

Add-Content $PROFILE $functionContent

# Verify installation
$gitdonePath = Get-Command gitdone.exe -ErrorAction SilentlyContinue
if (-not $gitdonePath) {
    Write-Color "Installation completed but gitdone.exe not found in PATH." Yellow
    Write-Color "Installation location: $targetPath" Yellow
    Write-Color "Please restart your terminal and try again." Yellow
    Write-Color "If the issue persists, run this command:" Yellow
    Write-Color "`$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')" Yellow
} else {
    Write-Color "gitdone successfully installed at $($gitdonePath.Source)" Green
}

# Reload the PowerShell profile
try {
    . $PROFILE
    Write-Color "PowerShell profile reloaded." Green
} catch {
    Write-Color "Please restart your PowerShell session to use gitdone." Yellow
}

Write-Color @"
Installation complete! To use gitdone:
1. Close and reopen your PowerShell terminal
2. Run 'gitdone' from any directory
"@ Green

# Add Git check at the beginning of the script
function Test-GitInstallation {
    try {
        $gitVersion = git --version
        if ($gitVersion) {
            Write-Color "Git version: $gitVersion" Green
            return $true
        }
    } catch {
        Write-Color "Git is not installed or not in PATH" Yellow
        return $false
    }
    return $false
}

# Call Git check before proceeding
if (-not (Test-GitInstallation)) {
    Handle-Error "Git is required but not found. Please install Git and try again."
}
