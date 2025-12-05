#!/usr/bin/env bash

# Snapd Recovery Script for Arch Linux
# This script fixes common snapd seeding and initialization issues

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if running on Arch Linux
check_arch() {
    if [[ ! -f /etc/os-release ]] || ! grep -q "ID=arch" /etc/os-release; then
        log_error "This script is designed for Arch Linux only"
        exit 1
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi
}

# Show banner
show_banner() {
    echo -e "\n${BLUE}╔════════════════════════════════════════╗"
    echo -e "║       Snapd Recovery for Arch Linux   ║"
    echo -e "╚════════════════════════════════════════╝${NC}\n"
}

# Check AppArmor status
check_apparmor_status() {
    if [[ -f /sys/module/apparmor/parameters/enabled ]]; then
        local enabled=$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)
        [[ "$enabled" == "Y" ]]
    else
        return 1
    fi
}

# User confirmation function
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        if [[ "$default" == "y" || "$default" == "yes" ]]; then
            read -rp "$prompt [Y/n]: " response
            response=${response:-y}
        else
            read -rp "$prompt [y/N]: " response
            response=${response:-n}
        fi
        
        case $response in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Setup AppArmor
setup_apparmor() {
    log_info "Setting up AppArmor for better snap security..."
    
    # Install AppArmor if not present
    if ! command -v aa-status >/dev/null 2>&1; then
        log_info "Installing AppArmor package..."
        sudo pacman -S --noconfirm apparmor || {
            log_error "Failed to install AppArmor"
            return 1
        }
    fi
    
    # Check if AppArmor is already enabled
    if check_apparmor_status; then
        log_success "AppArmor is already enabled"
        return 0
    fi
    
    log_info "Configuring AppArmor kernel parameters..."
    
    # Add AppArmor to GRUB configuration
    if grep -q "apparmor=1" /etc/default/grub; then
        log_info "AppArmor already configured in GRUB"
    else
        sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 apparmor=1 security=apparmor"/' /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg || {
            log_error "Failed to update GRUB configuration"
            return 1
        }
        log_success "AppArmor configured in GRUB"
    fi
    
    # Enable AppArmor service
    sudo systemctl enable apparmor || {
        log_error "Failed to enable AppArmor service"
        return 1
    }
    
    log_warning "AppArmor requires a reboot to take effect"
    return 0
}

# Check snapd status
check_snapd_status() {
    log_info "Checking snapd status..."
    
    if ! command -v snap >/dev/null 2>&1; then
        log_error "Snapd is not installed"
        return 1
    fi
    
    if ! systemctl is-active --quiet snapd.socket; then
        log_warning "Snapd socket is not active"
        return 1
    fi
    
    if ! systemctl is-enabled --quiet snapd.socket; then
        log_warning "Snapd socket is not enabled"
        return 1
    fi
    
    log_success "Snapd service is running"
    return 0
}

# Fix snapd service issues
fix_snapd_service() {
    log_info "Fixing snapd service configuration..."
    
    # Stop services
    sudo systemctl stop snapd.service snapd.socket 2>/dev/null || true
    
    # Enable and start socket
    sudo systemctl enable snapd.socket
    sudo systemctl start snapd.socket
    
    # Create classic snap symlink
    sudo ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
    
    # Start snapd service
    sudo systemctl start snapd.service
    
    log_success "Snapd service configuration fixed"
}

# Wait for snapd to seed
wait_for_seeding() {
    log_info "Waiting for snapd to complete seeding..."
    
    local max_attempts=120  # 10 minutes
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        # Try the wait command first
        if sudo snap wait system seed.loaded 2>/dev/null; then
            log_success "Snapd seeding completed"
            return 0
        fi
        
        # Fallback: check if snap commands work
        if sudo snap version >/dev/null 2>&1; then
            log_success "Snapd is responsive"
            return 0
        fi
        
        # Show progress every 30 seconds
        if [ $((attempt % 6)) -eq 0 ]; then
            log_info "Still waiting for snapd seeding... (${attempt}/120 - $((attempt * 5))s elapsed)"
        fi
        
        sleep 5
        ((attempt++))
    done
    
    log_error "Snapd seeding did not complete within 10 minutes"
    return 1
}

# Test snapd functionality
test_snapd() {
    log_info "Testing snapd functionality..."
    
    # Test basic snap command
    if ! sudo snap version >/dev/null 2>&1; then
        log_error "Basic snap command failed"
        return 1
    fi
    
    # Test snap list
    if ! sudo snap list >/dev/null 2>&1; then
        log_error "Snap list command failed"
        return 1
    fi
    
    # Try installing a test snap
    log_info "Installing test snap (hello-world)..."
    if sudo snap install hello-world >/dev/null 2>&1; then
        log_success "Test snap installation successful"
        # Clean up test snap
        sudo snap remove hello-world >/dev/null 2>&1 || true
    else
        log_warning "Test snap installation failed, but basic commands work"
    fi
    
    log_success "Snapd functionality test passed"
    return 0
}

# Install multipass
install_multipass() {
    local use_devmode="${1:-false}"
    
    log_info "Installing multipass..."
    
    if command -v multipass >/dev/null 2>&1; then
        log_info "Multipass is already installed"
        return 0
    fi
    
    local install_cmd="sudo snap install multipass"
    if [[ "$use_devmode" == "true" ]]; then
        install_cmd="sudo snap install multipass --devmode"
        log_info "Using devmode installation (reduced security)"
    fi
    
    if $install_cmd; then
        log_success "Multipass installed successfully"
        
        # Wait for multipass to be ready
        local attempt=0
        while [ $attempt -lt 12 ]; do
            if multipass version >/dev/null 2>&1; then
                log_success "Multipass is ready"
                return 0
            fi
            log_info "Waiting for multipass to become ready... ($((attempt + 1))/12)"
            sleep 5
            ((attempt++))
        done
        
        log_warning "Multipass installed but may not be fully ready"
        return 0
    else
        log_error "Failed to install multipass"
        return 1
    fi
}

# Show diagnostic information
show_diagnostics() {
    echo -e "\n${YELLOW}╔════════════════════════════════════════╗"
    echo -e "║             Diagnostics                ║"
    echo -e "╚════════════════════════════════════════╝${NC}\n"
    
    echo -e "${BLUE}Snapd Version:${NC}"
    sudo snap version 2>/dev/null || echo "  Not available"
    
    echo -e "\n${BLUE}Snapd Service Status:${NC}"
    systemctl status snapd.socket --no-pager -l 2>/dev/null || echo "  Service not found"
    
    echo -e "\n${BLUE}Installed Snaps:${NC}"
    sudo snap list 2>/dev/null || echo "  Cannot list snaps"
    
    echo -e "\n${BLUE}Disk Space:${NC}"
    df -h / /var /tmp 2>/dev/null || echo "  Cannot check disk space"
    
    echo -e "\n${BLUE}Memory Usage:${NC}"
    free -h 2>/dev/null || echo "  Cannot check memory"
}

# Main recovery process
main() {
    show_banner
    
    # Preliminary checks
    check_arch
    check_root
    
    log_info "Starting snapd recovery process for Arch Linux..."
    
    # Step 1: Check AppArmor status
    local use_devmode="false"
    if ! check_apparmor_status; then
        log_warning "AppArmor is not enabled"
        log_info "AppArmor provides security confinement for snaps and is recommended"
        log_info "Without AppArmor, snaps will run in 'devmode' with reduced security"
        echo
        
        if confirm "Do you want to install and configure AppArmor (requires reboot)?" "y"; then
            if setup_apparmor; then
                echo
                log_warning "REBOOT REQUIRED: AppArmor has been configured"
                log_info "After reboot, run this script again or the main setup script"
                echo
                
                if confirm "Reboot now?" "y"; then
                    log_info "Rebooting system..."
                    sudo reboot
                else
                    log_info "Please reboot manually and re-run this script"
                    exit 0
                fi
            else
                log_warning "AppArmor setup failed, continuing with devmode"
                use_devmode="true"
            fi
        else
            log_warning "Continuing without AppArmor - will use devmode"
            use_devmode="true"
        fi
    else
        log_success "AppArmor is enabled"
    fi
    
    # Step 2: Check current snapd status
    if check_snapd_status; then
        log_info "Snapd appears to be working, testing functionality..."
        if test_snapd; then
            log_success "Snapd is working correctly!"
            
            # Try to install multipass if not present
            if ! command -v multipass >/dev/null 2>&1; then
                install_multipass "$use_devmode"
            else
                log_info "Multipass is already installed"
            fi
            
            echo -e "\n${GREEN}✅ Recovery complete! You can now run the main setup script.${NC}\n"
            exit 0
        fi
    fi
    
    # Step 3: Fix service issues
    log_warning "Snapd issues detected, attempting to fix..."
    fix_snapd_service
    
    # Step 4: Wait for seeding
    if ! wait_for_seeding; then
        log_error "Snapd seeding failed"
        show_diagnostics
        
        echo -e "\n${RED}╔════════════════════════════════════════╗"
        echo -e "║            Recovery Failed             ║"
        echo -e "╚════════════════════════════════════════╝${NC}\n"
        
        echo -e "${YELLOW}Manual recovery steps:${NC}"
        echo -e "  1. ${BLUE}sudo systemctl restart snapd${NC}"
        echo -e "  2. ${BLUE}sudo reboot${NC} (if above doesn't work)"
        echo -e "  3. ${BLUE}sudo pacman -R snapd && sudo pacman -S snapd${NC} (reinstall)"
        echo -e "  4. Re-run this script after reboot\n"
        
        exit 1
    fi
    
    # Step 5: Test functionality
    if ! test_snapd; then
        log_error "Snapd functionality test failed"
        show_diagnostics
        exit 1
    fi
    
    # Step 6: Install multipass
    if ! install_multipass "$use_devmode"; then
        log_warning "Multipass installation failed, but snapd is working"
        echo -e "\n${YELLOW}You can try installing multipass manually:${NC}"
        if [[ "$use_devmode" == "true" ]]; then
            echo -e "  ${BLUE}sudo snap install multipass --devmode${NC}\n"
        else
            echo -e "  ${BLUE}sudo snap install multipass${NC}\n"
        fi
    fi
    
    # Success
    echo -e "\n${GREEN}╔════════════════════════════════════════╗"
    echo -e "║           Recovery Successful!         ║"
    echo -e "╚════════════════════════════════════════╝${NC}\n"
    
    log_success "Snapd is now working correctly!"
    log_info "You can now run the main VM setup script:"
    echo -e "  ${BLUE}curl -fsSL <script-url> | bash${NC}\n"
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        cat << 'EOF'
Snapd Recovery Script for Arch Linux

USAGE:
    ./fix-snapd-arch.sh           # Run recovery process
    ./fix-snapd-arch.sh --help    # Show this help

DESCRIPTION:
    Fixes common snapd seeding and initialization issues on Arch Linux.
    This script should be run when you encounter "device not yet seeded"
    errors during multipass installation.

WHAT IT DOES:
    1. Checks snapd service status
    2. Fixes service configuration if needed
    3. Waits for snapd seeding to complete
    4. Tests snapd functionality
    5. Installs multipass if successful

REQUIREMENTS:
    - Arch Linux system
    - snapd package installed
    - Non-root user with sudo access
    - Internet connection

COMMON ISSUES FIXED:
    - "device not yet seeded" errors
    - snapd.socket not running
    - Missing /snap symlink
    - Snapd seeding timeouts
    - AppArmor configuration for better security

EOF
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac