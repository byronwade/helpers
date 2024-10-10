#!/bin/bash

# Get the current directory of the setup script
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Variables
SCRIPT_PATH="$CURRENT_DIR/gitdone"
OLLAMA_API_URL="http://localhost:11434"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    echo -e "${1}${2}${NC}"
}

# Ensure the gitdone script exists in the current directory
if [ ! -f "$SCRIPT_PATH" ]; then
    print_color "$RED" "Error: gitdone script not found in the current directory."
    exit 1
fi

# Make the script executable
chmod +x "$SCRIPT_PATH"
print_color "$CYAN" "Made gitdone script executable."

# Detect shell and set profile file
SHELL_NAME=$(basename "$SHELL")
if [ "$SHELL_NAME" = "zsh" ]; then
    PROFILE_FILE="$HOME/.zshrc"
elif [ "$SHELL_NAME" = "bash" ]; then
    PROFILE_FILE="$HOME/.bashrc"
else
    PROFILE_FILE="$HOME/.profile"
fi

# Add alias to shell profile
ALIAS_CONTENT="alias gitdone='$SCRIPT_PATH'"
if ! grep -q "$ALIAS_CONTENT" "$PROFILE_FILE"; then
    echo "$ALIAS_CONTENT" >> "$PROFILE_FILE"
    print_color "$CYAN" "Alias 'gitdone' added to $PROFILE_FILE."
else
    print_color "$CYAN" "Alias 'gitdone' already exists in $PROFILE_FILE."
fi

# Install Python if not installed
if ! command -v python3 &>/dev/null; then
    print_color "$YELLOW" "Python3 not found. Installing Python3..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install python3
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt update
        sudo apt install -y python3 python3-pip
    fi
fi

# Install required Python packages
print_color "$BLUE" "Installing required Python packages..."
pip3 install requests --user

# Set OLLAMA_API_URL environment variable
if ! grep -q "export OLLAMA_API_URL=" "$PROFILE_FILE"; then
    echo "export OLLAMA_API_URL=\"$OLLAMA_API_URL\"" >> "$PROFILE_FILE"
    print_color "$CYAN" "OLLAMA_API_URL environment variable added to $PROFILE_FILE."
else
    print_color "$CYAN" "OLLAMA_API_URL already set in $PROFILE_FILE."
fi

# Ensure Ollama is installed and running
ensure_ollama() {
    if ! command -v ollama &>/dev/null; then
        print_color "$YELLOW" "Ollama not found. Installing Ollama..."
        curl https://ollama.ai/install.sh | sh
    fi

    model_name="codellama:latest"
    if ! ollama list | grep -q "$model_name"; then
        print_color "$BLUE" "Pulling the latest $model_name model..."
        ollama pull $model_name
    else
        print_color "$GREEN" "$model_name model is already available."
    fi

    print_color "$BLUE" "Starting Ollama service..."
    ollama serve &
}

# Run Ollama setup
ensure_ollama

# Final setup message
print_color "$GREEN" "\nSetup completed successfully."
print_color "$YELLOW" "Restart your terminal or run 'source $PROFILE_FILE' to use the 'gitdone' command."

print_color "$MAGENTA" "\nAdditional Information:"
print_color "$WHITE" "- GitDone script location: $SCRIPT_PATH"
print_color "$WHITE" "- Ollama API URL: $OLLAMA_API_URL"
print_color "$WHITE" "- To use GitDone, type 'gitdone' in a new terminal session"