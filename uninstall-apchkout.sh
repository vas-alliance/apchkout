#!/bin/bash
#
#
# This script removes git-apchkout from the system

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

INSTALL_PATH="/usr/local/bin/apchkout"

if [ ! -f "$INSTALL_PATH" ]; then
    print_warning "apchkout is not installed at $INSTALL_PATH"
    exit 0
fi

print_info "Uninstalling apchkout from $INSTALL_PATH"

if [ ! -w "$INSTALL_PATH" ]; then
    print_warning "Need sudo permissions to remove from /usr/local/bin"
    sudo rm "$INSTALL_PATH"
else
    rm "$INSTALL_PATH"
fi

print_info "apchkout uninstalled successfully!"

if git config --global --get alias.apchkout >/dev/null 2>&1; then
    echo ""
    print_warning "Git alias 'git apchkout' still exists"
    read -p "Remove git alias? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git config --global --unset alias.apchkout
        print_info "Git alias removed"
    else
        print_info "Git alias kept. To remove manually, run:"
        echo "  git config --global --unset alias.apchkout"
    fi
fi

echo ""
print_info "Uninstallation complete!"
