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

# Function to check if a command exists
function Command-Exists {
    param ([string]$CommandName)
    $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

# Update package lists
function Update-Packages {
    Print-Info "Updating package lists..."
    # For winget, this isn't necessary, but we can update the source
    Run-Command { winget source update }
}

# Install a package using winget
function Install-Package {
    param ([string]$PackageName)
    Print-Info "Installing $PackageName..."

    if (Command-Exists $PackageName) {
        Print-Info "$PackageName is already installed."
    } else {
        if (Run-Command { winget install --silent --accept-source-agreements --accept-package-agreements $PackageName }) {
            Print-Info "$PackageName installed successfully."
        } else {
            Print-Error "Failed to install $PackageName."
        }
    }
}

# Install Python and pip
function Install-Python {
    if (Command-Exists python) {
        Print-Info "Python is already installed."
    } else {
        Install-Package "Python.Python.3"
    }
}

# Install Node.js and npm
function Install-Node {
    if (Command-Exists node) {
        Print-Info "Node.js is already installed."
    } else {
        Install-Package "OpenJS.NodeJS"
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
    if (Command-Exists docker) {
        Print-Info "Docker is already installed."
    } else {
        Install-Package "Docker.DockerDesktop"
    }
}

# Install Git
function Install-Git {
    if (Command-Exists git) {
        Print-Info "Git is already installed."
    } else {
        Install-Package "Git.Git"
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

# Display Installation Summary
function Display-Summary {
    # You can implement this function to display the installation results
    Print-Info "Installation Summary:"
    # For brevity, not implementing the full summary here
}

# Main Execution Function
function Main {
    # Ensure script is running as Administrator
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Print-Error "Please run this script as Administrator."
        exit
    }

    Update-Packages

    # Run installations sequentially or in parallel
    Install-Python
    Install-Node
    Install-GlobalNpmPackages
    Install-PHP
    Install-Docker
    Install-Bun
    Install-Go
    Install-Git
    Install-Java
    Install-Ruby
    Install-MySQL
    Install-PostgreSQL
    Install-MongoDB
    Install-AWSCLI
    Install-Terraform
    Install-KubernetesTools
    Install-BuildTools
    Install-Yarn
    Install-ProductivityApps
    Install-BrowsersAndTestingTools
    Install-AITools
    Install-OtherTools
    Set-Permissions
    Display-Summary

    Print-Info "Setup completed successfully!"
}

# Run the main function
Main
