#!/usr/bin/env bash

# Multipass Troubleshooting and Fix Script
# Fixes common multipass connectivity and launch issues

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

log_step() {
    echo -e "${GREEN}▶${NC} $*"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Show banner
show_banner() {
    echo -e "\n${BLUE}╔════════════════════════════════════════╗"
    echo -e "║         Multipass Troubleshooter      ║"
    echo -e "╚════════════════════════════════════════╝${NC}\n"
}

# Check basic connectivity
check_connectivity() {
    log_step "Testing network connectivity..."
    
    if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
        log_success "Basic network connectivity: OK"
    else
        log_error "Basic network connectivity: FAILED"
        return 1
    fi
    
    if ping -c 3 cloud-images.ubuntu.com >/dev/null 2>&1; then
        log_success "Ubuntu cloud images server: OK"
    else
        log_warning "Ubuntu cloud images server: UNREACHABLE"
        log_info "This might cause image download issues"
    fi
    
    return 0
}

# Check multipass status
check_multipass_status() {
    log_step "Checking multipass status..."
    
    if ! command_exists multipass; then
        log_error "Multipass is not installed"
        return 1
    fi
    
    log_info "Multipass version: $(multipass version 2>/dev/null || echo 'Unknown')"
    
    if multipass list >/dev/null 2>&1; then
        log_success "Multipass daemon is responsive"
        return 0
    else
        log_error "Multipass daemon is not responding"
        return 1
    fi
}

# Test image availability
test_image_availability() {
    log_step "Testing Ubuntu image availability..."
    
    local images
    if images=$(multipass find 2>/dev/null); then
        log_success "Can query available images"
        
        if echo "$images" | grep -q "24.04"; then
            log_success "Ubuntu 24.04 LTS is available"
        else
            log_warning "Ubuntu 24.04 LTS not found"
        fi
        
        if echo "$images" | grep -q "22.04"; then
            log_success "Ubuntu 22.04 LTS is available (fallback)"
        else
            log_warning "Ubuntu 22.04 LTS not found"
        fi
        
        echo -e "\nTop 5 available images:"
        echo "$images" | head -6
        
    else
        log_error "Cannot query available images"
        return 1
    fi
    
    return 0
}

# Restart multipass services
restart_multipass() {
    log_step "Restarting multipass services..."
    
    if command_exists systemctl; then
        log_info "Using systemctl to restart multipass..."
        sudo systemctl restart multipass 2>/dev/null || {
            log_warning "systemctl restart failed"
        }
    fi
    
    if command_exists snap; then
        log_info "Using snap to restart multipass..."
        sudo snap restart multipass 2>/dev/null || {
            log_warning "snap restart failed"
        }
    fi
    
    log_info "Waiting for multipass to restart..."
    sleep 10
    
    if multipass list >/dev/null 2>&1; then
        log_success "Multipass restarted successfully"
        return 0
    else
        log_error "Multipass restart failed"
        return 1
    fi
}

# Test VM creation
test_vm_creation() {
    log_step "Testing VM creation..."
    
    local test_vm="test-vm-$$"
    
    log_info "Creating test VM: $test_vm"
    
    # Try with 24.04 first
    if multipass launch --name "$test_vm" --cpus 1 --memory 1G --disk 5G 24.04 >/dev/null 2>&1; then
        log_success "Test VM created successfully with Ubuntu 24.04"
        multipass delete "$test_vm" >/dev/null 2>&1 || true
        multipass purge >/dev/null 2>&1 || true
        return 0
    fi
    
    # Try with 22.04 fallback
    log_warning "24.04 failed, trying 22.04..."
    if multipass launch --name "$test_vm" --cpus 1 --memory 1G --disk 5G 22.04 >/dev/null 2>&1; then
        log_success "Test VM created successfully with Ubuntu 22.04"
        multipass delete "$test_vm" >/dev/null 2>&1 || true
        multipass purge >/dev/null 2>&1 || true
        return 0
    fi
    
    log_error "Test VM creation failed with both 24.04 and 22.04"
    return 1
}

# Show diagnostic information
show_diagnostics() {
    echo -e "\n${YELLOW}╔════════════════════════════════════════╗"
    echo -e "║             Diagnostics                ║"
    echo -e "╚════════════════════════════════════════╝${NC}\n"
    
    echo -e "${BLUE}System Information:${NC}"
    uname -a 2>/dev/null || echo "  Cannot get system info"
    
    echo -e "\n${BLUE}Multipass Version:${NC}"
    multipass version 2>/dev/null || echo "  Not available"
    
    echo -e "\n${BLUE}Multipass Status:${NC}"
    if command_exists systemctl; then
        systemctl status multipass --no-pager -l 2>/dev/null || echo "  Service not found"
    fi
    
    echo -e "\n${BLUE}Network Interfaces:${NC}"
    ip addr show 2>/dev/null | grep -E "^[0-9]+:|inet " || echo "  Cannot show interfaces"
    
    echo -e "\n${BLUE}Disk Space:${NC}"
    df -h / /var /tmp 2>/dev/null || echo "  Cannot check disk space"
    
    echo -e "\n${BLUE}Memory Usage:${NC}"
    free -h 2>/dev/null || echo "  Cannot check memory"
    
    echo -e "\n${BLUE}Virtualization Support:${NC}"
    if [[ -r /proc/cpuinfo ]]; then
        if grep -q "vmx\|svm" /proc/cpuinfo; then
            echo "  Hardware virtualization: Supported"
        else
            echo "  Hardware virtualization: Not detected"
        fi
    fi
    
    if [[ -c /dev/kvm ]]; then
        echo "  KVM device: Available"
    else
        echo "  KVM device: Not available"
    fi
}

# Fix common issues
fix_common_issues() {
    log_step "Attempting to fix common issues..."
    
    # Fix permissions
    if [[ -d ~/.multipass ]]; then
        log_info "Fixing multipass directory permissions..."
        sudo chown -R "$USER:$USER" ~/.multipass 2>/dev/null || true
    fi
    
    # Clear any stuck operations
    log_info "Clearing any stuck operations..."
    multipass delete --all --purge 2>/dev/null || true
    
    # Restart network (if systemd)
    if command_exists systemctl; then
        log_info "Restarting network services..."
        sudo systemctl restart systemd-networkd 2>/dev/null || true
        sudo systemctl restart systemd-resolved 2>/dev/null || true
    fi
    
    log_success "Common fixes applied"
}

# Main recovery process
main() {
    show_banner
    
    log_info "Starting multipass troubleshooting..."
    
    # Step 1: Basic checks
    if ! check_connectivity; then
        log_error "Network connectivity issues detected"
        log_info "Please check your internet connection and try again"
        exit 1
    fi
    
    # Step 2: Check multipass status
    if check_multipass_status; then
        log_info "Multipass appears to be working, testing image availability..."
        
        if test_image_availability; then
            log_info "Images are available, testing VM creation..."
            
            if test_vm_creation; then
                log_success "Multipass is working correctly!"
                echo -e "\n${GREEN}✅ All tests passed! Multipass should work for VM creation.${NC}\n"
                exit 0
            fi
        fi
    fi
    
    # Step 3: Try to fix issues
    log_warning "Issues detected, attempting repairs..."
    
    fix_common_issues
    
    if ! restart_multipass; then
        log_error "Could not restart multipass services"
        show_diagnostics
        exit 1
    fi
    
    # Step 4: Re-test after fixes
    log_info "Re-testing after fixes..."
    
    if test_image_availability && test_vm_creation; then
        log_success "Fixes successful! Multipass is now working."
        echo -e "\n${GREEN}✅ Multipass has been fixed and is ready for use.${NC}\n"
    else
        log_error "Fixes were not successful"
        show_diagnostics
        
        echo -e "\n${RED}╔════════════════════════════════════════╗"
        echo -e "║            Troubleshooting Failed     ║"
        echo -e "╚════════════════════════════════════════╝${NC}\n"
        
        echo -e "${YELLOW}Manual troubleshooting steps:${NC}"
        echo -e "  1. ${BLUE}sudo snap remove multipass${NC}"
        echo -e "  2. ${BLUE}sudo snap install multipass${NC}"
        echo -e "  3. ${BLUE}sudo reboot${NC}"
        echo -e "  4. Re-run this script after reboot\n"
        
        echo -e "${YELLOW}Alternative solutions:${NC}"
        echo -e "  1. Check firewall settings"
        echo -e "  2. Verify virtualization is enabled in BIOS"
        echo -e "  3. Try using VirtualBox instead of multipass"
        echo -e "  4. Check for proxy/VPN interference\n"
        
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        cat << 'EOF'
Multipass Troubleshooting Script

USAGE:
    ./fix-multipass.sh           # Run troubleshooting
    ./fix-multipass.sh --help    # Show this help

DESCRIPTION:
    Diagnoses and fixes common multipass issues including:
    - Network connectivity problems
    - Image download failures
    - VM launch failures
    - Service startup issues

WHAT IT DOES:
    1. Tests network connectivity
    2. Checks multipass daemon status
    3. Verifies image availability
    4. Tests VM creation
    5. Applies common fixes
    6. Restarts services if needed

REQUIREMENTS:
    - multipass installed
    - sudo access
    - Internet connection

COMMON ISSUES FIXED:
    - "Remote release is unknown or unreachable"
    - "launch failed" errors
    - Multipass daemon not responding
    - Network connectivity issues
    - Permission problems

EOF
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac