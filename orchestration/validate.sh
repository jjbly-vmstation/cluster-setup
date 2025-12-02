#!/bin/bash
# validate.sh - Validation script for VMStation cluster
# Part of VMStation Cluster Setup
#
# This script validates cluster health and configuration:
# - Node connectivity
# - Kubernetes cluster health
# - Service availability
# - Configuration consistency
#
# Usage:
#   ./validate.sh           # Full validation
#   ./validate.sh quick     # Quick connectivity check
#   ./validate.sh health    # Cluster health only
#   ./validate.sh config    # Configuration validation

set -euo pipefail

# Script information
# shellcheck disable=SC2034
readonly SCRIPT_VERSION="2.0.0"

# Get script directory and load libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Source library files
# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/safety.sh
source "$SCRIPT_DIR/lib/safety.sh"

# Load default configuration
# shellcheck source=config/defaults.env
source "$SCRIPT_DIR/config/defaults.env"

# Validation mode
VALIDATION_MODE="full"
REPORT_FILE=""

# Validation results
declare -A RESULTS
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# Print banner
print_banner() {
    if [[ "$LOG_USE_COLORS" == "true" ]]; then
        echo -e "${LOG_BOLD}${LOG_CYAN}"
    fi
    cat << 'EOF'
__     __    _ _     _       _       
\ \   / /_ _| (_) __| | __ _| |_ ___ 
 \ \ / / _` | | |/ _` |/ _` | __/ _ \
  \ V / (_| | | | (_| | (_| | ||  __/
   \_/ \__,_|_|_|\__,_|\__,_|\__\___|
                                     
     VMStation Cluster Validation
EOF
    if [[ "$LOG_USE_COLORS" == "true" ]]; then
        echo -e "${LOG_NC}"
    fi
    echo ""
}

# Print usage
print_usage() {
    cat << EOF
Usage: $(basename "$0") [MODE] [OPTIONS]

Validate VMStation cluster health and configuration.

Modes:
    full            Full validation (default)
    quick           Quick connectivity check
    health          Cluster health only
    config          Configuration validation only
    services        Service availability check

Options:
    --report FILE   Write report to file
    -v, --verbose   Verbose output
    -h, --help      Show this help message

Examples:
    $(basename "$0")                    # Full validation
    $(basename "$0") quick              # Quick check
    $(basename "$0") --report out.txt   # Full validation with report

EOF
}

# Record a validation result
record_result() {
    local check="$1"
    local status="$2"
    local message="${3:-}"
    
    RESULTS["$check"]="$status:$message"
    
    case "$status" in
        pass)
            ((PASS_COUNT++))
            log_success "✓ $check${message:+: $message}"
            ;;
        fail)
            ((FAIL_COUNT++))
            log_error "✗ $check${message:+: $message}"
            ;;
        warn)
            ((WARN_COUNT++))
            log_warn "⚠ $check${message:+: $message}"
            ;;
        skip)
            log_info "○ $check${message:+: $message} (skipped)"
            ;;
    esac
}

# Check: SSH connectivity
check_ssh_connectivity() {
    log_step "Checking SSH connectivity..."
    
    if [[ -z "$ANSIBLE_INVENTORY" ]] || [[ ! -f "$ANSIBLE_INVENTORY" ]]; then
        record_result "SSH connectivity" "skip" "No inventory file"
        return
    fi
    
    if ! command_exists ansible; then
        record_result "SSH connectivity" "skip" "Ansible not installed"
        return
    fi
    
    local result
    if result=$(ansible -i "$ANSIBLE_INVENTORY" all -m ping -o 2>&1); then
        local success_count
        success_count=$(echo "$result" | grep -c "SUCCESS" || echo "0")
        record_result "SSH connectivity" "pass" "$success_count hosts reachable"
    else
        local fail_count
        fail_count=$(echo "$result" | grep -c "UNREACHABLE" || echo "0")
        if [[ $fail_count -gt 0 ]]; then
            record_result "SSH connectivity" "fail" "$fail_count hosts unreachable"
        else
            record_result "SSH connectivity" "warn" "Some hosts may be unreachable"
        fi
    fi
}

# Check: Kubernetes cluster health
check_kubernetes_health() {
    log_step "Checking Kubernetes cluster health..."
    
    if ! command_exists kubectl; then
        record_result "Kubernetes health" "skip" "kubectl not installed"
        return
    fi
    
    # Check cluster info
    if ! kubectl cluster-info &>/dev/null; then
        record_result "Kubernetes health" "fail" "Cluster not accessible"
        return
    fi
    
    # Check nodes
    local nodes_ready
    nodes_ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
    local nodes_total
    nodes_total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ $nodes_total -eq 0 ]]; then
        record_result "Kubernetes nodes" "fail" "No nodes found"
    elif [[ $nodes_ready -eq "$nodes_total" ]]; then
        record_result "Kubernetes nodes" "pass" "$nodes_ready/$nodes_total nodes ready"
    else
        record_result "Kubernetes nodes" "warn" "$nodes_ready/$nodes_total nodes ready"
    fi
    
    # Check system pods
    local pods_running
    pods_running=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local pods_total
    pods_total=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ $pods_total -eq 0 ]]; then
        record_result "System pods" "warn" "No system pods found"
    elif [[ $pods_running -eq "$pods_total" ]]; then
        record_result "System pods" "pass" "$pods_running/$pods_total pods running"
    else
        record_result "System pods" "warn" "$pods_running/$pods_total pods running"
    fi
    
    record_result "Kubernetes health" "pass" "Cluster accessible"
}

# Check: Required tools
check_required_tools() {
    log_step "Checking required tools..."
    
    local required_tools=("git" "ssh" "python3")
    local missing=()
    
    for tool in "${required_tools[@]}"; do
        if command_exists "$tool"; then
            local version
            version=$("$tool" --version 2>&1 | head -1 || echo "unknown")
            log_debug "$tool: $version"
        else
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        record_result "Required tools" "pass" "All required tools installed"
    else
        record_result "Required tools" "fail" "Missing: ${missing[*]}"
    fi
    
    # Check optional tools
    local optional_tools=("ansible" "kubectl" "helm" "jq")
    local optional_missing=()
    
    for tool in "${optional_tools[@]}"; do
        if ! command_exists "$tool"; then
            optional_missing+=("$tool")
        fi
    done
    
    if [[ ${#optional_missing[@]} -gt 0 ]]; then
        record_result "Optional tools" "warn" "Not installed: ${optional_missing[*]}"
    else
        record_result "Optional tools" "pass" "All optional tools installed"
    fi
}

# Check: Repository status
check_repository_status() {
    log_step "Checking repository status..."
    
    local repos_ok=0
    
    for repo_dir in "$WORKSPACE_DIR"/*; do
        if [[ -d "$repo_dir/.git" ]]; then
            local repo_name
            repo_name=$(basename "$repo_dir")
            
            # Check for uncommitted changes
            if git -C "$repo_dir" diff --quiet 2>/dev/null; then
                ((repos_ok++))
            else
                log_warn "Repository has uncommitted changes: $repo_name"
            fi
        fi
    done
    
    if [[ $repos_ok -gt 0 ]]; then
        record_result "Repository status" "pass" "$repos_ok repositories available"
    else
        record_result "Repository status" "warn" "No repositories in workspace"
    fi
}

# Check: Configuration files
check_configuration() {
    log_step "Checking configuration..."
    
    # Check inventory
    if [[ -n "$ANSIBLE_INVENTORY" ]] && [[ -f "$ANSIBLE_INVENTORY" ]]; then
        record_result "Ansible inventory" "pass" "Found at $ANSIBLE_INVENTORY"
    else
        # Try to find inventory
        local found_inventory=""
        for inv in "$REPO_ROOT/ansible/inventory/hosts.yml" "$WORKSPACE_DIR/cluster-infra/inventory/hosts.yml"; do
            if [[ -f "$inv" ]]; then
                found_inventory="$inv"
                break
            fi
        done
        
        if [[ -n "$found_inventory" ]]; then
            record_result "Ansible inventory" "pass" "Found at $found_inventory"
        else
            record_result "Ansible inventory" "warn" "Not found"
        fi
    fi
    
    # Check Ansible config
    if [[ -f "$REPO_ROOT/ansible/ansible.cfg" ]]; then
        record_result "Ansible config" "pass" "Found"
    else
        record_result "Ansible config" "warn" "Not found"
    fi
    
    # Check kubeconfig
    if [[ -f "$KUBECONFIG" ]]; then
        record_result "Kubeconfig" "pass" "Found at $KUBECONFIG"
    elif [[ -f "${HOME}/.kube/config" ]]; then
        record_result "Kubeconfig" "pass" "Found at ${HOME}/.kube/config"
    else
        record_result "Kubeconfig" "warn" "Not found"
    fi
}

# Check: Service availability
check_services() {
    log_step "Checking service availability..."
    
    if ! command_exists kubectl || ! kubectl cluster-info &>/dev/null; then
        record_result "Services" "skip" "Kubernetes not accessible"
        return
    fi
    
    # Check for monitoring services
    if kubectl get namespace monitoring &>/dev/null; then
        local prom_ready
        prom_ready=$(kubectl get pods -n monitoring -l app=prometheus --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ $prom_ready -gt 0 ]]; then
            record_result "Prometheus" "pass" "Running"
        else
            record_result "Prometheus" "warn" "Not running"
        fi
        
        local grafana_ready
        grafana_ready=$(kubectl get pods -n monitoring -l app=grafana --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ $grafana_ready -gt 0 ]]; then
            record_result "Grafana" "pass" "Running"
        else
            record_result "Grafana" "warn" "Not running"
        fi
    else
        record_result "Monitoring namespace" "warn" "Not found"
    fi
}

# Check: Power management
check_power_management() {
    log_step "Checking power management..."
    
    if [[ -x "$REPO_ROOT/power-management/scripts/vmstation-sleep.sh" ]]; then
        record_result "Sleep script" "pass" "Available"
    else
        record_result "Sleep script" "warn" "Not found"
    fi
    
    if [[ -x "$REPO_ROOT/power-management/scripts/vmstation-wake.sh" ]]; then
        record_result "Wake script" "pass" "Available"
    else
        record_result "Wake script" "warn" "Not found"
    fi
}

# Quick validation
validate_quick() {
    log_header "Quick Validation"
    
    check_required_tools
    check_ssh_connectivity
    
    if command_exists kubectl; then
        if kubectl cluster-info &>/dev/null; then
            record_result "Kubernetes cluster" "pass" "Accessible"
        else
            record_result "Kubernetes cluster" "fail" "Not accessible"
        fi
    fi
}

# Health validation
validate_health() {
    log_header "Health Validation"
    
    check_kubernetes_health
    check_services
}

# Configuration validation
validate_config() {
    log_header "Configuration Validation"
    
    check_configuration
    check_repository_status
}

# Full validation
validate_full() {
    log_header "Full Validation"
    
    check_required_tools
    check_configuration
    check_repository_status
    check_ssh_connectivity
    check_kubernetes_health
    check_services
    check_power_management
}

# Generate report
generate_report() {
    local report_file="$1"
    
    {
        echo "VMStation Cluster Validation Report"
        echo "===================================="
        echo ""
        echo "Date: $(date)"
        echo "Mode: $VALIDATION_MODE"
        echo ""
        echo "Summary"
        echo "-------"
        echo "Passed: $PASS_COUNT"
        echo "Failed: $FAIL_COUNT"
        echo "Warnings: $WARN_COUNT"
        echo ""
        echo "Details"
        echo "-------"
        
        for check in "${!RESULTS[@]}"; do
            local result="${RESULTS[$check]}"
            local status="${result%%:*}"
            local message="${result#*:}"
            printf "%-30s %-6s %s\n" "$check" "[$status]" "$message"
        done
        
        echo ""
        echo "=== End of Report ==="
    } > "$report_file"
    
    log_info "Report written to: $report_file"
}

# Print summary
print_summary() {
    echo ""
    log_header "Validation Summary"
    
    echo ""
    if [[ "$LOG_USE_COLORS" == "true" ]]; then
        echo -e "${LOG_GREEN}Passed: $PASS_COUNT${LOG_NC}"
        echo -e "${LOG_RED}Failed: $FAIL_COUNT${LOG_NC}"
        echo -e "${LOG_YELLOW}Warnings: $WARN_COUNT${LOG_NC}"
    else
        echo "Passed: $PASS_COUNT"
        echo "Failed: $FAIL_COUNT"
        echo "Warnings: $WARN_COUNT"
    fi
    echo ""
    
    if [[ $FAIL_COUNT -gt 0 ]]; then
        log_error "Validation failed with $FAIL_COUNT errors"
        return 1
    elif [[ $WARN_COUNT -gt 0 ]]; then
        log_warn "Validation passed with $WARN_COUNT warnings"
        return 0
    else
        log_success "All validations passed!"
        return 0
    fi
}

# Main function
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            full|quick|health|config|services)
                VALIDATION_MODE="$1"
                shift
                ;;
            --report)
                REPORT_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                LOG_LEVEL=0
                export LOG_LEVEL
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Print banner
    print_banner
    
    # Initialize
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/validate_$(date +%Y%m%d_%H%M%S).log"
    init_log_file "$LOG_FILE"
    
    # Detect inventory
    if [[ -z "$ANSIBLE_INVENTORY" ]]; then
        for inv in "$REPO_ROOT/ansible/inventory/hosts.yml" "$WORKSPACE_DIR/cluster-infra/inventory/hosts.yml"; do
            if [[ -f "$inv" ]]; then
                ANSIBLE_INVENTORY="$inv"
                break
            fi
        done
    fi
    
    log_info "Validation mode: $VALIDATION_MODE"
    log_info "Log file: $LOG_FILE"
    echo ""
    
    # Run validation
    case "$VALIDATION_MODE" in
        full)
            validate_full
            ;;
        quick)
            validate_quick
            ;;
        health)
            validate_health
            ;;
        config)
            validate_config
            ;;
        services)
            check_services
            ;;
    esac
    
    # Generate report if requested
    if [[ -n "$REPORT_FILE" ]]; then
        generate_report "$REPORT_FILE"
    fi
    
    # Print summary
    print_summary
}

main "$@"
