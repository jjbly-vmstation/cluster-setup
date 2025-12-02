#!/bin/bash
# reset.sh - Cluster reset script for VMStation
# Part of VMStation Cluster Setup
#
# This script performs a safe cluster reset:
# - Drains all nodes
# - Removes workloads
# - Resets Kubernetes state
# - Optionally resets to bare metal
#
# Usage:
#   ./reset.sh              # Interactive reset
#   ./reset.sh --soft       # Soft reset (keep Kubernetes)
#   ./reset.sh --hard       # Hard reset (remove Kubernetes)
#   ./reset.sh --yes        # Skip confirmations

set -euo pipefail

# Script information
# shellcheck disable=SC2034
readonly SCRIPT_VERSION="2.0.0"

# Get script directory and load libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
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

# Reset modes
RESET_MODE="soft"  # soft, hard, full
BACKUP_ENABLED="${FEATURE_AUTO_BACKUP:-true}"

# Print banner
print_banner() {
    if [[ "$LOG_USE_COLORS" == "true" ]]; then
        echo -e "${LOG_BOLD}${LOG_RED}"
    fi
    cat << 'EOF'
 ____  _____ ____  _____ _____ 
|  _ \| ____/ ___|| ____|_   _|
| |_) |  _| \___ \|  _|   | |  
|  _ <| |___ ___) | |___  | |  
|_| \_\_____|____/|_____| |_|  
                               
     VMStation Cluster Reset
EOF
    if [[ "$LOG_USE_COLORS" == "true" ]]; then
        echo -e "${LOG_NC}"
    fi
    echo ""
}

# Print usage
print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Reset VMStation cluster to a clean state.

Reset Modes:
    --soft          Soft reset: remove workloads, keep Kubernetes (default)
    --hard          Hard reset: remove Kubernetes, keep base OS
    --full          Full reset: reset to bare metal (dangerous!)

Options:
    --yes           Skip confirmation prompts
    --no-backup     Skip backup creation
    --check         Dry-run mode (show what would be done)
    -v, --verbose   Verbose output
    -h, --help      Show this help message

Safety:
    - Soft reset is the default and safest option
    - Hard reset requires typing 'RESET' to confirm
    - Full reset requires typing 'DESTROY' to confirm
    - Use VMSTATION_SAFE_MODE=1 to block destructive operations

Examples:
    $(basename "$0")                 # Interactive soft reset
    $(basename "$0") --soft --yes    # Automatic soft reset
    $(basename "$0") --hard          # Hard reset with confirmation
    $(basename "$0") --check         # Preview reset actions

EOF
}

# Create backup before reset
create_reset_backup() {
    if [[ "$BACKUP_ENABLED" != "true" ]]; then
        log_info "Backup disabled, skipping"
        return 0
    fi
    
    log_step "Creating pre-reset backup..."
    
    local backup_dir
    backup_dir="$BACKUP_DIR/reset_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup Kubernetes state if available
    if command_exists kubectl && kubectl cluster-info &>/dev/null; then
        log_info "Backing up Kubernetes resources..."
        
        # Backup all namespaces
        kubectl get namespaces -o yaml > "$backup_dir/namespaces.yaml" 2>/dev/null || true
        
        # Backup deployments
        kubectl get deployments -A -o yaml > "$backup_dir/deployments.yaml" 2>/dev/null || true
        
        # Backup services
        kubectl get services -A -o yaml > "$backup_dir/services.yaml" 2>/dev/null || true
        
        # Backup configmaps
        kubectl get configmaps -A -o yaml > "$backup_dir/configmaps.yaml" 2>/dev/null || true
        
        # Backup secrets (if allowed)
        kubectl get secrets -A -o yaml > "$backup_dir/secrets.yaml" 2>/dev/null || true
    fi
    
    # Backup state files
    if [[ -d "$STATE_DIR" ]]; then
        cp -r "$STATE_DIR" "$backup_dir/state" 2>/dev/null || true
    fi
    
    log_success "Backup created: $backup_dir"
}

# Drain all Kubernetes nodes
drain_nodes() {
    log_step "Draining Kubernetes nodes..."
    
    if ! command_exists kubectl; then
        log_warn "kubectl not available"
        return 0
    fi
    
    if ! kubectl cluster-info &>/dev/null; then
        log_warn "Kubernetes cluster not accessible"
        return 0
    fi
    
    local nodes
    nodes=$(kubectl get nodes -o name 2>/dev/null || echo "")
    
    if [[ -z "$nodes" ]]; then
        log_info "No nodes found"
        return 0
    fi
    
    for node in $nodes; do
        local node_name="${node#node/}"
        log_info "Draining node: $node_name"
        
        if is_dry_run; then
            log_info "[DRY-RUN] Would drain $node_name"
        else
            kubectl drain "$node_name" \
                --ignore-daemonsets \
                --delete-emptydir-data \
                --force \
                --timeout=120s 2>/dev/null || log_warn "Drain had warnings for $node_name"
        fi
    done
    
    log_success "All nodes drained"
}

# Remove all workloads
remove_workloads() {
    log_step "Removing workloads..."
    
    if ! command_exists kubectl; then
        log_warn "kubectl not available"
        return 0
    fi
    
    if ! kubectl cluster-info &>/dev/null; then
        log_warn "Kubernetes cluster not accessible"
        return 0
    fi
    
    # Get all namespaces except system namespaces
    local namespaces
    namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    local system_namespaces="kube-system kube-public kube-node-lease default"
    
    for ns in $namespaces; do
        # Skip system namespaces
        if [[ " $system_namespaces " =~ $ns ]]; then
            continue
        fi
        
        log_info "Removing workloads from namespace: $ns"
        
        if is_dry_run; then
            log_info "[DRY-RUN] Would delete all in namespace $ns"
        else
            kubectl delete all --all -n "$ns" --timeout=60s 2>/dev/null || true
        fi
    done
    
    log_success "Workloads removed"
}

# Soft reset - remove workloads, keep Kubernetes
soft_reset() {
    log_header "Soft Reset"
    
    if ! is_auto_yes; then
        if ! confirm "Perform soft reset? This will remove all workloads but keep Kubernetes."; then
            log_info "Reset cancelled"
            return 1
        fi
    fi
    
    create_reset_backup
    drain_nodes
    remove_workloads
    
    # Uncordon nodes
    log_step "Uncordoning nodes..."
    if command_exists kubectl && kubectl cluster-info &>/dev/null; then
        local nodes
        nodes=$(kubectl get nodes -o name 2>/dev/null || echo "")
        for node in $nodes; do
            local node_name="${node#node/}"
            if is_dry_run; then
                log_info "[DRY-RUN] Would uncordon $node_name"
            else
                kubectl uncordon "$node_name" 2>/dev/null || true
            fi
        done
    fi
    
    log_success "Soft reset complete"
}

# Hard reset - remove Kubernetes
hard_reset() {
    log_header "Hard Reset"
    
    if ! guard_destructive "Remove Kubernetes from all nodes" "RESET"; then
        return 1
    fi
    
    create_reset_backup
    drain_nodes
    
    log_step "Removing Kubernetes..."
    
    # Use Kubespray reset if available
    local infra_dir="$WORKSPACE_DIR/cluster-infra"
    if [[ -d "$infra_dir" ]] && [[ -f "$infra_dir/reset.yml" ]]; then
        log_info "Using Kubespray reset playbook..."
        
        if [[ -n "$ANSIBLE_INVENTORY" ]] && [[ -f "$ANSIBLE_INVENTORY" ]]; then
            local ansible_args=("-i" "$ANSIBLE_INVENTORY" "$infra_dir/reset.yml")
            if is_dry_run; then
                ansible_args+=("--check")
            fi
            
            if command_exists ansible-playbook; then
                ansible-playbook "${ansible_args[@]}" || log_warn "Kubespray reset had warnings"
            fi
        fi
    else
        log_info "No Kubespray reset playbook, performing manual reset..."
        
        # Manual Kubernetes removal
        if is_dry_run; then
            log_info "[DRY-RUN] Would remove Kubernetes packages and configuration"
        else
            log_warn "Manual Kubernetes removal not implemented"
            log_info "Use Kubespray reset playbook for complete removal"
        fi
    fi
    
    log_success "Hard reset complete"
}

# Full reset - back to bare metal
full_reset() {
    log_header "Full Reset"
    
    log_warn "⚠️  DANGER: This will reset all nodes to bare metal!"
    log_warn "All data, configuration, and software will be removed!"
    
    if ! guard_destructive "Reset cluster to bare metal (ALL DATA WILL BE LOST)" "DESTROY"; then
        return 1
    fi
    
    create_reset_backup
    
    log_step "Performing full reset..."
    
    # This would typically involve:
    # 1. Stopping all services
    # 2. Removing Kubernetes
    # 3. Removing Docker/containerd
    # 4. Removing all configuration
    # 5. Optionally re-imaging nodes
    
    if is_dry_run; then
        log_info "[DRY-RUN] Would perform full system reset"
    else
        log_error "Full reset requires manual intervention or PXE re-imaging"
        log_info "This safety measure prevents accidental data loss"
    fi
    
    log_success "Full reset preparation complete"
}

# Clean up state files
cleanup_state() {
    log_step "Cleaning up state files..."
    
    if is_dry_run; then
        log_info "[DRY-RUN] Would clean up state files in $STATE_DIR"
        return 0
    fi
    
    if [[ -d "$STATE_DIR" ]]; then
        # Remove deployment state
        rm -f "$STATE_DIR"/*.state 2>/dev/null || true
        rm -f "$STATE_DIR"/deploy_* 2>/dev/null || true
    fi
    
    log_success "State files cleaned"
}

# Main function
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --soft)
                RESET_MODE="soft"
                shift
                ;;
            --hard)
                RESET_MODE="hard"
                shift
                ;;
            --full)
                RESET_MODE="full"
                shift
                ;;
            --yes|-y)
                AUTO_YES="true"
                export AUTO_YES
                shift
                ;;
            --no-backup)
                BACKUP_ENABLED="false"
                shift
                ;;
            --check|--dry-run)
                DRY_RUN="true"
                shift
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
    
    # Initialize logging
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/reset_$(date +%Y%m%d_%H%M%S).log"
    init_log_file "$LOG_FILE"
    
    log_info "Reset mode: $RESET_MODE"
    log_info "Dry-run: $DRY_RUN"
    log_info "Backup enabled: $BACKUP_ENABLED"
    
    # Pre-flight check
    preflight_check "Cluster Reset ($RESET_MODE)"
    
    # Execute reset
    case "$RESET_MODE" in
        soft)
            soft_reset
            ;;
        hard)
            hard_reset
            ;;
        full)
            full_reset
            ;;
        *)
            log_error "Unknown reset mode: $RESET_MODE"
            exit 1
            ;;
    esac
    
    # Cleanup
    cleanup_state
    
    echo ""
    log_header "Reset Complete"
    log_info "Log file: $LOG_FILE"
    
    if [[ "$RESET_MODE" == "full" ]]; then
        log_warn "Manual steps may be required to complete full reset"
    fi
}

main "$@"
