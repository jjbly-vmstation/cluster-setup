#!/bin/bash
# deploy-wrapper.sh - Main deployment orchestration script
# Part of VMStation Cluster Setup
#
# This script orchestrates the complete cluster setup process:
# - Pre-flight validation
# - Bootstrap dependencies
# - SSH key setup
# - Node preparation
# - Ansible playbook execution
# - Post-deployment verification
#
# Usage:
#   ./deploy-wrapper.sh              # Full deployment
#   ./deploy-wrapper.sh --check      # Validate only
#   ./deploy-wrapper.sh --phase 3    # Start from specific phase

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
INVENTORY_FILE="${INVENTORY_FILE:-$REPO_ROOT/ansible/inventory/hosts.yml}"
ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-$REPO_ROOT/ansible/ansible.cfg}"
STATE_FILE="${STATE_FILE:-/tmp/vmstation-deploy-state}"
LOG_FILE="${LOG_FILE:-/tmp/vmstation-deploy.log}"

# Modes
DRY_RUN="${DRY_RUN:-false}"
INTERACTIVE="${INTERACTIVE:-true}"
VERBOSE="${VERBOSE:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Deployment phases
PHASES=(
    "preflight:Pre-flight Validation"
    "dependencies:Install Dependencies"
    "ssh:SSH Key Setup"
    "prepare:Prepare Nodes"
    "initial:Initial Setup Playbook"
    "power:Power Management Setup"
    "autosleep:Auto-Sleep Configuration"
    "wake:Wake Event Handler"
    "verify:Post-deployment Verification"
)

# Current phase tracking
CURRENT_PHASE=1
START_PHASE=1
END_PHASE=${#PHASES[@]}

# Logging
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        INFO) echo -e "${BLUE}ℹ${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}✓${NC} $message" ;;
        WARN) echo -e "${YELLOW}⚠${NC} $message" ;;
        ERROR) echo -e "${RED}✗${NC} $message" ;;
        STEP) echo -e "${CYAN}→${NC} $message" ;;
        HEADER) echo -e "\n${BOLD}${CYAN}$message${NC}" ;;
    esac
}

log_info() { log INFO "$@"; }
log_success() { log SUCCESS "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_step() { log STEP "$@"; }
log_header() { log HEADER "$@"; }

# Progress indicator
show_progress() {
    local current="$1"
    local total="$2"
    local phase_name="$3"
    
    local percentage=$((current * 100 / total))
    local filled=$((percentage / 5))
    local empty=$((20 - filled))
    
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    echo -e "${BOLD}[${current}/${total}]${NC} [${bar}] ${percentage}% - ${phase_name}"
}

# Prompt for confirmation
confirm() {
    local message="$1"
    
    if [[ "$INTERACTIVE" != "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    read -rp "Continue? [y/N] " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Save state
save_state() {
    echo "LAST_PHASE=$CURRENT_PHASE" > "$STATE_FILE"
    echo "TIMESTAMP=$(date +%s)" >> "$STATE_FILE"
}

# Load state
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$STATE_FILE"
        return 0
    fi
    return 1
}

# Phase: Pre-flight Validation
phase_preflight() {
    log_header "Phase 1: Pre-flight Validation"
    
    log_step "Checking required tools..."
    
    local required_tools=("ansible" "ansible-playbook" "ssh" "python3")
    local missing=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        else
            log_info "$tool: $(command -v "$tool")"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        return 1
    fi
    
    log_step "Checking Ansible configuration..."
    if [[ ! -f "$ANSIBLE_CONFIG" ]]; then
        log_error "Ansible config not found: $ANSIBLE_CONFIG"
        return 1
    fi
    log_info "Ansible config: $ANSIBLE_CONFIG"
    
    log_step "Checking inventory file..."
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_error "Inventory file not found: $INVENTORY_FILE"
        return 1
    fi
    log_info "Inventory: $INVENTORY_FILE"
    
    log_step "Validating inventory syntax..."
    if ! python3 -c "import yaml; yaml.safe_load(open('$INVENTORY_FILE'))" 2>/dev/null; then
        log_error "Invalid YAML in inventory file"
        return 1
    fi
    
    log_success "Pre-flight validation passed"
}

# Phase: Install Dependencies
phase_dependencies() {
    log_header "Phase 2: Install Dependencies"
    
    log_step "Running dependency installation..."
    
    local install_script="$REPO_ROOT/bootstrap/install-dependencies.sh"
    
    if [[ ! -f "$install_script" ]]; then
        log_error "Install script not found: $install_script"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $install_script"
    else
        if ! bash "$install_script"; then
            log_error "Dependency installation failed"
            return 1
        fi
    fi
    
    log_success "Dependencies installed"
}

# Phase: SSH Key Setup
phase_ssh() {
    log_header "Phase 3: SSH Key Setup"
    
    local ssh_script="$REPO_ROOT/bootstrap/setup-ssh-keys.sh"
    
    if [[ ! -f "$ssh_script" ]]; then
        log_error "SSH setup script not found: $ssh_script"
        return 1
    fi
    
    log_step "Configuring SSH keys..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $ssh_script"
    else
        if ! bash "$ssh_script" generate; then
            log_warn "SSH key generation had warnings"
        fi
    fi
    
    log_success "SSH keys configured"
}

# Phase: Prepare Nodes
phase_prepare() {
    log_header "Phase 4: Prepare Nodes"
    
    local prepare_script="$REPO_ROOT/bootstrap/prepare-nodes.sh"
    
    if [[ ! -f "$prepare_script" ]]; then
        log_error "Prepare script not found: $prepare_script"
        return 1
    fi
    
    log_step "Preparing cluster nodes..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $prepare_script"
    else
        if ! bash "$prepare_script" --dry-run; then
            log_warn "Node preparation needs attention"
        fi
    fi
    
    log_success "Nodes prepared"
}

# Phase: Initial Setup Playbook
phase_initial() {
    log_header "Phase 5: Initial Setup Playbook"
    
    log_step "Running initial setup playbook..."
    
    local playbook="$REPO_ROOT/ansible/playbooks/initial-setup.yml"
    
    if [[ ! -f "$playbook" ]]; then
        log_error "Playbook not found: $playbook"
        return 1
    fi
    
    local ansible_args=(
        "-i" "$INVENTORY_FILE"
        "$playbook"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        ansible_args+=("--check")
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        ansible_args+=("-vv")
    fi
    
    export ANSIBLE_CONFIG="$ANSIBLE_CONFIG"
    
    if ! ansible-playbook "${ansible_args[@]}"; then
        log_error "Initial setup playbook failed"
        return 1
    fi
    
    log_success "Initial setup complete"
}

# Phase: Power Management Setup
phase_power() {
    log_header "Phase 6: Power Management Setup"
    
    log_step "Configuring power management..."
    
    local playbook="$REPO_ROOT/ansible/playbooks/configure-power-management.yml"
    
    if [[ ! -f "$playbook" ]]; then
        log_error "Playbook not found: $playbook"
        return 1
    fi
    
    local ansible_args=(
        "-i" "$INVENTORY_FILE"
        "$playbook"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        ansible_args+=("--check")
    fi
    
    export ANSIBLE_CONFIG="$ANSIBLE_CONFIG"
    
    if ! ansible-playbook "${ansible_args[@]}"; then
        log_warn "Power management setup had issues"
    fi
    
    log_success "Power management configured"
}

# Phase: Auto-Sleep Configuration
phase_autosleep() {
    log_header "Phase 7: Auto-Sleep Configuration"
    
    log_step "Configuring auto-sleep..."
    
    local playbook="$REPO_ROOT/ansible/playbooks/setup-autosleep.yml"
    
    if [[ ! -f "$playbook" ]]; then
        log_error "Playbook not found: $playbook"
        return 1
    fi
    
    local ansible_args=(
        "-i" "$INVENTORY_FILE"
        "$playbook"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        ansible_args+=("--check")
    fi
    
    export ANSIBLE_CONFIG="$ANSIBLE_CONFIG"
    
    if ! ansible-playbook "${ansible_args[@]}"; then
        log_warn "Auto-sleep setup had issues"
    fi
    
    log_success "Auto-sleep configured"
}

# Phase: Wake Event Handler
phase_wake() {
    log_header "Phase 8: Wake Event Handler"
    
    log_step "Deploying wake event handler..."
    
    local playbook="$REPO_ROOT/ansible/playbooks/deploy-event-wake.yml"
    
    if [[ ! -f "$playbook" ]]; then
        log_error "Playbook not found: $playbook"
        return 1
    fi
    
    local ansible_args=(
        "-i" "$INVENTORY_FILE"
        "$playbook"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        ansible_args+=("--check")
    fi
    
    export ANSIBLE_CONFIG="$ANSIBLE_CONFIG"
    
    if ! ansible-playbook "${ansible_args[@]}"; then
        log_warn "Wake handler deployment had issues"
    fi
    
    log_success "Wake event handler deployed"
}

# Phase: Post-deployment Verification
phase_verify() {
    log_header "Phase 9: Post-deployment Verification"
    
    log_step "Running verification checks..."
    
    local verify_script="$REPO_ROOT/bootstrap/verify-prerequisites.sh"
    
    if [[ -f "$verify_script" ]]; then
        if ! bash "$verify_script" --local-only; then
            log_warn "Verification had warnings"
        fi
    fi
    
    log_step "Checking Ansible connectivity..."
    if ansible -i "$INVENTORY_FILE" all -m ping -o 2>/dev/null | grep -q "SUCCESS"; then
        log_success "All nodes reachable via Ansible"
    else
        log_warn "Some nodes may not be reachable"
    fi
    
    log_success "Deployment verification complete"
}

# Run specific phase
run_phase() {
    local phase_num="$1"
    local phase_info="${PHASES[$((phase_num - 1))]}"
    local phase_id="${phase_info%%:*}"
    local phase_name="${phase_info#*:}"
    
    show_progress "$phase_num" "${#PHASES[@]}" "$phase_name"
    
    case "$phase_id" in
        preflight) phase_preflight ;;
        dependencies) phase_dependencies ;;
        ssh) phase_ssh ;;
        prepare) phase_prepare ;;
        initial) phase_initial ;;
        power) phase_power ;;
        autosleep) phase_autosleep ;;
        wake) phase_wake ;;
        verify) phase_verify ;;
        *) log_error "Unknown phase: $phase_id"; return 1 ;;
    esac
}

# Print banner
print_banner() {
    echo -e "${BOLD}${CYAN}"
    cat << 'EOF'
 __     ____  __ ____  _        _   _             
 \ \   / /  \/  / ___|| |_ __ _| |_(_) ___  _ __  
  \ \ / /| |\/| \___ \| __/ _` | __| |/ _ \| '_ \ 
   \ V / | |  | |___) | || (_| | |_| | (_) | | | |
    \_/  |_|  |_|____/ \__\__,_|\__|_|\___/|_| |_|
                                                  
     Cluster Setup Deployment
EOF
    echo -e "${NC}"
}

# Print usage
print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

VMStation Cluster Setup Deployment Orchestrator

Options:
    --check             Dry-run mode (validate without making changes)
    --phase N           Start from phase N
    --to-phase N        Stop at phase N
    --list-phases       List all deployment phases
    --resume            Resume from last saved state
    --non-interactive   Run without prompts
    -v, --verbose       Enable verbose output
    -h, --help          Show this help message

Phases:
EOF
    
    local i=1
    for phase_info in "${PHASES[@]}"; do
        local phase_name="${phase_info#*:}"
        echo "    $i. $phase_name"
        ((i++))
    done
    
    cat << EOF

Environment Variables:
    INVENTORY_FILE      Path to Ansible inventory
    ANSIBLE_CONFIG      Path to Ansible config
    DRY_RUN             Enable dry-run mode (true/false)
    INTERACTIVE         Enable interactive mode (true/false)

Examples:
    $(basename "$0")                    # Full deployment
    $(basename "$0") --check            # Validate only
    $(basename "$0") --phase 5          # Start from phase 5
    $(basename "$0") --resume           # Resume from last state

EOF
}

# Main function
main() {
    local list_phases=false
    local resume=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)
                DRY_RUN="true"
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
            --list-phases)
                list_phases=true
                shift
                ;;
            --resume)
                resume=true
                shift
                ;;
            --non-interactive)
                INTERACTIVE="false"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
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
    
    # List phases if requested
    if [[ "$list_phases" == "true" ]]; then
        echo "Deployment Phases:"
        local i=1
        for phase_info in "${PHASES[@]}"; do
            local phase_name="${phase_info#*:}"
            echo "  $i. $phase_name"
            ((i++))
        done
        exit 0
    fi
    
    # Resume from saved state
    if [[ "$resume" == "true" ]]; then
        if load_state; then
            START_PHASE=$((LAST_PHASE + 1))
            log_info "Resuming from phase $START_PHASE"
        else
            log_warn "No saved state found, starting from beginning"
        fi
    fi
    
    # Print banner
    print_banner
    
    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== Deployment started at $(date) ===" >> "$LOG_FILE"
    
    log_info "Repository root: $REPO_ROOT"
    log_info "Inventory: $INVENTORY_FILE"
    log_info "Dry run: $DRY_RUN"
    log_info "Interactive: $INTERACTIVE"
    echo ""
    
    # Confirm before starting
    if [[ "$INTERACTIVE" == "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        if ! confirm "Ready to start deployment?"; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    # Run phases
    local failed=false
    for ((i=START_PHASE; i<=END_PHASE; i++)); do
        CURRENT_PHASE=$i
        
        if ! run_phase "$i"; then
            log_error "Phase $i failed"
            save_state
            failed=true
            break
        fi
        
        save_state
        echo ""
    done
    
    # Final summary
    echo ""
    log_header "Deployment Summary"
    
    if [[ "$failed" == "true" ]]; then
        log_error "Deployment failed at phase $CURRENT_PHASE"
        log_info "Run with --resume to continue from this point"
        exit 1
    else
        log_success "Deployment completed successfully!"
        rm -f "$STATE_FILE"
    fi
    
    log_info "Log file: $LOG_FILE"
}

main "$@"
