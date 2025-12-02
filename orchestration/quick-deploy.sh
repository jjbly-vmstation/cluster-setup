#!/bin/bash
# quick-deploy.sh - Quick deployment helper for common operations
# Part of VMStation Cluster Setup
#
# This script provides shortcuts for common deployment tasks.
#
# Usage:
#   ./quick-deploy.sh setup       # Initial setup
#   ./quick-deploy.sh power       # Configure power management
#   ./quick-deploy.sh wake        # Deploy wake handler

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
INVENTORY_FILE="/srv/vmstation-org/cluster-setup/ansible/inventory/hosts.yml}"
ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Available quick commands
declare -A COMMANDS=(
    [setup]="ansible/playbooks/initial-setup.yml"
    [power]="ansible/playbooks/configure-power-management.yml"
    [autosleep]="ansible/playbooks/setup-autosleep.yml"
    [wake]="ansible/playbooks/deploy-event-wake.yml"
    [wol]="power-management/playbooks/setup-wake-on-lan.yml"
    [spindown]="power-management/playbooks/spin-down-cluster.yml"
)

# Print header
print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════╗"
    echo "║     VMStation Quick Deploy             ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Run Ansible playbook
run_playbook() {
    local playbook="$1"
    shift
    local extra_args=("$@")
    
    local full_path="$REPO_ROOT/$playbook"
    
    if [[ ! -f "$full_path" ]]; then
        echo -e "${RED}Error: Playbook not found: $full_path${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Running: $playbook${NC}"
    echo ""
    
    export ANSIBLE_CONFIG
    ansible-playbook -i "$INVENTORY_FILE" "$full_path" "${extra_args[@]}"
}

# Print usage
print_usage() {
    cat << EOF
${BOLD}Usage:${NC} $(basename "$0") <command> [options]

${BOLD}Commands:${NC}
    setup       Run initial cluster setup
    power       Configure power management
    autosleep   Setup auto-sleep monitoring
    wake        Deploy wake event handler
    wol         Setup Wake-on-LAN
    spindown    Spin down the cluster

    list        List available playbooks
    ping        Test connectivity to all nodes
    check       Run syntax check on playbooks

${BOLD}Options:${NC}
    --check     Dry-run mode (validate without changes)
    --verbose   Enable verbose output
    --tags TAGS Only run specific tags
    --limit     Limit to specific hosts/groups

${BOLD}Examples:${NC}
    $(basename "$0") setup                    # Full initial setup
    $(basename "$0") power --check            # Dry-run power config
    $(basename "$0") setup --tags packages    # Only install packages
    $(basename "$0") spindown                 # Shutdown cluster

EOF
}

# List available playbooks
list_playbooks() {
    echo -e "${BOLD}Available Playbooks:${NC}"
    echo ""
    
    for cmd in "${!COMMANDS[@]}"; do
        local playbook="${COMMANDS[$cmd]}"
        if [[ -f "$REPO_ROOT/$playbook" ]]; then
            echo -e "  ${GREEN}✓${NC} ${BOLD}$cmd${NC}"
            echo "    $playbook"
        else
            echo -e "  ${RED}✗${NC} ${BOLD}$cmd${NC} (missing)"
        fi
    done
    echo ""
}

# Test connectivity
test_ping() {
    echo -e "${BLUE}Testing connectivity to all nodes...${NC}"
    echo ""
    
    export ANSIBLE_CONFIG
    ansible -i "$INVENTORY_FILE" all -m ping -o
}

# Check playbook syntax
check_syntax() {
    echo -e "${BLUE}Checking playbook syntax...${NC}"
    echo ""
    
    local errors=0
    
    for playbook in "$REPO_ROOT"/ansible/playbooks/*.yml "$REPO_ROOT"/power-management/playbooks/*.yml; do
        if [[ -f "$playbook" ]]; then
            local name
            name=$(basename "$playbook")
            
            if ansible-playbook --syntax-check -i "$INVENTORY_FILE" "$playbook" &>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $name"
            else
                echo -e "  ${RED}✗${NC} $name"
                ((errors++))
            fi
        fi
    done
    
    echo ""
    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}$errors playbook(s) have syntax errors${NC}"
        exit 1
    else
        echo -e "${GREEN}All playbooks have valid syntax${NC}"
    fi
}

# Main function
main() {
    if [[ $# -lt 1 ]]; then
        print_header
        print_usage
        exit 0
    fi
    
    local command="$1"
    shift
    
    # Parse remaining arguments for ansible
    local ansible_args=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)
                ansible_args+=("--check")
                shift
                ;;
            --verbose|-v)
                ansible_args+=("-vv")
                shift
                ;;
            --tags)
                ansible_args+=("--tags" "$2")
                shift 2
                ;;
            --limit)
                ansible_args+=("--limit" "$2")
                shift 2
                ;;
            *)
                ansible_args+=("$1")
                shift
                ;;
        esac
    done
    
    case "$command" in
        list)
            print_header
            list_playbooks
            ;;
        ping)
            test_ping
            ;;
        check)
            check_syntax
            ;;
        help|-h|--help)
            print_header
            print_usage
            ;;
        *)
            if [[ -v "COMMANDS[$command]" ]]; then
                run_playbook "${COMMANDS[$command]}" "${ansible_args[@]}"
            else
                echo -e "${RED}Unknown command: $command${NC}"
                echo ""
                print_usage
                exit 1
            fi
            ;;
    esac
}

main "$@"
