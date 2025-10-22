#!/bin/bash
#
#
# This script installs git-apchkout as a global command

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/git-apchkout.sh"

# Check if source script exists
if [ ! -f "$SOURCE_SCRIPT" ]; then
    print_error "git-apchkout.sh not found at $SOURCE_SCRIPT"
    exit 1
fi

INSTALL_DIR="/usr/local/bin"
INSTALL_PATH="$INSTALL_DIR/apchkout"

print_info "Installing git-apchkout to $INSTALL_PATH"

# Check if we need sudo
if [ ! -w "$INSTALL_DIR" ]; then
    print_warning "Need sudo permissions to install to $INSTALL_DIR"
    sudo cp "$SOURCE_SCRIPT" "$INSTALL_PATH"
    sudo chmod +x "$INSTALL_PATH"
else
    cp "$SOURCE_SCRIPT" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
fi

print_info "git-apchkout installed successfully!"
echo ""

print_info "Setting up git alias..."
git config --global alias.apchkout '!apchkout'
print_info "Git alias created: 'git apchkout'"

echo ""
echo "You can now use it from any Django project:"
echo "  apchkout feature/my-branch --with-db"
echo "  git apchkout feature/my-branch --with-db"
echo "  apchkout --list"
echo "  apchkout --clean"
echo ""
print_info "The script will work from any directory within your Django git repositories"
