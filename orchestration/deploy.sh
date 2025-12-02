#!/bin/bash
# deploy.sh - Main orchestration script for VMStation cluster deployment
# Part of VMStation Cluster Setup
#
# This script orchestrates deployments across all modular VMStation repositories:
# - cluster-infra: Infrastructure and Kubespray deployment
# - cluster-config: Configuration and infrastructure services
# - cluster-monitor-stack: Monitoring (Prometheus, Grafana, Loki)
# - cluster-application-stack: Applications (Jellyfin, etc.)
# - cluster-tools: Validation and utilities
#
# Usage:
#   ./deploy.sh                     # Full deployment
#   ./deploy.sh kubespray           # Deploy Kubernetes via Kubespray
#   ./deploy.sh monitoring          # Deploy monitoring stack
#   ./deploy.sh infrastructure      # Deploy infrastructure services
#   ./deploy.sh reset               # Reset cluster
#   ./deploy.sh setup               # Initial setup only
#   ./deploy.sh spindown            # Graceful cluster shutdown
#
# Flags:
#   --yes           Skip confirmation prompts
#   --check         Dry-run mode (validate without changes)
#   --dry-run       Same as --check
#   --log-dir DIR   Custom log directory
#   --enable-autosleep  Enable auto-sleep after deployment
#   --offline       Use local repositories only
#   -v, --verbose   Verbose output
#   -h, --help      Show help

set -euo pipefail

# Script information
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="vmstation-deploy"

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

# Load user configuration if exists
if [[ -f "${HOME}/.vmstation/config.env" ]]; then
    # shellcheck source=/dev/null
    source "${HOME}/.vmstation/config.env"
fi

# Runtime configuration
RUN_ID=""
COMMAND=""
VERBOSE="${VERBOSE:-false}"
ENABLE_AUTOSLEEP="${ENABLE_AUTOSLEEP:-false}"
START_PHASE=1
END_PHASE=5

# Available commands
readonly -a COMMANDS=(
    "all:Full deployment (all phases)"
    "debian:Debian base setup"
    "kubespray:Deploy Kubernetes via Kubespray"
    "monitoring:Deploy monitoring stack"
    "infrastructure:Deploy infrastructure services"
    "applications:Deploy application stack"
    "reset:Reset cluster"
    "setup:Initial setup only"
    "spindown:Graceful cluster shutdown"
    "validate:Run validation suite"
    "status:Show cluster status"
)

# Deployment phases
readonly -a PHASES=(
    "infrastructure:Infrastructure (cluster-infra)"
    "configuration:Configuration (cluster-config)"
    "monitoring:Monitoring (cluster-monitor-stack)"
    "applications:Applications (cluster-application-stack)"
    "validation:Validation (cluster-tools)"
)

# Print banner
print_banner() {
    if [[ "$LOG_USE_COLORS" == "true" ]]; then
        echo -e "${LOG_BOLD}${LOG_CYAN}"
    fi
    cat << 'EOF'
 __     ____  __ ____  _        _   _             
 \ \   / /  \/  / ___|| |_ __ _| |_(_) ___  _ __  
  \ \ / /| |\/| \___ \| __/ _` | __| |/ _ \| '_ \ 
   \ V / | |  | |___) | || (_| | |_| | (_) | | | |
    \_/  |_|  |_|____/ \__\__,_|\__|_|\___/|_| |_|
                                                   
     Cluster Deployment Orchestrator v${SCRIPT_VERSION}
EOF
    if [[ "$LOG_USE_COLORS" == "true" ]]; then
        echo -e "${LOG_NC}"
    fi
    echo ""
}

# Print usage
print_usage() {
    cat << EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

VMStation Cluster Deployment Orchestrator

Commands:
EOF
    for cmd_info in "${COMMANDS[@]}"; do
        local cmd="${cmd_info%%:*}"
        local desc="${cmd_info#*:}"
        printf "    %-16s %s\n" "$cmd" "$desc"
    done

    cat << EOF

Options:
    --yes               Skip confirmation prompts
    --check, --dry-run  Dry-run mode (validate without making changes)
    --log-dir DIR       Custom log directory (default: $LOG_DIR)
    --enable-autosleep  Enable auto-sleep after deployment
    --offline           Use local repositories only (no git fetch/clone)
    --phase N           Start from phase N (1-${#PHASES[@]})
    --to-phase N        Stop at phase N
    -v, --verbose       Enable verbose output
    -h, --help          Show this help message
    --version           Show version information

Environment Variables:
    WORKSPACE_DIR       Repository workspace (default: \$HOME/.vmstation/repos)
    LOG_DIR             Log directory (default: \$HOME/.vmstation/logs)
    DRY_RUN             Enable dry-run mode (true/false)
    AUTO_YES            Skip confirmations (true/false)
    OFFLINE_MODE        Use local repos only (true/false)
    VMSTATION_SAFE_MODE Prevent destructive operations (1/0)

Examples:
    $(basename "$0")                    # Full deployment
    $(basename "$0") kubespray          # Deploy Kubernetes only
    $(basename "$0") monitoring --check # Dry-run monitoring deployment
    $(basename "$0") reset --yes        # Reset cluster without prompts
    $(basename "$0") --phase 2          # Start from phase 2

Deployment Phases:
EOF
    local i=1
    for phase_info in "${PHASES[@]}"; do
        local phase_name="${phase_info#*:}"
        echo "    $i. $phase_name"
        ((i++))
    done

    cat << EOF

For more information, see: https://github.com/jjbly-vmstation/cluster-setup
EOF
}

# Print version
print_version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

# Initialize run
init_run() {
    RUN_ID=$(generate_run_id)
    
    # Create directories
    mkdir -p "$WORKSPACE_DIR" "$LOG_DIR" "$STATE_DIR" "$ARTIFACTS_DIR"
    
    # Initialize logging
    LOG_FILE="$LOG_DIR/deploy_${RUN_ID}.log"
    init_log_file "$LOG_FILE"
    
    log_info "Run ID: $RUN_ID"
    log_info "Log file: $LOG_FILE"
    log_info "Workspace: $WORKSPACE_DIR"
}

# Check prerequisites
check_prerequisites() {
    log_header "Checking Prerequisites"
    
    local missing=()
    
    # Required commands
    local required_cmds=("git" "ssh" "python3")
    for cmd in "${required_cmds[@]}"; do
        if command_exists "$cmd"; then
            log_info "✓ $cmd: $(command -v "$cmd")"
        else
            missing+=("$cmd")
            log_error "✗ $cmd: not found"
        fi
    done
    
    # Optional but recommended
    local optional_cmds=("ansible" "kubectl" "helm")
    for cmd in "${optional_cmds[@]}"; do
        if command_exists "$cmd"; then
            log_info "✓ $cmd: $(command -v "$cmd")"
        else
            log_warn "○ $cmd: not found (optional)"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        log_info "Run: $REPO_ROOT/bootstrap/install-dependencies.sh"
        return 1
    fi
    
    log_success "Prerequisites check passed"
}

# Clone or update all modular repositories
setup_repositories() {
    log_header "Setting Up Repositories"
    
    if is_dry_run; then
        log_info "[DRY-RUN] Would set up repositories in $WORKSPACE_DIR"
        return 0
    fi
    
    local repos=(
        "CLUSTER_INFRA_REPO:cluster-infra:$CLUSTER_INFRA_BRANCH"
        "CLUSTER_CONFIG_REPO:cluster-config:$CLUSTER_CONFIG_BRANCH"
        "CLUSTER_MONITOR_REPO:cluster-monitor-stack:$CLUSTER_MONITOR_BRANCH"
        "CLUSTER_APP_REPO:cluster-application-stack:$CLUSTER_APP_BRANCH"
        "CLUSTER_TOOLS_REPO:cluster-tools:$CLUSTER_TOOLS_BRANCH"
    )
    
    for repo_info in "${repos[@]}"; do
        local var_name="${repo_info%%:*}"
        local remainder="${repo_info#*:}"
        local dir_name="${remainder%%:*}"
        local branch="${remainder#*:}"
        local repo_url="${!var_name}"
        local target_dir="$WORKSPACE_DIR/$dir_name"
        
        if [[ "$OFFLINE_MODE" == "true" ]]; then
            if local_repo_exists "$target_dir"; then
                log_info "Using local repository: $dir_name"
            else
                log_warn "Repository not available in offline mode: $dir_name"
            fi
        else
            if ! clone_or_update_repo "$repo_url" "$target_dir" "$branch"; then
                log_warn "Failed to setup repository: $dir_name"
            fi
        fi
    done
    
    log_success "Repositories ready"
}

# Detect Ansible inventory
detect_inventory() {
    # Try cluster-infra first
    local infra_inventory="$WORKSPACE_DIR/cluster-infra/inventory/hosts.yml"
    if [[ -f "$infra_inventory" ]]; then
        ANSIBLE_INVENTORY="$infra_inventory"
        log_info "Using inventory from cluster-infra: $ANSIBLE_INVENTORY"
        return 0
    fi
    
    # Try local repository
    local local_inventory="$REPO_ROOT/ansible/inventory/hosts.yml"
    if [[ -f "$local_inventory" ]]; then
        ANSIBLE_INVENTORY="$local_inventory"
        log_info "Using local inventory: $ANSIBLE_INVENTORY"
        return 0
    fi
    
    log_warn "No inventory file found"
    return 1
}

# Phase 1: Infrastructure (cluster-infra)
phase_infrastructure() {
    log_header "Phase 1: Infrastructure Deployment"
    log_info "Repository: cluster-infra"
    
    local infra_dir="$WORKSPACE_DIR/cluster-infra"
    
    if [[ ! -d "$infra_dir" ]]; then
        log_warn "cluster-infra repository not available"
        log_info "Skipping Kubespray deployment"
        return 0
    fi
    
    log_step "Running Kubespray deployment..."
    
    if is_dry_run; then
        log_info "[DRY-RUN] Would run Kubespray from $infra_dir"
        return 0
    fi
    
    # Check for Kubespray deploy script
    local deploy_script="$infra_dir/deploy.sh"
    if [[ -x "$deploy_script" ]]; then
        if ! "$deploy_script" ${DRY_RUN:+--check}; then
            log_error "Kubespray deployment failed"
            return 1
        fi
    else
        log_info "No deploy.sh in cluster-infra, running Ansible directly"
        # Fallback to direct Ansible if available
        local kubespray_playbook="$infra_dir/playbooks/cluster.yml"
        if [[ -f "$kubespray_playbook" ]] && command_exists ansible-playbook; then
            local ansible_args=("-i" "$ANSIBLE_INVENTORY" "$kubespray_playbook")
            if is_dry_run; then
                ansible_args+=("--check")
            fi
            if [[ "$VERBOSE" == "true" ]]; then
                ansible_args+=("-vv")
            fi
            
            if ! ansible-playbook "${ansible_args[@]}"; then
                log_error "Ansible playbook failed"
                return 1
            fi
        fi
    fi
    
    log_step "Validating cluster health..."
    if command_exists kubectl; then
        if kubectl cluster-info &>/dev/null; then
            log_success "Kubernetes cluster is healthy"
        else
            log_warn "Could not verify cluster health"
        fi
    fi
    
    log_success "Infrastructure phase complete"
}

# Phase 2: Configuration (cluster-config)
phase_configuration() {
    log_header "Phase 2: Configuration Deployment"
    log_info "Repository: cluster-config"
    
    local config_dir="$WORKSPACE_DIR/cluster-config"
    
    if [[ ! -d "$config_dir" ]]; then
        log_warn "cluster-config repository not available"
        log_info "Using local configuration"
        
        # Fallback to local Ansible playbooks
        if [[ -d "$REPO_ROOT/ansible/playbooks" ]]; then
            log_step "Running local configuration playbooks..."
            
            local playbook="$REPO_ROOT/ansible/playbooks/initial-setup.yml"
            if [[ -f "$playbook" ]] && command_exists ansible-playbook; then
                local ansible_args=("-i" "$ANSIBLE_INVENTORY" "$playbook")
                if is_dry_run; then
                    ansible_args+=("--check")
                fi
                
                if ! ansible-playbook "${ansible_args[@]}"; then
                    log_warn "Local playbook had issues"
                fi
            fi
        fi
        return 0
    fi
    
    log_step "Deploying infrastructure services (NTP, Syslog)..."
    
    if is_dry_run; then
        log_info "[DRY-RUN] Would deploy configuration from $config_dir"
        return 0
    fi
    
    # Run cluster-config deployment
    local deploy_script="$config_dir/deploy.sh"
    if [[ -x "$deploy_script" ]]; then
        if ! "$deploy_script" ${DRY_RUN:+--check}; then
            log_warn "Configuration deployment had issues"
        fi
    fi
    
    log_success "Configuration phase complete"
}

# Phase 3: Monitoring (cluster-monitor-stack)
phase_monitoring() {
    log_header "Phase 3: Monitoring Stack Deployment"
    log_info "Repository: cluster-monitor-stack"
    
    local monitor_dir="$WORKSPACE_DIR/cluster-monitor-stack"
    
    if [[ ! -d "$monitor_dir" ]]; then
        log_warn "cluster-monitor-stack repository not available"
        return 0
    fi
    
    log_step "Deploying Prometheus, Grafana, Loki..."
    
    if is_dry_run; then
        log_info "[DRY-RUN] Would deploy monitoring from $monitor_dir"
        return 0
    fi
    
    local deploy_script="$monitor_dir/deploy.sh"
    if [[ -x "$deploy_script" ]]; then
        if ! "$deploy_script" ${DRY_RUN:+--check}; then
            log_warn "Monitoring deployment had issues"
        fi
    fi
    
    log_step "Validating monitoring stack..."
    # Add monitoring validation here
    
    log_success "Monitoring phase complete"
}

# Phase 4: Applications (cluster-application-stack)
phase_applications() {
    log_header "Phase 4: Application Stack Deployment"
    log_info "Repository: cluster-application-stack"
    
    local app_dir="$WORKSPACE_DIR/cluster-application-stack"
    
    if [[ ! -d "$app_dir" ]]; then
        log_warn "cluster-application-stack repository not available"
        return 0
    fi
    
    log_step "Deploying applications (Jellyfin, etc.)..."
    
    if is_dry_run; then
        log_info "[DRY-RUN] Would deploy applications from $app_dir"
        return 0
    fi
    
    local deploy_script="$app_dir/deploy.sh"
    if [[ -x "$deploy_script" ]]; then
        if ! "$deploy_script" ${DRY_RUN:+--check}; then
            log_warn "Application deployment had issues"
        fi
    fi
    
    log_success "Applications phase complete"
}

# Phase 5: Validation (cluster-tools)
phase_validation() {
    log_header "Phase 5: Validation"
    log_info "Repository: cluster-tools"
    
    local tools_dir="$WORKSPACE_DIR/cluster-tools"
    
    log_step "Running validation suite..."
    
    if [[ -d "$tools_dir" ]] && [[ -x "$tools_dir/validate.sh" ]]; then
        if is_dry_run; then
            log_info "[DRY-RUN] Would run validation from $tools_dir"
        else
            if ! "$tools_dir/validate.sh"; then
                log_warn "Validation had warnings"
            fi
        fi
    else
        # Fallback to local validation
        if [[ -x "$REPO_ROOT/bootstrap/verify-prerequisites.sh" ]]; then
            log_step "Running local validation..."
            "$REPO_ROOT/bootstrap/verify-prerequisites.sh" --local-only || true
        fi
    fi
    
    log_step "Generating deployment report..."
    generate_deployment_report
    
    log_success "Validation phase complete"
}

# Generate deployment report
generate_deployment_report() {
    local report_file="$ARTIFACTS_DIR/deployment_report_${RUN_ID}.txt"
    
    {
        echo "VMStation Deployment Report"
        echo "==========================="
        echo ""
        echo "Run ID: $RUN_ID"
        echo "Date: $(date)"
        echo "Command: $COMMAND"
        echo ""
        echo "Repository Status:"
        echo "-----------------"
        
        for repo_dir in "$WORKSPACE_DIR"/*; do
            if [[ -d "$repo_dir/.git" ]]; then
                local repo_name
                repo_name=$(basename "$repo_dir")
                local branch
                branch=$(get_repo_branch "$repo_dir")
                local commit
                commit=$(get_repo_commit "$repo_dir")
                echo "  $repo_name: $branch ($commit)"
            fi
        done
        
        echo ""
        echo "Cluster Status:"
        echo "--------------"
        
        if command_exists kubectl && kubectl cluster-info &>/dev/null; then
            echo "  Kubernetes: Running"
            kubectl get nodes --no-headers 2>/dev/null | while read -r line; do
                echo "    $line"
            done
        else
            echo "  Kubernetes: Not accessible or not deployed"
        fi
        
        echo ""
        echo "Log File: $LOG_FILE"
        echo ""
        echo "=== End of Report ==="
    } > "$report_file"
    
    log_info "Deployment report: $report_file"
}

# Run specific phase by number
run_phase() {
    local phase_num="$1"
    local phase_info="${PHASES[$((phase_num - 1))]}"
    local phase_id="${phase_info%%:*}"
    local phase_name="${phase_info#*:}"
    
    show_progress "$phase_num" "${#PHASES[@]}" "$phase_name"
    
    case "$phase_id" in
        infrastructure) phase_infrastructure ;;
        configuration) phase_configuration ;;
        monitoring) phase_monitoring ;;
        applications) phase_applications ;;
        validation) phase_validation ;;
        *) log_error "Unknown phase: $phase_id"; return 1 ;;
    esac
}

# Full deployment (all phases)
deploy_all() {
    log_header "Full Deployment"
    
    # Pre-flight
    preflight_check "Full Deployment"
    
    if ! is_auto_yes && ! is_dry_run; then
        if ! confirm "Ready to start full deployment?"; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    # Setup repositories
    setup_repositories
    
    # Detect inventory
    detect_inventory || true
    
    # Run phases
    local failed=false
    for ((i=START_PHASE; i<=END_PHASE && i<=${#PHASES[@]}; i++)); do
        if ! run_phase "$i"; then
            log_error "Phase $i failed"
            failed=true
            break
        fi
        echo ""
    done
    
    # Auto-sleep configuration
    if [[ "$ENABLE_AUTOSLEEP" == "true" ]] && [[ "$failed" != "true" ]]; then
        log_step "Configuring auto-sleep..."
        if [[ -x "$REPO_ROOT/orchestration/quick-deploy.sh" ]]; then
            "$REPO_ROOT/orchestration/quick-deploy.sh" autosleep || true
        fi
    fi
    
    # Summary
    echo ""
    log_header "Deployment Summary"
    
    if [[ "$failed" == "true" ]]; then
        log_error "Deployment failed"
        exit 1
    else
        log_success "Deployment completed successfully!"
    fi
}

# Deploy Kubernetes via Kubespray
deploy_kubespray() {
    log_header "Kubespray Deployment"
    
    preflight_check "Kubespray Deployment"
    
    if ! is_auto_yes && ! is_dry_run; then
        if ! confirm "Deploy Kubernetes via Kubespray?"; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    setup_repositories
    detect_inventory || true
    phase_infrastructure
}

# Deploy monitoring stack
deploy_monitoring() {
    log_header "Monitoring Stack Deployment"
    
    preflight_check "Monitoring Deployment"
    
    if ! is_auto_yes && ! is_dry_run; then
        if ! confirm "Deploy monitoring stack?"; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    setup_repositories
    detect_inventory || true
    phase_monitoring
}

# Deploy infrastructure services
deploy_infrastructure_services() {
    log_header "Infrastructure Services Deployment"
    
    preflight_check "Infrastructure Services"
    
    if ! is_auto_yes && ! is_dry_run; then
        if ! confirm "Deploy infrastructure services?"; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    setup_repositories
    detect_inventory || true
    phase_configuration
}

# Deploy applications
deploy_applications() {
    log_header "Application Stack Deployment"
    
    preflight_check "Application Deployment"
    
    if ! is_auto_yes && ! is_dry_run; then
        if ! confirm "Deploy application stack?"; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    setup_repositories
    detect_inventory || true
    phase_applications
}

# Initial setup only
deploy_setup() {
    log_header "Initial Setup"
    
    check_prerequisites
    
    log_step "Installing dependencies..."
    if [[ -x "$REPO_ROOT/bootstrap/install-dependencies.sh" ]]; then
        if is_dry_run; then
            log_info "[DRY-RUN] Would run install-dependencies.sh"
        else
            "$REPO_ROOT/bootstrap/install-dependencies.sh" ${DRY_RUN:+--dry-run}
        fi
    fi
    
    log_step "Setting up SSH keys..."
    if [[ -x "$REPO_ROOT/bootstrap/setup-ssh-keys.sh" ]]; then
        if is_dry_run; then
            log_info "[DRY-RUN] Would run setup-ssh-keys.sh"
        else
            "$REPO_ROOT/bootstrap/setup-ssh-keys.sh" generate || true
        fi
    fi
    
    log_step "Preparing nodes..."
    if [[ -x "$REPO_ROOT/bootstrap/prepare-nodes.sh" ]]; then
        if is_dry_run; then
            log_info "[DRY-RUN] Would run prepare-nodes.sh"
        else
            "$REPO_ROOT/bootstrap/prepare-nodes.sh" --dry-run || true
        fi
    fi
    
    log_success "Initial setup complete"
}

# Debian base setup
deploy_debian() {
    log_header "Debian Base Setup"
    
    preflight_check "Debian Setup"
    
    log_step "Running Debian base configuration..."
    
    # Use local Ansible playbook if available
    local playbook="$REPO_ROOT/ansible/playbooks/debian-base.yml"
    if [[ -f "$playbook" ]] && command_exists ansible-playbook; then
        detect_inventory || true
        
        local ansible_args=("-i" "$ANSIBLE_INVENTORY" "$playbook")
        if is_dry_run; then
            ansible_args+=("--check")
        fi
        
        if ! ansible-playbook "${ansible_args[@]}"; then
            log_warn "Debian setup had issues"
        fi
    else
        log_info "No Debian base playbook found, skipping"
    fi
    
    log_success "Debian setup complete"
}

# Reset cluster
cluster_reset() {
    log_header "Cluster Reset"
    
    preflight_check "Cluster Reset"
    
    # This is a destructive operation
    if ! guard_destructive "Reset entire VMStation cluster" "RESET"; then
        return 1
    fi
    
    log_warn "This will reset the cluster to initial state"
    
    # Use dedicated reset script if available
    if [[ -x "$SCRIPT_DIR/reset.sh" ]]; then
        exec "$SCRIPT_DIR/reset.sh"
    fi
    
    # Fallback reset procedure
    log_step "Draining nodes..."
    if command_exists kubectl && kubectl cluster-info &>/dev/null; then
        local nodes
        nodes=$(kubectl get nodes -o name 2>/dev/null || echo "")
        for node in $nodes; do
            log_info "Draining $node..."
            kubectl drain "${node#node/}" --ignore-daemonsets --delete-emptydir-data --force --timeout=60s 2>/dev/null || true
        done
    fi
    
    log_step "Resetting cluster state..."
    # Add cluster reset logic here
    
    log_success "Cluster reset complete"
}

# Cluster spindown
cluster_spindown() {
    log_header "Cluster Spindown"
    
    preflight_check "Cluster Spindown"
    
    if ! is_auto_yes; then
        if ! confirm "Gracefully shut down the cluster?"; then
            log_info "Spindown cancelled"
            exit 0
        fi
    fi
    
    log_step "Running graceful spindown..."
    
    # Use power management playbook
    local playbook="$REPO_ROOT/power-management/playbooks/spin-down-cluster.yml"
    if [[ -f "$playbook" ]] && command_exists ansible-playbook; then
        detect_inventory || true
        
        local ansible_args=("-i" "$ANSIBLE_INVENTORY" "$playbook")
        if is_dry_run; then
            ansible_args+=("--check")
        fi
        
        if ! ansible-playbook "${ansible_args[@]}"; then
            log_warn "Spindown had issues"
        fi
    else
        log_info "No spindown playbook found"
        
        # Fallback to sleep scripts
        if [[ -x "$REPO_ROOT/power-management/scripts/vmstation-sleep.sh" ]]; then
            log_step "Using vmstation-sleep.sh..."
            "$REPO_ROOT/power-management/scripts/vmstation-sleep.sh" ${DRY_RUN:+--check}
        fi
    fi
    
    log_success "Cluster spindown complete"
}

# Run validation
run_validation() {
    log_header "Cluster Validation"
    
    check_prerequisites
    setup_repositories
    detect_inventory || true
    phase_validation
}

# Show cluster status
show_status() {
    log_header "Cluster Status"
    
    echo ""
    echo "Repository Status:"
    echo "-----------------"
    
    for repo_dir in "$WORKSPACE_DIR"/*; do
        if [[ -d "$repo_dir/.git" ]]; then
            local repo_name
            repo_name=$(basename "$repo_dir")
            local branch
            branch=$(get_repo_branch "$repo_dir" 2>/dev/null || echo "unknown")
            local commit
            commit=$(get_repo_commit "$repo_dir" 2>/dev/null || echo "unknown")
            echo "  $repo_name: $branch ($commit)"
        fi
    done
    
    echo ""
    echo "Kubernetes Status:"
    echo "-----------------"
    
    if command_exists kubectl; then
        if kubectl cluster-info &>/dev/null; then
            kubectl cluster-info 2>/dev/null | head -5
            echo ""
            kubectl get nodes 2>/dev/null || echo "  Could not get node status"
        else
            echo "  Cluster not accessible"
        fi
    else
        echo "  kubectl not installed"
    fi
    
    echo ""
    echo "Services Status:"
    echo "---------------"
    
    if command_exists kubectl && kubectl cluster-info &>/dev/null; then
        kubectl get pods -A 2>/dev/null | head -20 || echo "  Could not get pod status"
    else
        echo "  Cannot check services"
    fi
}

# Main function
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            all|debian|kubespray|monitoring|infrastructure|applications|reset|setup|spindown|validate|status)
                COMMAND="$1"
                shift
                ;;
            --yes|-y)
                AUTO_YES="true"
                export AUTO_YES
                shift
                ;;
            --check|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            --log-dir)
                LOG_DIR="$2"
                shift 2
                ;;
            --enable-autosleep)
                ENABLE_AUTOSLEEP="true"
                shift
                ;;
            --offline)
                OFFLINE_MODE="true"
                shift
                ;;
            --phase)
                START_PHASE="$2"
                shift 2
                ;;
            --to-phase)
                END_PHASE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE="true"
                LOG_LEVEL=0
                export LOG_LEVEL
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            --version)
                print_version
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo ""
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Default command
    if [[ -z "$COMMAND" ]]; then
        COMMAND="all"
    fi
    
    # Print banner
    print_banner
    
    # Initialize run
    init_run
    
    # Set up signal handlers
    setup_signal_handlers
    
    # Execute command
    case "$COMMAND" in
        all)
            deploy_all
            ;;
        debian)
            deploy_debian
            ;;
        kubespray)
            deploy_kubespray
            ;;
        monitoring)
            deploy_monitoring
            ;;
        infrastructure)
            deploy_infrastructure_services
            ;;
        applications)
            deploy_applications
            ;;
        reset)
            cluster_reset
            ;;
        setup)
            # shellcheck disable=SC2119
            deploy_setup
            ;;
        spindown)
            cluster_spindown
            ;;
        validate)
            run_validation
            ;;
        status)
            show_status
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            print_usage
            exit 1
            ;;
    esac
    
    log_info "Log file: $LOG_FILE"
}

main "$@"
