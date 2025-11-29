#!/bin/bash
# vmstation-sleep.sh - Gracefully put a node to sleep
# Part of VMStation Power Management
#
# This script performs a graceful sleep sequence:
# - Run pre-sleep checks
# - Notify cluster of impending sleep
# - Drain workloads if Kubernetes node
# - Run pre-sleep hooks
# - Sync filesystems
# - Suspend to RAM
#
# Usage:
#   vmstation-sleep.sh              # Normal sleep
#   vmstation-sleep.sh --force      # Force sleep without checks
#   vmstation-sleep.sh --check      # Check if safe to sleep

set -euo pipefail

# Configuration
HOOKS_DIR="${HOOKS_DIR:-/opt/vmstation/power/pre-sleep.d}"
STATE_DIR="${STATE_DIR:-/var/lib/vmstation/power}"
LOG_FILE="${LOG_FILE:-/var/log/vmstation/power.log}"
CONFIG_FILE="${CONFIG_FILE:-/etc/vmstation/power/power.conf}"

# Timeouts
DRAIN_TIMEOUT="${DRAIN_TIMEOUT:-120}"
NOTIFICATION_TIMEOUT="${NOTIFICATION_TIMEOUT:-10}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date -Iseconds)
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        INFO) echo -e "${BLUE}[INFO]${NC} $message" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        *) echo "[$level] $message" ;;
    esac
}

log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_success() { log SUCCESS "$@"; }

# Ensure directories exist
ensure_directories() {
    mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"
}

# Check if it's safe to sleep
check_safe_to_sleep() {
    log_info "Checking if safe to sleep..."
    
    local hostname
    hostname=$(hostname)
    
    # Check for active SSH sessions
    local ssh_sessions
    ssh_sessions=$(who | grep -c 'pts/' 2>/dev/null || echo "0")
    if [[ $ssh_sessions -gt 0 ]]; then
        log_warn "There are $ssh_sessions active SSH sessions"
        return 1
    fi
    
    # Check if this is a Kubernetes master node
    if kubectl get nodes "$hostname" &>/dev/null; then
        local node_roles
        node_roles=$(kubectl get node "$hostname" -o jsonpath='{.metadata.labels.node-role\.kubernetes\.io/control-plane}' 2>/dev/null || echo "")
        
        if [[ -n "$node_roles" ]]; then
            log_warn "This is a control-plane node - sleeping may affect cluster availability"
            # Check if there are other control-plane nodes
            local master_count
            master_count=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o name 2>/dev/null | wc -l)
            if [[ $master_count -le 1 ]]; then
                log_error "This is the only control-plane node - cannot sleep"
                return 1
            fi
        fi
    fi
    
    # Check for pods with prevent-sleep label
    if command -v kubectl &>/dev/null; then
        local prevent_sleep_pods
        prevent_sleep_pods=$(kubectl get pods --all-namespaces -l vmstation.io/prevent-sleep=true -o name 2>/dev/null | wc -l || echo "0")
        if [[ $prevent_sleep_pods -gt 0 ]]; then
            log_warn "There are $prevent_sleep_pods pods with prevent-sleep label"
            return 1
        fi
    fi
    
    log_success "Safe to sleep"
    return 0
}

# Cordon and drain node if Kubernetes
drain_kubernetes_node() {
    local hostname
    hostname=$(hostname)
    
    if ! command -v kubectl &>/dev/null; then
        log_info "kubectl not available, skipping drain"
        return 0
    fi
    
    if ! kubectl get nodes "$hostname" &>/dev/null; then
        log_info "Node not part of Kubernetes cluster, skipping drain"
        return 0
    fi
    
    log_info "Cordoning node $hostname..."
    if ! kubectl cordon "$hostname" 2>/dev/null; then
        log_warn "Failed to cordon node"
    fi
    
    log_info "Draining node $hostname (timeout: ${DRAIN_TIMEOUT}s)..."
    if ! kubectl drain "$hostname" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --timeout="${DRAIN_TIMEOUT}s" \
        --grace-period=30 \
        --force 2>/dev/null; then
        log_warn "Drain completed with warnings"
    fi
    
    log_success "Node drained"
}

# Run pre-sleep hooks
run_pre_sleep_hooks() {
    if [[ ! -d "$HOOKS_DIR" ]]; then
        log_info "No pre-sleep hooks directory found"
        return 0
    fi
    
    log_info "Running pre-sleep hooks..."
    
    for hook in "$HOOKS_DIR"/*; do
        if [[ -x "$hook" ]]; then
            local hook_name
            hook_name=$(basename "$hook")
            log_info "Running hook: $hook_name"
            
            if ! "$hook"; then
                log_warn "Hook $hook_name failed"
            fi
        fi
    done
    
    log_success "Pre-sleep hooks completed"
}

# Notify cluster of sleep
notify_sleep() {
    local hostname
    hostname=$(hostname)
    
    log_info "Notifying cluster of impending sleep..."
    
    # Update state file
    cat > "$STATE_DIR/state" << EOF
STATE=sleeping
SLEEP_TIME=$(date +%s)
SLEEP_DATE=$(date -Iseconds)
HOSTNAME=$hostname
EOF
    
    # Try to notify via webhook if configured
    if [[ -f "$CONFIG_FILE" ]]; then
        local webhook_url
        webhook_url=$(grep -oP 'notification_webhook_url=\K.*' "$CONFIG_FILE" 2>/dev/null || echo "")
        
        if [[ -n "$webhook_url" ]]; then
            curl -s -X POST "$webhook_url" \
                --max-time "$NOTIFICATION_TIMEOUT" \
                -H "Content-Type: application/json" \
                -d "{
                    \"event\": \"node_sleeping\",
                    \"node\": \"$hostname\",
                    \"timestamp\": \"$(date -Iseconds)\"
                }" &>/dev/null || log_warn "Failed to send notification"
        fi
    fi
}

# Perform sleep
do_sleep() {
    log_info "Syncing filesystems..."
    sync
    
    log_info "Suspending to RAM..."
    
    if command -v systemctl &>/dev/null; then
        systemctl suspend
    elif [[ -f /sys/power/state ]]; then
        echo mem > /sys/power/state
    else
        log_error "No suspend mechanism available"
        return 1
    fi
}

# Handle wake-up
on_wakeup() {
    local hostname
    hostname=$(hostname)
    
    log_info "System waking up..."
    
    # Update state
    cat > "$STATE_DIR/state" << EOF
STATE=running
WAKE_TIME=$(date +%s)
WAKE_DATE=$(date -Iseconds)
HOSTNAME=$hostname
EOF
    
    # Uncordon if Kubernetes node
    if command -v kubectl &>/dev/null; then
        if kubectl get nodes "$hostname" &>/dev/null; then
            log_info "Uncordoning node..."
            kubectl uncordon "$hostname" 2>/dev/null || log_warn "Failed to uncordon"
        fi
    fi
    
    # Notify cluster
    if [[ -f "$CONFIG_FILE" ]]; then
        local webhook_url
        webhook_url=$(grep -oP 'notification_webhook_url=\K.*' "$CONFIG_FILE" 2>/dev/null || echo "")
        
        if [[ -n "$webhook_url" ]]; then
            curl -s -X POST "$webhook_url" \
                --max-time "$NOTIFICATION_TIMEOUT" \
                -H "Content-Type: application/json" \
                -d "{
                    \"event\": \"node_awake\",
                    \"node\": \"$hostname\",
                    \"timestamp\": \"$(date -Iseconds)\"
                }" &>/dev/null || true
        fi
    fi
    
    log_success "Wake-up complete"
}

# Print usage
print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Gracefully put a VMStation node to sleep.

Options:
    --force         Force sleep without safety checks
    --check         Only check if safe to sleep, don't actually sleep
    --no-drain      Skip Kubernetes node drain
    --no-hooks      Skip pre-sleep hooks
    --wakeup        Handle wake-up sequence (called after resume)
    -h, --help      Show this help message

Environment Variables:
    DRAIN_TIMEOUT              Kubernetes drain timeout (default: 120)
    HOOKS_DIR                  Pre-sleep hooks directory
    STATE_DIR                  State directory

Examples:
    $(basename "$0")           # Normal graceful sleep
    $(basename "$0") --force   # Force sleep
    $(basename "$0") --check   # Check if safe to sleep

EOF
}

# Main function
main() {
    local force=false
    local check_only=false
    local do_drain=true
    local do_hooks=true
    local wakeup_mode=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true
                shift
                ;;
            --check)
                check_only=true
                shift
                ;;
            --no-drain)
                do_drain=false
                shift
                ;;
            --no-hooks)
                do_hooks=false
                shift
                ;;
            --wakeup)
                wakeup_mode=true
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
    
    ensure_directories
    
    # Handle wake-up mode
    if [[ "$wakeup_mode" == "true" ]]; then
        on_wakeup
        exit 0
    fi
    
    log_info "VMStation Sleep Sequence"
    log_info "========================"
    
    # Safety checks
    if [[ "$force" != "true" ]]; then
        if ! check_safe_to_sleep; then
            if [[ "$check_only" == "true" ]]; then
                exit 1
            fi
            log_error "Not safe to sleep. Use --force to override."
            exit 1
        fi
    else
        log_warn "Force mode enabled, skipping safety checks"
    fi
    
    # Exit if check only
    if [[ "$check_only" == "true" ]]; then
        exit 0
    fi
    
    # Drain Kubernetes node
    if [[ "$do_drain" == "true" ]]; then
        drain_kubernetes_node
    fi
    
    # Run pre-sleep hooks
    if [[ "$do_hooks" == "true" ]]; then
        run_pre_sleep_hooks
    fi
    
    # Notify cluster
    notify_sleep
    
    # Perform sleep
    if do_sleep; then
        # This runs after wake-up
        on_wakeup
    else
        log_error "Sleep failed"
        exit 1
    fi
}

main "$@"
