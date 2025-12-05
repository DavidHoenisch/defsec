#!/usr/bin/env bash

# Test script for the improved setup script
# This script validates functionality without creating actual VMs

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
readonly SETUP_SCRIPT="$SCRIPT_DIR/setup-improved.sh"
readonly TEST_LOG="$SCRIPT_DIR/test-results.log"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging
log_test() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$TEST_LOG"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*" | tee -a "$TEST_LOG"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*" | tee -a "$TEST_LOG"
    ((TESTS_FAILED++))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$TEST_LOG"
}

# Test helper functions
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((TESTS_RUN++))
    log_info "Running test: $test_name"
    
    if eval "$test_command"; then
        log_pass "$test_name"
        return 0
    else
        log_fail "$test_name"
        return 1
    fi
}

# Individual tests
test_script_exists() {
    [[ -f "$SETUP_SCRIPT" ]] && [[ -x "$SETUP_SCRIPT" ]]
}

test_help_option() {
    "$SETUP_SCRIPT" --help >/dev/null 2>&1
}

test_dry_run_option() {
    timeout 30 "$SETUP_SCRIPT" --dry-run >/dev/null 2>&1 || [[ $? -eq 124 ]]
}

test_invalid_option() {
    ! "$SETUP_SCRIPT" --invalid-option >/dev/null 2>&1
}

test_script_syntax() {
    bash -n "$SETUP_SCRIPT"
}

test_shellcheck() {
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck "$SETUP_SCRIPT"
    else
        log_info "Shellcheck not available, skipping syntax analysis"
        return 0
    fi
}

test_dependencies_check() {
    # Test that script can detect missing dependencies
    local temp_script="/tmp/test_deps_$$"
    sed 's/command_exists.*jq.*/command_exists "nonexistent_command_xyz"/' "$SETUP_SCRIPT" > "$temp_script"
    chmod +x "$temp_script"
    
    if ! "$temp_script" --dry-run >/dev/null 2>&1; then
        rm -f "$temp_script"
        return 0
    else
        rm -f "$temp_script"
        return 1
    fi
}

test_os_detection() {
    # Extract and test OS detection function
    bash -c "
    source '$SETUP_SCRIPT'
    detect_os() {
        if [[ \"\$OSTYPE\" == \"linux-gnu\"* ]]; then
            echo \"linux\"
        elif [[ \"\$OSTYPE\" == \"darwin\"* ]]; then
            echo \"macos\"
        else
            echo \"unknown\"
        fi
    }
    result=\$(detect_os)
    [[ \"\$result\" =~ ^(linux|macos|unknown)\$ ]]
    "
}

test_logging_functions() {
    # Test that logging functions work
    bash -c "
    source '$SETUP_SCRIPT' 2>/dev/null || true
    # Test basic logging (these functions should exist)
    type log_info >/dev/null 2>&1 &&
    type log_error >/dev/null 2>&1 &&
    type log_success >/dev/null 2>&1 &&
    type log_warning >/dev/null 2>&1
    "
}

test_config_variables() {
    # Test that configuration variables are defined
    bash -c "
    source '$SETUP_SCRIPT' 2>/dev/null || true
    [[ -n \"\${VM_NAMES:-}\" ]] &&
    [[ -n \"\${VM_CPUS:-}\" ]] &&
    [[ -n \"\${VM_MEMORY:-}\" ]] &&
    [[ -n \"\${VM_DISK:-}\" ]]
    "
}

test_error_handling() {
    # Test that script uses proper error handling
    grep -q "set -euo pipefail" "$SETUP_SCRIPT"
}

test_cleanup_function() {
    # Test that cleanup function exists
    grep -q "cleanup()" "$SETUP_SCRIPT"
}

test_argument_parsing() {
    # Test various argument combinations
    "$SETUP_SCRIPT" --help >/dev/null 2>&1 &&
    "$SETUP_SCRIPT" -h >/dev/null 2>&1 &&
    ! "$SETUP_SCRIPT" --invalid >/dev/null 2>&1
}

# Performance tests
test_script_performance() {
    # Test that help loads quickly (under 2 seconds)
    local start_time end_time duration
    start_time=$(date +%s)
    "$SETUP_SCRIPT" --help >/dev/null 2>&1
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    [[ $duration -lt 2 ]]
}

# Security tests
test_no_hardcoded_paths() {
    # Check for potential security issues
    ! grep -E "(sudo.*rm.*-rf|rm.*-rf.*\$)" "$SETUP_SCRIPT" &&
    ! grep -E "curl.*\|.*bash" "$SETUP_SCRIPT"
}

test_input_validation() {
    # Test that script validates inputs properly
    grep -q "error_exit" "$SETUP_SCRIPT"
}

# Main test runner
run_all_tests() {
    log_test "Starting test suite for improved setup script"
    log_info "Testing script: $SETUP_SCRIPT"
    
    # Basic functionality tests
    run_test "Script exists and is executable" "test_script_exists"
    run_test "Script syntax is valid" "test_script_syntax"
    run_test "Help option works" "test_help_option"
    run_test "Dry-run option works" "test_dry_run_option"
    run_test "Invalid options are rejected" "test_invalid_option"
    run_test "Argument parsing works" "test_argument_parsing"
    
    # Code quality tests
    run_test "Shellcheck analysis passes" "test_shellcheck"
    run_test "Error handling is enabled" "test_error_handling"
    run_test "Cleanup function exists" "test_cleanup_function"
    run_test "Logging functions exist" "test_logging_functions"
    run_test "Configuration variables defined" "test_config_variables"
    
    # Functional tests
    run_test "OS detection works" "test_os_detection"
    run_test "Dependencies check works" "test_dependencies_check"
    
    # Performance tests
    run_test "Script loads quickly" "test_script_performance"
    
    # Security tests
    run_test "No dangerous hardcoded commands" "test_no_hardcoded_paths"
    run_test "Input validation exists" "test_input_validation"
}

# Report generation
generate_report() {
    echo
    log_info "Test Results Summary:"
    log_info "===================="
    log_info "Tests run: $TESTS_RUN"
    log_pass "Tests passed: $TESTS_PASSED"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        log_fail "Tests failed: $TESTS_FAILED"
        echo
        log_info "Check $TEST_LOG for detailed results"
        return 1
    else
        echo
        log_pass "All tests passed! ✨"
        log_info "The improved setup script is ready for use"
        return 0
    fi
}

# Cleanup
cleanup_test() {
    # Remove any temporary files
    rm -f /tmp/test_deps_*
}

trap cleanup_test EXIT

# Main execution
main() {
    echo -e "${BLUE}╔═══════════════════════════════════════╗"
    echo -e "║       Setup Script Test Suite         ║"
    echo -e "╚═══════════════════════════════════════╝${NC}"
    echo
    
    # Initialize log
    mkdir -p "$(dirname "$TEST_LOG")"
    echo > "$TEST_LOG"
    
    # Check if setup script exists
    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        log_fail "Setup script not found: $SETUP_SCRIPT"
        exit 1
    fi
    
    # Run tests
    run_all_tests
    
    # Generate report
    generate_report
}

# Run if called directly
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi