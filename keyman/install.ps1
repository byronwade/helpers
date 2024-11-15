# Windows Installation Script
$ErrorActionPreference = "Stop"

function Test-GoInstallation {
    try {
        $goVersion = go version
        Write-Host "Go is already installed: $goVersion"
        return $true
    } catch {
        return $false
    }
}

function Install-Go {
    Write-Host "Installing Go..."
    $goVersion = "1.21.4"
    $downloadUrl = "https://golang.org/dl/go$goVersion.windows-amd64.msi"
    $installer = "$env:TEMP\go$goVersion.windows-amd64.msi"
    
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installer
        Start-Process msiexec.exe -ArgumentList "/i", $installer, "/quiet" -Wait
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    } finally {
        if (Test-Path $installer) {
            Remove-Item $installer
        }
    }
}

function Enable-SSHAgent {
    Write-Host "Ensuring SSH Agent is running..."
    try {
        $sshAgentService = Get-Service -Name "ssh-agent" -ErrorAction Stop
        
        if ($sshAgentService.Status -ne "Running") {
            Set-Service -Name "ssh-agent" -StartupType Automatic
            Start-Service ssh-agent
        }
    } catch {
        Write-Host "Failed to configure SSH agent: $_" -ForegroundColor Red
    }
}

# Main installation
try {
    if (-not (Test-GoInstallation)) {
        Install-Go
    }

    Enable-SSHAgent

    $installDir = Join-Path $env:LOCALAPPDATA "Keyman"
    
    # Build keyman
    Write-Host "Building Keyman..."
    $buildOutput = go build -o "$installDir\keyman.exe" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed: $buildOutput"
    }

    # Update PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $userPath.Contains($installDir)) {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$installDir", "User")
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + 
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
    }

    Write-Host "`nInstallation complete! Running initial setup...`n"
    & "$installDir\keyman.exe" init

} catch {
    Write-Host "Installation failed: $_" -ForegroundColor Red
    exit 1
} 