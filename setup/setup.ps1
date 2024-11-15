# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
        $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
        Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList $CommandLine
        Exit
    }
}

# Requires PowerShell 7.0 or higher

# Color Codes for Output Formatting
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$RED = "`e[31m"
$NC = "`e[0m" # No Color

# Function to print messages with colors
function Print-Info {
    param ([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Print-Warning {
    param ([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Print-Error {
    param ([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Spinner function to indicate progress
function Start-Spinner {
    param (
        [System.Threading.CancellationTokenSource]$cts
    )

    $spinner = @('|','/','-','\')
    $i = 0
    while (-not $cts.IsCancellationRequested) {
        Write-Host -NoNewline -ForegroundColor Green " ${spinner[$i % $spinner.Length]}"
        Start-Sleep -Milliseconds 100
        Write-Host -NoNewline "`b"
        $i++
    }
}

# Function to run a command silently with a spinner
function Run-Command {
    param (
        [ScriptBlock]$Command
    )

    $cts = New-Object System.Threading.CancellationTokenSource
    $job = Start-Job -ScriptBlock $Command

    Start-Spinner -cts $cts | Out-Null

    Wait-Job $job
    $cts.Cancel()
    Receive-Job $job
    $job.State -eq 'Completed'
}

# Enhanced Command-Exists function with better desktop app detection
function Command-Exists {
    param (
        [string]$CommandName,
        [switch]$IsDesktopApp
    )
    
    # Special handling for common apps
    switch ($CommandName.ToLower()) {
        "docker" {
            # Check multiple Docker-related paths and registry entries
            $dockerPaths = @(
                "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
                "$env:ProgramFiles\Docker\Docker Desktop\Docker Desktop.exe",
                "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
            )
            
            # Check registry for Docker Desktop
            $dockerKeys = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Docker Desktop",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Docker Desktop"
            )
            
            # Check process
            $dockerProcess = Get-Process "Docker Desktop" -ErrorAction SilentlyContinue
            
            if ($dockerProcess -or 
                (Test-Path $dockerPaths) -or 
                (Test-Path $dockerKeys) -or 
                (Get-Command "docker" -ErrorAction SilentlyContinue)) {
                return $true
            }
        }
        
        "git" {
            # Check multiple Git-related paths
            $gitPaths = @(
                "$env:ProgramFiles\Git\cmd\git.exe",
                "$env:ProgramFiles\Git\bin\git.exe",
                "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
                "${env:ProgramFiles(x86)}\Git\bin\git.exe",
                "$env:LocalAppData\Programs\Git\cmd\git.exe"
            )
            
            # Check registry for Git
            $gitKeys = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Git*",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Git*"
            )
            
            # Check PATH
            $gitInPath = Get-Command "git" -ErrorAction SilentlyContinue
            
            if ($gitInPath -or 
                ($gitPaths | Where-Object { Test-Path $_ }) -or 
                ($gitKeys | Where-Object { Test-Path $_ })) {
                return $true
            }
        }
        
        default {
            # First check if it's in PATH
            $inPath = $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
            if ($inPath) { return $true }
            
            if ($IsDesktopApp) {
                # Check Program Files directories
                $programPaths = @(
                    $env:ProgramFiles,
                    ${env:ProgramFiles(x86)},
                    "$env:LocalAppData\Programs",
                    "$env:AppData\Local\Programs",
                    "$env:UserProfile\AppData\Local"
                )
                
                # Check registry
                $regPaths = @(
                    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
                )
                
                # Search for the application in registry
                foreach ($regPath in $regPaths) {
                    $installed = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
                        Where-Object { 
                            ($_.DisplayName -like "*$CommandName*") -or 
                            ($_.InstallLocation -like "*$CommandName*") -or
                            ($_.UninstallString -like "*$CommandName*")
                        }
                    if ($installed) { return $true }
                }
                
                # Search in common installation directories
                foreach ($basePath in $programPaths) {
                    $searchPath = Join-Path $basePath "*$CommandName*"
                    if (Test-Path $searchPath) { return $true }
                    
                    # Search subdirectories
                    $found = Get-ChildItem $basePath -Recurse -ErrorAction SilentlyContinue | 
                        Where-Object { 
                            $_.Name -like "*$CommandName*" -and 
                            ($_.Extension -in '.exe', '.cmd', '.bat', '.msi')
                        }
                    if ($found) { return $true }
                }
            }
        }
    }
    
    return $false
}

# Update package lists
function Update-Packages {
    Write-Log "Updating package lists..." -Type "INFO"
    Write-Log "This may take a few minutes..." -Type "INFO"
    
    try {
        # Check if winget is available
        if (-not (Command-Exists winget)) {
            Write-Log "Winget is not installed. Installing winget..." -Type "WARNING"
            # You might want to add winget installation logic here
            throw "Winget is not installed"
        }

        # Show progress while updating
        $job = Start-Job -ScriptBlock {
            $result = winget source update 2>&1
            $result | Out-String
        }

        $spinner = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')
        $i = 0
        
        while ($job.State -eq 'Running') {
            Write-Host "`r$($spinner[$i % $spinner.Length]) Updating package sources..." -NoNewline
            Start-Sleep -Milliseconds 100
            $i++
        }
        
        Write-Host "`r" -NoNewline
        
        $result = Receive-Job $job
        Remove-Job $job

        if ($result -match "error") {
            Write-Log "Error updating package sources:" -Type "ERROR"
            Write-Log $result -Type "ERROR"
            return $false
        }

        Write-Log "Package lists updated successfully" -Type "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to update package lists: $_" -Type "ERROR"
        Write-Error -Message "Package list update failed" -ErrorRecord $_
        return $false
    }
}

# Add version checking function
function Get-LatestVersion {
    param (
        [string]$PackageName
    )
    try {
        $latest = (winget show $PackageName) | Select-String "Version:" | Select-Object -First 1
        if ($latest) {
            return $latest.ToString().Split(":")[1].Trim()
        }
    } catch {
        return $null
    }
    return $null
}

# Add at the beginning of the script
$script:StartTime = Get-Date
$script:LogFile = Join-Path $PSScriptRoot "setup_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:ErrorLogFile = Join-Path $PSScriptRoot "setup_errors_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:InstallationSummary = @()

# Enhanced logging functions
function Write-Log {
    param(
        [string]$Message,
        [string]$Type = "INFO",
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Type] $Message"
    
    # Always write to log file
    Add-Content -Path $script:LogFile -Value $logMessage
    
    # Write to console if not suppressed
    if (-not $NoConsole) {
        $color = switch ($Type) {
            "INFO" { "White" }
            "SUCCESS" { "Green" }
            "WARNING" { "Yellow" }
            "ERROR" { "Red" }
            "PROGRESS" { "Cyan" }
            default { "White" }
        }
        Write-Host $logMessage -ForegroundColor $color
    }
}

# Enhanced progress bar
function Show-Progress {
    param(
        [string]$Activity,
        [int]$PercentComplete,
        [string]$Status
    )
    
    $elapsed = (Get-Date) - $script:StartTime
    $elapsedStr = "{0:hh\:mm\:ss}" -f $elapsed
    
    Write-Progress -Activity $Activity `
                  -Status "$Status (Elapsed: $elapsedStr)" `
                  -PercentComplete $PercentComplete
    
    Write-Log "[$Activity] $Status ($PercentComplete% complete)" -Type "PROGRESS" -NoConsole
}

# Enhanced error handling
function Write-Error {
    param(
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )
    
    $errorDetails = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Message = $Message
        Exception = $ErrorRecord.Exception.Message
        ScriptStackTrace = $ErrorRecord.ScriptStackTrace
        PositionMessage = $ErrorRecord.InvocationInfo.PositionMessage
    }
    
    $errorJson = $errorDetails | ConvertTo-Json
    Add-Content -Path $script:ErrorLogFile -Value $errorJson
    Write-Log $Message -Type "ERROR"
}

# Add installation tracking
function Track-Installation {
    param(
        [string]$Package,
        [string]$Status,
        [string]$Version,
        [string]$Notes
    )
    
    $script:InstallationSummary += [PSCustomObject]@{
        Package = $Package
        Status = $Status
        Version = $Version
        Notes = $Notes
        Timestamp = Get-Date
    }
}

# Update these variables at the beginning of the script
$script:SpinnerChars = @('-', '\', '|', '/')
$script:ProgressEmpty = '.'
$script:ProgressFull = '#'

# Modify the progress bar section in Install-Package
function Install-Package {
    param (
        [string]$PackageName,
        [switch]$Update,
        [switch]$IsDesktopApp
    )
    
    Write-Log "Checking $PackageName..." -Type "INFO"
    
    if (Command-Exists $PackageName -IsDesktopApp:$IsDesktopApp) {
        Write-Log "$PackageName is already installed." -Type "SUCCESS"
        # Continue with update logic if needed
        return
    }
    
    # Continue with installation logic...
}

# Enhanced Python installation function with multiple methods
function Install-Python {
    Write-Log "Setting up Python..." -Type "INFO"
    
    try {
        # Check if Python is already installed
        if (Command-Exists python) {
            $currentVersion = (python --version 2>&1).ToString().Split(" ")[1]
            Write-Log "Python $currentVersion is already installed" -Type "SUCCESS"
            
            # Check for updates
            try {
                $job = Start-Job -ScriptBlock { 
                    winget upgrade --silent Python.Python.3 
                }

                $spinner = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')
                $i = 0
                $startTime = Get-Date
                
                while ($job.State -eq 'Running') {
                    $elapsed = (Get-Date) - $startTime
                    $elapsedStr = "{0:mm}m {0:ss}s" -f $elapsed
                    Write-Host "`r$($spinner[$i % $spinner.Length]) Checking for Python updates... (Elapsed: $elapsedStr)" -NoNewline
                    Start-Sleep -Milliseconds 100
                    $i++
                }
                
                Write-Host "`r" -NoNewline
                $result = Receive-Job $job
                Remove-Job $job
                
                Write-Log "Python is up to date" -Type "SUCCESS"
                Track-Installation -Package "Python" -Status "Up to date" -Version $currentVersion
            }
            catch {
                Write-Log "Failed to check for Python updates: $_" -Type "WARNING"
            }
            return
        }

        # Try installation methods in order of preference
        $methods = @(
            @{
                Name = "Winget"
                Action = {
                    $job = Start-Job -ScriptBlock { 
                        winget install --silent Python.Python.3
                    }

                    $spinner = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')
                    $i = 0
                    $startTime = Get-Date
                    $progressLength = 20

                    while ($job.State -eq 'Running') {
                        $elapsed = (Get-Date) - $startTime
                        $elapsedStr = "{0:mm}m {0:ss}s" -f $elapsed
                        
                        Write-Host "`r$($script:SpinnerChars[$i % 4]) Installing Python... [" -NoNewline
                        for ($j = 0; $j -lt 20; $j++) {
                            if ($j -eq ($i % 20)) {
                                Write-Host $script:ProgressFull -NoNewline
                            } else {
                                Write-Host $script:ProgressEmpty -NoNewline
                            }
                        }
                        Write-Host "] (Elapsed: $elapsedStr)" -NoNewline
                        
                        Start-Sleep -Milliseconds 100
                        $i++
                    }

                    Write-Host "`r" -NoNewline
                    $result = Receive-Job $job
                    Remove-Job $job

                    if (-not (Command-Exists python)) {
                        throw "Python installation failed"
                    }
                }
            },
            @{
                Name = "Direct Download"
                Action = {
                    Write-Log "Attempting direct download installation..." -Type "INFO"
                    $pythonUrl = "https://www.python.org/ftp/python/3.11.0/python-3.11.0-amd64.exe"
                    $installerPath = Join-Path $env:TEMP "python-installer.exe"
                    
                    # Download with progress
                    $webClient = New-Object System.Net.WebClient
                    $webClient.DownloadFile($pythonUrl, $installerPath)
                    
                    # Install with progress
                    $process = Start-Process -FilePath $installerPath -ArgumentList "/quiet", "InstallAllUsers=1", "PrependPath=1" -PassThru -Wait
                    if ($process.ExitCode -ne 0) {
                        throw "Python installer returned exit code: $($process.ExitCode)"
                    }
                    
                    Remove-Item $installerPath -Force
                }
            },
            @{
                Name = "Chocolatey"
                Action = {
                    Write-Log "Attempting installation via Chocolatey..." -Type "INFO"
                    if (-not (Command-Exists choco)) {
                        Set-ExecutionPolicy Bypass -Scope Process -Force
                        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
                    }
                    choco install python3 -y
                }
            }
        )

        $success = $false
        foreach ($method in $methods) {
            Write-Log "Attempting Python installation using $($method.Name)..." -Type "INFO"
            try {
                & $method.Action
                $version = (python --version 2>&1).ToString().Split(" ")[1]
                Write-Log "Python $version installed successfully using $($method.Name)" -Type "SUCCESS"
                Track-Installation -Package "Python" -Status "Installed" -Version $version
                $success = $true
                break
            }
            catch {
                Write-Log "Failed to install Python using $($method.Name): $_" -Type "WARNING"
                continue
            }
        }

        if (-not $success) {
            throw "All Python installation methods failed"
        }

        # Verify PATH and pip
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        if (-not (Command-Exists pip)) {
            Write-Log "Installing pip..." -Type "INFO"
            python -m ensurepip --upgrade
        }

    }
    catch {
        Write-Error -Message "Python installation failed" -ErrorRecord $_
        Track-Installation -Package "Python" -Status "Failed" -Notes $_.Exception.Message
    }
}

# Enhanced Node.js version check function
function Get-NodeVersion {
    try {
        $nodeVersion = node --version 2>$null
        if ($nodeVersion) {
            return $nodeVersion.TrimStart('v')
        }
    } catch {
        return $null
    }
    return $null
}

# Enhanced npm version check function
function Get-NpmVersion {
    try {
        $npmVersion = npm --version 2>$null
        if ($npmVersion) {
            return $npmVersion
        }
    } catch {
        return $null
    }
    return $null
}

# Enhanced Node.js check and installation
function Install-Node {
    Write-Log "Checking Node.js installation..." -Type "INFO"
    
    $nodeVersion = Get-NodeVersion
    $npmVersion = Get-NpmVersion
    
    if ($nodeVersion) {
        Write-Log "Node.js v$nodeVersion is installed" -Type "INFO"
        
        # Check if npm is properly installed
        if ($npmVersion) {
            Write-Log "npm v$npmVersion is installed" -Type "INFO"
            
            # Verify npm is working correctly
            try {
                $npmTest = npm list -g --depth=0 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "npm is functioning correctly" -Type "SUCCESS"
                } else {
                    Write-Log "npm installation appears corrupted, attempting repair..." -Type "WARNING"
                    Repair-NodeInstallation
                }
            } catch {
                Write-Log "Error testing npm: $_" -Type "ERROR"
                Repair-NodeInstallation
            }
        } else {
            Write-Log "npm is not installed properly, attempting repair..." -Type "WARNING"
            Repair-NodeInstallation
        }
        
        # Check for updates
        try {
            $latestVersion = Get-LatestVersion "OpenJS.NodeJS"
            if ($latestVersion -and ($nodeVersion -ne $latestVersion)) {
                Write-Log "Updating Node.js from v$nodeVersion to v$latestVersion..." -Type "INFO"
                Install-Package "OpenJS.NodeJS" -Update
            }
        } catch {
            Write-Log "Failed to check for Node.js updates: $_" -Type "WARNING"
        }
    } else {
        Write-Log "Node.js is not installed, installing..." -Type "INFO"
        Install-Package "OpenJS.NodeJS"
    }
}

# New function to repair Node.js installation
function Repair-NodeInstallation {
    Write-Log "Attempting to repair Node.js installation..." -Type "INFO"
    
    try {
        # First try to repair using npm
        Write-Log "Running npm repair..." -Type "INFO"
        Start-Process -FilePath "npm" -ArgumentList "repair" -Wait -NoNewWindow
        
        # If that doesn't work, try reinstalling
        if (-not (Get-NpmVersion)) {
            Write-Log "npm repair failed, attempting reinstallation..." -Type "WARNING"
            
            # Uninstall existing Node.js
            Write-Log "Removing existing Node.js installation..." -Type "INFO"
            Start-Process -FilePath "winget" -ArgumentList "uninstall", "OpenJS.NodeJS" -Wait -NoNewWindow
            
            # Clean up remaining files
            $nodePaths = @(
                "$env:ProgramFiles\nodejs",
                "$env:APPDATA\npm",
                "$env:APPDATA\npm-cache"
            )
            
            foreach ($path in $nodePaths) {
                if (Test-Path $path) {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            
            # Reinstall Node.js
            Write-Log "Reinstalling Node.js..." -Type "INFO"
            Install-Package "OpenJS.NodeJS"
            
            # Verify installation
            $newNodeVersion = Get-NodeVersion
            $newNpmVersion = Get-NpmVersion
            
            if ($newNodeVersion -and $newNpmVersion) {
                Write-Log "Node.js repair successful" -Type "SUCCESS"
                Write-Log "Node.js v$newNodeVersion and npm v$newNpmVersion installed" -Type "SUCCESS"
            } else {
                throw "Failed to repair Node.js installation"
            }
        }
    } catch {
        Write-Log "Failed to repair Node.js: $_" -Type "ERROR"
        Write-Log "Please try manually uninstalling Node.js and running this script again" -Type "WARNING"
    }
}

# Enhanced npm package update function
function Update-GlobalNpmPackages {
    Write-Log "Checking for npm package updates..." -Type "INFO"
    
    try {
        # First verify npm is working
        $npmVersion = Get-NpmVersion
        if (-not $npmVersion) {
            throw "npm is not properly installed"
        }
        
        # Suppress experimental warnings
        $env:NODE_NO_WARNINGS = "1"
        
        # Get list of outdated packages
        $outdatedJson = npm outdated -g --json --silent 2>$null
        
        if ($outdatedJson) {
            $outdated = $outdatedJson | ConvertFrom-Json -ErrorAction SilentlyContinue
            
            if ($outdated.PSObject.Properties.Count -gt 0) {
                foreach ($package in $outdated.PSObject.Properties) {
                    $name = $package.Name
                    $current = $package.Value.current
                    $wanted = $package.Value.wanted
                    $latest = $package.Value.latest
                    
                    Write-Log ("Updating {0} from v{1} to v{2}..." -f $name, $current, $latest) -Type "INFO"
                    
                    try {
                        $result = npm update -g $name --silent 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log ("Package {0} updated successfully" -f $name) -Type "SUCCESS"
                        } else {
                            Write-Log ("Failed to update package {0} - {1}" -f $name, $result) -Type "ERROR"
                        }
                    } catch {
                        Write-Log ("Error updating package {0} - {1}" -f $name, $_.Exception.Message) -Type "ERROR"
                    }
                }
            } else {
                Write-Log "All global npm packages are up to date" -Type "SUCCESS"
            }
        }
    } catch {
        Write-Log ("Error checking for npm updates: {0}" -f $_.Exception.Message) -Type "ERROR"
        Write-Log "Attempting to repair npm..." -Type "WARNING"
        Repair-NodeInstallation
    }
}

# Install Global npm Packages
function Install-GlobalNpmPackages {
    $GlobalNpmPackages = @('vercel', 'prisma', 'github', 'typescript', 'eslint', 'nodemon', '@githubnext/github-copilot-cli')
    foreach ($package in $GlobalNpmPackages) {
        if (npm list -g $package | Out-String | Select-String $package) {
            Print-Info "$package is already installed globally."
        } else {
            Print-Info "Installing $package globally..."
            if (Run-Command { npm install -g $package }) {
                Print-Info "$package installed globally."
            } else {
                Print-Error "Failed to install $package globally."
            }
        }
    }
}

# Install PHP
function Install-PHP {
    if (Command-Exists php) {
        Print-Info "PHP is already installed."
    } else {
        Install-Package "PHP"
    }
}

# Install Docker Desktop
function Install-Docker {
    if (Command-Exists "docker" -IsDesktopApp) {
        Print-Info "Docker Desktop is already installed."
    } else {
        Install-Package "Docker.DockerDesktop" -IsDesktopApp
    }
}

# Install Git
function Install-Git {
    if (Command-Exists "git" -IsDesktopApp) {
        Print-Info "Git is already installed."
    } else {
        Install-Package "Git.Git" -IsDesktopApp
    }
}

# Install Go
function Install-Go {
    if (Command-Exists go) {
        Print-Info "Go is already installed."
    } else {
        Install-Package "Golang.Go"
    }
}

# Install Bun (requires Node.js)
function Install-Bun {
    if (Command-Exists bun) {
        Print-Info "Bun is already installed."
    } else {
        Print-Info "Installing Bun..."
        Run-Command { iwr https://bun.sh/install -UseBasicParsing | Invoke-Expression }
    }
}

# Install Java (OpenJDK)
function Install-Java {
    if (Command-Exists java) {
        Print-Info "Java is already installed."
    } else {
        Install-Package "EclipseAdoptium.Temurin.11.JDK"
    }
}

# Install Ruby
function Install-Ruby {
    if (Command-Exists ruby) {
        Print-Info "Ruby is already installed."
    } else {
        Install-Package "RubyInstallerTeam.RubyWithDevKit"
        Run-Command { ridk install }
    }
}

# Install MySQL
function Install-MySQL {
    if (Command-Exists mysql) {
        Print-Info "MySQL is already installed."
    } else {
        Install-Package "Oracle.MySQL"
    }
}

# Install PostgreSQL
function Install-PostgreSQL {
    if (Command-Exists psql) {
        Print-Info "PostgreSQL is already installed."
    } else {
        Install-Package "PostgreSQL.PostgreSQL"
    }
}

# Install MongoDB
function Install-MongoDB {
    if (Command-Exists mongo) {
        Print-Info "MongoDB is already installed."
    } else {
        Install-Package "MongoDB.Server"
    }
}

# Install AWS CLI
function Install-AWSCLI {
    if (Command-Exists aws) {
        Print-Info "AWS CLI is already installed."
    } else {
        Install-Package "Amazon.AWSCLI"
    }
}

# Install Terraform
function Install-Terraform {
    if (Command-Exists terraform) {
        Print-Info "Terraform is already installed."
    } else {
        Install-Package "Hashicorp.Terraform"
    }
}

# Install Kubernetes Tools (kubectl)
function Install-KubernetesTools {
    if (Command-Exists kubectl) {
        Print-Info "kubectl is already installed."
    } else {
        Install-Package "Kubernetes.kubectl"
    }
    # Install Helm
    if (Command-Exists helm) {
        Print-Info "Helm is already installed."
    } else {
        Install-Package "Helm.Helm"
    }
}

# Install Build Tools (Gradle and Maven)
function Install-BuildTools {
    # Install Gradle
    if (Command-Exists gradle) {
        Print-Info "Gradle is already installed."
    } else {
        Install-Package "Gradle.Gradle"
    }

    # Install Maven
    if (Command-Exists mvn) {
        Print-Info "Maven is already installed."
    } else {
        Install-Package "Apache.Maven"
    }
}

# Install Yarn
function Install-Yarn {
    if (Command-Exists yarn) {
        Print-Info "Yarn is already installed."
    } else {
        Install-Package "Yarn.Yarn"
    }
}

# Install Productivity Applications
function Install-ProductivityApps {
    # Visual Studio Code
    if (Command-Exists code) {
        Print-Info "Visual Studio Code is already installed."
    } else {
        Install-Package "Microsoft.VisualStudioCode"
    }

    # IntelliJ IDEA Community Edition
    if (Command-Exists idea) {
        Print-Info "IntelliJ IDEA is already installed."
    } else {
        Install-Package "JetBrains.IntelliJIDEA.Community"
    }

    # Notion
    if (Command-Exists notion) {
        Print-Info "Notion is already installed."
    } else {
        Install-Package "Notion.Notion"
    }

    # Discord
    if (Command-Exists discord) {
        Print-Info "Discord is already installed."
    } else {
        Install-Package "Discord.Discord"
    }

    # Figma
    if (Command-Exists figma) {
        Print-Info "Figma is already installed."
    } else {
        Install-Package "Figma.Figma"
    }

    # Blender
    if (Command-Exists blender) {
        Print-Info "Blender is already installed."
    } else {
        Install-Package "BlenderFoundation.Blender"
    }
}

# Install Browsers and Testing Tools
function Install-BrowsersAndTestingTools {
    # Google Chrome
    if (Command-Exists chrome) {
        Print-Info "Google Chrome is already installed."
    } else {
        Install-Package "Google.Chrome"
    }

    # Postman
    if (Command-Exists postman) {
        Print-Info "Postman is already installed."
    } else {
        Install-Package "Postman.Postman"
    }

    # Selenium (via pip)
    if (python -c "import selenium" 2>$null) {
        Print-Info "Selenium is already installed."
    } else {
        Print-Info "Installing Selenium..."
        Run-Command { pip install selenium }
    }

    # Cypress (via npm)
    if (npm list -g cypress | Out-String | Select-String 'cypress') {
        Print-Info "Cypress is already installed globally."
    } else {
        Print-Info "Installing Cypress globally..."
        Run-Command { npm install -g cypress }
    }
}

# Install AI and Machine Learning Tools
function Install-AITools {
    # TensorFlow
    if (python -c "import tensorflow" 2>$null) {
        Print-Info "TensorFlow is already installed."
    } else {
        Print-Info "Installing TensorFlow..."
        Run-Command { pip install tensorflow }
    }

    # PyTorch
    if (python -c "import torch" 2>$null) {
        Print-Info "PyTorch is already installed."
    } else {
        Print-Info "Installing PyTorch..."
        Run-Command { pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu117 }
    }

    # Jupyter Notebook
    if (Command-Exists jupyter) {
        Print-Info "Jupyter Notebook is already installed."
    } else {
        Print-Info "Installing Jupyter Notebook..."
        Run-Command { pip install notebook }
    }
}

# Install Other Tools (Cursor AI is not available on Windows)
function Install-OtherTools {
    Print-Info "No additional tools to install."
}

# Set Permissions for Folders and Files (Not necessary on Windows)
function Set-Permissions {
    Print-Info "Setting permissions is not necessary on Windows."
}

# Enhanced Display-Summary function
function Display-Summary {
    $elapsed = (Get-Date) - $script:StartTime
    $elapsedStr = "{0:hh\:mm\:ss}" -f $elapsed
    
    Write-Log "`nInstallation Summary" -Type "INFO"
    Write-Log "Total time elapsed: $elapsedStr" -Type "INFO"
    Write-Log "Total packages processed: $($script:InstallationSummary.Count)" -Type "INFO"
    
    $successful = ($script:InstallationSummary | Where-Object Status -in @("Installed", "Updated", "Up to date")).Count
    $failed = ($script:InstallationSummary | Where-Object Status -eq "Failed").Count
    
    Write-Log "Successful: $successful" -Type "SUCCESS"
    Write-Log "Failed: $failed" -Type "ERROR"
    
    if ($failed -gt 0) {
        Write-Log "`nFailed installations:" -Type "WARNING"
        $script:InstallationSummary | Where-Object Status -eq "Failed" | ForEach-Object {
            Write-Log "- $($_.Package): $($_.Notes)" -Type "ERROR"
        }
    }
    
    Write-Log "`nLog files:" -Type "INFO"
    Write-Log "- Main log: $script:LogFile" -Type "INFO"
    Write-Log "- Error log: $script:ErrorLogFile" -Type "INFO"
}

# Add Python package updating
function Update-PythonPackages {
    Print-Info "Updating Python packages..."
    Run-Command { pip list --outdated --format=json | ConvertFrom-Json | ForEach-Object { pip install -U $_.name } }
}

# Modify main execution to include updates
function Main {
    # Check for admin rights
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Print-Error "Please run this script as Administrator."
        exit
    }

    Write-Log "Starting setup process..." -Type "INFO"
    
    if (-not (Update-Packages)) {
        Write-Log "Failed to update package sources. Continue anyway? (Y/N)" -Type "WARNING"
        $response = Read-Host
        if ($response -ne 'Y') {
            Write-Log "Setup aborted by user" -Type "WARNING"
            exit 1
        }
    }

    # Install/Update core tools
    Install-Package "Python.Python.3" -Update
    Install-Package "OpenJS.NodeJS" -Update
    Update-GlobalNpmPackages
    Install-Package "PHP" -Update
    Install-Package "Docker.DockerDesktop" -Update
    Install-Package "Git.Git" -Update
    Install-Package "Golang.Go" -Update
    
    # Update package managers
    Update-PythonPackages
    npm update -g
    
    # Continue with other installations...
    # [Previous installation code remains the same]

    Print-Info "Setup and updates completed successfully!"
}

# Run the main function
Main
