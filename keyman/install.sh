#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check Go installation
if ! command -v go &> /dev/null; then
    echo -e "${RED}Go is not installed${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${BLUE}Installing Go via Homebrew...${NC}"
        if ! command -v brew &> /dev/null; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew install go
    else
        echo -e "${RED}Please install Go manually from https://golang.org/dl/${NC}"
        exit 1
    fi
fi

# Ensure SSH agent is running
if [[ "$OSTYPE" != "darwin"* ]]; then
    eval "$(ssh-agent -s)" || {
        echo -e "${RED}Failed to start SSH agent${NC}"
        exit 1
    }
fi

# Build and install Keyman
echo -e "${BLUE}Building and installing Keyman...${NC}"
if ! go run cmd/install/main.go; then
    echo -e "${RED}Build failed${NC}"
    exit 1
fi

# Update PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi

echo -e "${GREEN}Installation complete!${NC}"
echo "You may need to restart your terminal or run: source ~/.profile" 