#!/bin/bash

# Color Codes for Output Formatting
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Spinner function to indicate progress
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'

    while [ "$(ps a | awk '{print $1}' | grep "$pid")" ]; do
        printf " [%c]  " "$spinstr"
        spinstr=${spinstr#?}${spinstr%???}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Function to print messages with colors
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Function to run a command silently with a spinner
run_command() {
    local cmd="$1"
    eval "$cmd" &>/dev/null &
    spinner
    wait $!
    local exit_code=$?
    return $exit_code
}

# Update package lists based on OS
update_packages() {
    print_info "Updating package lists..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        run_command "sudo apt update -y"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        run_command "brew update"
    else
        print_warning "Unsupported OS type: $OSTYPE"
    fi
}

# Install a package using Homebrew
install_package() {
    local package_name=$1
    print_info "Installing $package_name..."
    
    if brew install "$package_name"; then
        print_info "$package_name installed successfully."
    else
        print_error "Failed to install $package_name using Homebrew."
        print_warning "Please try installing $package_name manually."
    fi
}

# Install a cask package using brew (macOS)
install_cask_package() {
    local package_name=$1
    print_info "Installing $package_name..."
    if brew install --cask "$package_name" &>/dev/null; then
        print_info "$package_name installed successfully."
    else
        print_error "Failed to install $package_name using Homebrew Cask."
        print_warning "Please try installing $package_name manually or using an alternative method."
    fi
}

# Function definitions for installations (modified to use run_command)

# Install Python and pip
install_python() {
    if command_exists python3; then
        print_info "Python is already installed."
    else
        install_package python3
        install_package python3-pip
    fi
}

# Install Node.js and npm
install_node() {
    if command_exists node; then
        print_info "Node.js is already installed."
    else
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            print_info "Installing Node.js..."
            run_command "curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -"
            install_package nodejs
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            install_package node
        fi
    fi
}

# Install Global npm Packages
install_global_npm_packages() {
    GLOBAL_NPM_PACKAGES=(vercel prisma github)
    for package in "${GLOBAL_NPM_PACKAGES[@]}"; do
        if npm list -g "$package" &>/dev/null; then
            print_info "$package is already installed globally."
        else
            print_info "Installing $package globally..."
            if run_command "npm install -g $package"; then
                print_info "$package installed globally."
            else
                print_error "Failed to install $package globally."
            fi
        fi
    done
}

# Install PHP
install_php() {
    if command_exists php; then
        print_info "PHP is already installed."
    else
        install_package php
    fi
}

# Install Docker
install_docker() {
    if command_exists docker; then
        print_info "Docker is already installed."
    else
        print_info "Installing Docker..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            run_command "sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release"
            run_command "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
            run_command "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
                https://download.docker.com/linux/ubuntu \
                $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
            run_command "sudo apt update -y"
            run_command "sudo apt install -y docker-ce docker-ce-cli containerd.io"
            run_command "sudo usermod -aG docker ${USER}"
            print_info "Docker installed successfully."
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            install_cask_package docker
        fi
    fi
}

# Install Docker Compose
install_docker_compose() {
    if command_exists docker-compose; then
        print_info "Docker Compose is already installed."
    else
        print_info "Installing Docker Compose..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            latest_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
            run_command "sudo curl -L \"https://github.com/docker/compose/releases/download/$latest_version/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose"
            run_command "sudo chmod +x /usr/local/bin/docker-compose"
            print_info "Docker Compose installed successfully."
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            install_package docker-compose
        fi
    fi
}

# Install Bun
install_bun() {
    if command_exists bun; then
        print_info "Bun is already installed."
    else
        print_info "Installing Bun..."
        run_command "curl -fsSL https://bun.sh/install | bash"
        print_info "Bun installed successfully."
    fi
}

# Install Go
install_go() {
    if command_exists go; then
        print_info "Go is already installed."
    else
        print_info "Installing Go..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            run_command "wget https://go.dev/dl/go1.21.1.linux-amd64.tar.gz"
            run_command "sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.21.1.linux-amd64.tar.gz"
            run_command "rm go1.21.1.linux-amd64.tar.gz"
            echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.profile
            source ~/.profile
            print_info "Go installed successfully."
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            install_package go
        fi
    fi
}

# Install Git
install_git() {
    if command_exists git; then
        print_info "Git is already installed."
    else
        install_package git
    fi
}

# Install Java (JDK)
install_java() {
    if command_exists java; then
        print_info "Java is already installed."
    else
        install_package openjdk-11-jdk
    fi
}

# Install Ruby and Rails
install_ruby() {
    if command_exists ruby; then
        print_info "Ruby is already installed."
    else
        install_package ruby-full
        run_command "gem install rails"
        print_info "Ruby and Rails installed successfully."
    fi
}

# Install MySQL
install_mysql() {
    if command_exists mysql; then
        print_info "MySQL is already installed."
    else
        install_package mysql-server
    fi
}

# Install PostgreSQL
install_postgresql() {
    if command_exists psql; then
        print_info "PostgreSQL is already installed."
    else
        install_package "postgresql postgresql-contrib"
    fi
}

# Install MongoDB
install_mongodb() {
    if command_exists mongo; then
        print_info "MongoDB is already installed."
    else
        print_info "Installing MongoDB..."
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if run_command "brew tap mongodb/brew" && run_command "brew install mongodb-community@5.0"; then
                print_info "MongoDB installed successfully."
            else
                print_error "Failed to install MongoDB using Homebrew."
                print_warning "Please try installing MongoDB manually."
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if run_command "sudo apt install -y mongodb"; then
                print_info "MongoDB installed successfully."
            else
                print_error "Failed to install MongoDB using apt."
                print_warning "Please try installing MongoDB manually."
            fi
        else
            print_error "Unsupported operating system for installing MongoDB."
        fi
    fi
}

# Install AWS CLI
install_aws_cli() {
    if command_exists aws; then
        print_info "AWS CLI is already installed."
        update_package awscli
    else
        print_info "Installing AWS CLI..."
        if ! install_package awscli; then
            print_warning "Please install AWS CLI manually by following the instructions at:"
            print_warning "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        fi
    fi
}

# Install Terraform
install_terraform() {
    if command_exists terraform; then
        print_info "Terraform is already installed."
        update_package terraform
    else
        print_info "Installing Terraform..."
        if ! install_package terraform; then
            print_warning "Please install Terraform manually by following the instructions at:"
            print_warning "https://learn.hashicorp.com/tutorials/terraform/install-cli"
        fi
    fi
}

# Install Kubernetes Tools (kubectl and Helm)
install_kubernetes_tools() {
    # Install kubectl
    if command_exists kubectl; then
        print_info "kubectl is already installed."
    else
        print_info "Installing kubectl..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            latest_version=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
            run_command "curl -LO \"https://storage.googleapis.com/kubernetes-release/release/$latest_version/bin/linux/amd64/kubectl\""
            run_command "chmod +x ./kubectl"
            run_command "sudo mv ./kubectl /usr/local/bin/kubectl"
            print_info "kubectl installed successfully."
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            install_package kubectl
        fi
    fi

    # Install Helm
    if command_exists helm; then
        print_info "Helm is already installed."
    else
        print_info "Installing Helm..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            run_command "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
            print_info "Helm installed successfully."
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            install_package helm
        fi
    fi
}

# Install Build Tools (Gradle and Maven)
install_build_tools() {
    # Install Gradle
    if command_exists gradle; then
        print_info "Gradle is already installed."
    else
        install_package gradle
    fi

    # Install Maven
    if command_exists mvn; then
        print_info "Maven is already installed."
    else
        install_package maven
    fi
}

# Install Yarn
install_yarn() {
    if command_exists yarn; then
        print_info "Yarn is already installed."
    else
        print_info "Installing Yarn..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            run_command "curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -"
            run_command "echo \"deb https://dl.yarnpkg.com/debian/ stable main\" | sudo tee /etc/apt/sources.list.d/yarn.list"
            run_command "sudo apt update -y"
            run_command "sudo apt install -y yarn"
            print_info "Yarn installed successfully."
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            install_package yarn
        fi
    fi
}

# Install Zsh and Oh My Zsh
install_zsh() {
    if command_exists zsh; then
        print_info "Zsh is already installed."
    else
        install_package zsh
        run_command "chsh -s $(which zsh)"
    fi

    if [ -d "$HOME/.oh-my-zsh" ]; then
        print_info "Oh My Zsh is already installed."
    else
        print_info "Installing Oh My Zsh..."
        run_command "RUNZSH=no CHSH=no sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sed '/\\s*env\\s\\s*zsh\\s*/d')\""
        print_info "Oh My Zsh installed successfully."
    fi
}

# Install Productivity and Utility Applications
install_productivity_apps() {
    print_info "Installing productivity apps..."
    
    # Cursor AI
    if command_exists cursor; then
        print_info "Cursor AI is already installed."
    else
        install_cask_package cursor
    fi
    
    # Visual Studio Code
    if command_exists code; then
        print_info "Visual Studio Code is already installed."
    else
        install_cask_package visual-studio-code
    fi
    
    # Blender
    if command_exists blender; then
        print_info "Blender is already installed."
    else
        install_cask_package blender
    fi
}

# Install Design and Collaboration Tools
install_design_tools() {

    # Slack
    if command_exists slack; then
        print_info "Slack is already installed."
    else
        print_info "Installing Slack..."
        
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if run_command "sudo snap install slack --classic"; then
                print_info "Slack installed successfully."
            else
                print_error "Failed to install Slack using snap."
                print_warning "Please try installing Slack manually."
            fi
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            if run_command "brew install --cask slack"; then
                print_info "Slack installed successfully."
            else
                print_error "Failed to install Slack using Homebrew."
                print_warning "Please try installing Slack manually."
            fi
        else
            print_error "Unsupported operating system for installing Slack."
        fi
    fi
}

# Install Browsers and Testing Tools
install_browsers_and_testing_tools() {
    # Selenium (via pip)
    if python3 -c "import selenium" &>/dev/null; then
        print_info "Selenium is already installed."
    else
        print_info "Installing Selenium..."
        run_command "pip3 install selenium"
    fi

    # Cypress (via npm)
    if npm list -g cypress &>/dev/null; then
        print_info "Cypress is already installed globally."
    else
        print_info "Installing Cypress globally..."
        run_command "npm install -g cypress"
    fi
}

# Install AI and Machine Learning Tools
install_ai_tools() {
    # TensorFlow
    if python3 -c "import tensorflow" &>/dev/null; then
        print_info "TensorFlow is already installed."
    else
        print_info "Installing TensorFlow..."
        run_command "pip3 install tensorflow"
    fi

    # PyTorch
    if python3 -c "import torch" &>/dev/null; then
        print_info "PyTorch is already installed."
    else
        print_info "Installing PyTorch..."
        run_command "pip3 install torch torchvision torchaudio"
    fi

    # Jupyter Notebook
    if command_exists jupyter; then
        print_info "Jupyter Notebook is already installed."
    else
        print_info "Installing Jupyter Notebook..."
        run_command "pip3 install notebook"
    fi
}

# Install Others
install_other_tools() {
    # Blender
    if command_exists blender; then
        print_info "Blender is already installed."
    else
        print_info "Installing Blender..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            run_command "sudo snap install blender --classic"
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            install_cask_package blender
        fi
    fi

    # Cursor (assuming installation method is available)
    print_info "Skipping Cursor AI installation (installation method not specified)."
}

# Install Homebrew (macOS)
install_homebrew() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command_exists brew; then
            print_info "Homebrew is already installed."
        else
            print_info "Installing Homebrew..."
            run_command "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        fi
    fi
}

# Set Permissions for Folders and Files
set_permissions() {
    print_info "Setting permissions for folders and files..."
    run_command "sudo chmod -R ugo+rw /usr/local/bin"
    run_command "sudo chmod -R ugo+rw /usr/local/lib"
}

# Install AI models
install_ai_models() {
    # Ollama
    if python3 -c "import ollama" &>/dev/null; then
        print_info "Ollama is already installed."
    else
        print_info "Installing Ollama..."
        run_command "pip3 install ollama"
        print_info "Pulling Llama 3.1 model..."
        ollama pull llama3.1
    fi

    # Llama 2
    if python3 -c "import llama2" &>/dev/null; then
        print_info "Llama 2 is already installed." 
    else
        print_info "Installing Llama 2..."
        run_command "pip3 install llama2"
    fi

    # Llama 3
    if python3 -c "import llama3" &>/dev/null; then
        print_info "Llama 3 is already installed."
    else 
        print_info "Installing Llama 3..."
        run_command "pip3 install llama3"
    fi

    # Llama 3.1
    if python3 -c "import llama3p1" &>/dev/null; then
        print_info "Llama 3.1 is already installed."
    else
        print_info "Installing Llama 3.1..."
        if ollama pull llama3.1; then
            print_info "Llama 3.1 installed successfully."
        else
            print_error "Failed to install Llama 3.1 using ollama."
            print_warning "Please try installing Llama 3.1 manually."
        fi
    fi
}

display_summary() {
    print_info "Installation Summary:"
    
    print_info "- Homebrew:"
    if command_exists brew; then
        print_info "  - Homebrew is installed."
    else
        print_warning "  - Homebrew installation failed."
    fi
    
    print_info "- Python:"
    if command_exists python3; then
        local python_version=$(python3 --version | awk '{print $2}')
        print_info "  - Python $python_version is installed."
    else
        print_warning "  - Python installation failed."
    fi
    
    print_info "- Node.js:"
    if command_exists node; then
        local node_version=$(node --version)
        print_info "  - Node.js $node_version is installed."
    else
        print_warning "  - Node.js installation failed."
    fi
    
    print_info "- Global npm packages:"
    if command_exists npm; then
        print_info "  - Global npm packages are installed."
    else
        print_warning "  - Global npm package installation failed."
    fi
    
    print_info "- PHP:"
    if command_exists php; then
        local php_version=$(php --version | awk 'NR==1{print $2}')
        print_info "  - PHP $php_version is installed."
    else
        print_warning "  - PHP installation failed."
    fi
    
    print_info "- Docker:"
    if command_exists docker; then
        local docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
        print_info "  - Docker $docker_version is installed."
    else
        print_warning "  - Docker installation failed."
    fi
    
    print_info "- Docker Compose:"
    if command_exists docker-compose; then
        local docker_compose_version=$(docker-compose --version | awk '{print $4}' | tr -d ',')
        print_info "  - Docker Compose $docker_compose_version is installed."
    else
        print_warning "  - Docker Compose installation failed."
    fi
    
    print_info "- Bun:"
    if command_exists bun; then
        local bun_version=$(bun --version)
        print_info "  - Bun $bun_version is installed."
    else
        print_warning "  - Bun installation failed."
    fi
    
    print_info "- Go:"
    if command_exists go; then
        local go_version=$(go version | awk '{print $3}')
        print_info "  - Go $go_version is installed."
    else
        print_warning "  - Go installation failed."
    fi
    
    print_info "- Git:"
    if command_exists git; then
        local git_version=$(git --version | awk '{print $3}')
        print_info "  - Git $git_version is installed."
    else
        print_warning "  - Git installation failed."
    fi
    
    print_info "- Java:"
    if command_exists java; then
        local java_version=$(java -version 2>&1 | awk 'NR==1{print $3}' | tr -d '"')
        print_info "  - Java $java_version is installed."
    else
        print_warning "  - Java installation failed."
    fi
    
    print_info "- Ruby:"
    if command_exists ruby; then
        local ruby_version=$(ruby --version | awk '{print $2}')
        print_info "  - Ruby $ruby_version is installed."
    else
        print_warning "  - Ruby installation failed."
    fi
    
    print_info "- MySQL:"
    if command_exists mysql; then
        local mysql_version=$(mysql --version | awk '{print $5}' | tr -d ',')
        print_info "  - MySQL $mysql_version is installed."
    else
        print_warning "  - MySQL installation failed."
    fi
    
    print_info "- PostgreSQL:"
    if command_exists psql; then
        local psql_version=$(psql --version | awk '{print $3}')
        print_info "  - PostgreSQL $psql_version is installed."
    else
        print_warning "  - PostgreSQL installation failed."
    fi
    
    print_info "- MongoDB:"
    if command_exists mongo; then
        local mongo_version=$(mongo --version | awk 'NR==1{print $4}')
        print_info "  - MongoDB $mongo_version is installed."
    else
        print_warning "  - MongoDB installation failed."
    fi
    
    print_info "- AWS CLI:"
    if command_exists aws; then
        local aws_version=$(aws --version 2>&1 | awk 'NR==1{print $1}')
        print_info "  - AWS CLI $aws_version is installed."
    else
        print_warning "  - AWS CLI installation failed."
    fi
    
    print_info "- Terraform:"
    if command_exists terraform; then
        local terraform_version=$(terraform --version | awk '{print $2}')
        print_info "  - Terraform $terraform_version is installed."
    else
        print_warning "  - Terraform installation failed."
    fi
    
    print_info "- Figma:"
    if command_exists figma; then
        print_info "  - Figma is installed."
    else
        print_warning "  - Figma installation failed."
    fi
    
    print_info "- Discord:"
    if command_exists discord; then
        print_info "  - Discord is installed."
    else
        print_warning "  - Discord installation failed."
    fi
    
    print_info "- Notion:"
    if command_exists notion; then
        print_info "  - Notion is installed."
    else
        print_warning "  - Notion installation failed."
    fi
    
    print_info "- Blender:"
    if command_exists blender; then
        local blender_version=$(blender --version | awk '{print $2}')
        print_info "  - Blender $blender_version is installed."
    else
        print_warning "  - Blender installation failed."
    fi
    
    if [ -n "$installation_errors" ]; then
        print_warning "Errors encountered during installation:"
        echo "$installation_errors"
    fi
}

# Function to check if the script is being run with sudo
check_sudo() {
    if [ "$EUID" -eq 0 ]; then
        print_error "Running this script with sudo is not supported."
        print_warning "Please run the script without sudo."
        exit 1
    fi
}

# Install Figma
install_figma() {
    if command_exists figma; then
        print_info "Figma is already installed."
    else
        print_info "Installing Figma..."
        local download_url="https://desktop.figma.com/mac/Figma.zip"
        local temp_dir=$(mktemp -d)
        local zip_file="$temp_dir/Figma.zip"

        run_command "curl -L -o $zip_file $download_url"
        run_command "unzip -q $zip_file -d $temp_dir"
        run_command "cp -R $temp_dir/Figma.app /Applications/"

        rm -rf "$temp_dir"

        print_info "Figma installed successfully."
    fi
}

# Install Discord
install_discord() {
    if command_exists discord; then
        print_info "Discord is already installed."
    else
        print_info "Installing Discord..."
        local download_url="https://discord.com/api/download?platform=osx"
        local temp_dir=$(mktemp -d)
        local dmg_file="$temp_dir/Discord.dmg"

        run_command "curl -L -o $dmg_file $download_url"
        run_command "hdiutil attach $dmg_file"
        run_command "cp -R /Volumes/Discord/Discord.app /Applications/"
        run_command "hdiutil detach /Volumes/Discord"

        rm -rf "$temp_dir"

        print_info "Discord installed successfully."
    fi
}

# Install Notion
install_notion() {
    if command_exists notion; then
        print_info "Notion is already installed."
    else
        print_info "Installing Notion..."
        local download_url="https://www.notion.so/desktop/mac/download"
        local temp_dir=$(mktemp -d)
        local dmg_file="$temp_dir/Notion.dmg"

        run_command "curl -L -o $dmg_file $download_url"
        run_command "hdiutil attach $dmg_file"
        run_command "cp -R /Volumes/Notion/Notion.app /Applications/"
        run_command "hdiutil detach /Volumes/Notion"

        rm -rf "$temp_dir"

        print_info "Notion installed successfully."
    fi
}

# Install Blender
install_blender() {
    if command_exists blender; then
        print_info "Blender is already installed."
    else
        print_info "Installing Blender..."
        local download_url="https://www.blender.org/download/release/Blender3.5/blender-3.5.0-macos-x64.dmg/"
        local temp_dir=$(mktemp -d)
        local dmg_file="$temp_dir/Blender.dmg"

        run_command "curl -L -o $dmg_file $download_url"
        run_command "hdiutil attach $dmg_file"
        run_command "cp -R /Volumes/Blender/Blender.app /Applications/"
        run_command "hdiutil detach /Volumes/Blender"

        rm -rf "$temp_dir"

        print_info "Blender installed successfully."
    fi
}

# Main Execution Function
main() {
    # Check if the script is being run with sudo
    check_sudo

    install_homebrew
    update_packages
    
    # Run installations in parallel
    install_python &
    install_node &
    install_global_npm_packages &
    install_php &
    install_docker &
    install_docker_compose &
    install_bun &
    install_go &
    install_git &
    install_java &
    install_ruby &
    install_mysql &
    install_postgresql &
    install_mongodb &
    install_aws_cli &
    install_terraform &
    install_kubernetes_tools &
    install_build_tools &
    install_yarn &
    install_zsh &
    install_productivity_apps &
    install_design_tools &
    install_browsers_and_testing_tools &
    install_ai_tools &
    install_other_tools &
    install_ai_models &
    install_figma &
    install_discord &
    install_notion &
    install_blender &
    
    # Wait for all installations to complete
    wait
    
    # Display installation summary
    display_summary
    
    set_permissions
    print_info "Setup completed successfully!"
}

# Run the main function
main