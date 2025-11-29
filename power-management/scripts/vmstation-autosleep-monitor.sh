#!/bin/bash
# vmstation-autosleep-monitor.sh - Monitor node activity and initiate sleep when idle
# Part of VMStation Power Management
#
# This script monitors various activity indicators and puts the node to sleep
# when it has been idle for a configured period.
#
# Features:
# - Pod activity detection
# - CPU usage monitoring
# - Network activity monitoring
# - SSH session detection
# - Configurable timeouts and thresholds
# - Grace period before sleep
# - Pre-sleep hooks
# - Notification support

set -euo pipefail

# Configuration paths
CONFIG_FILE="${CONFIG_FILE:-/etc/vmstation/autosleep/autosleep.conf}"
STATE_FILE="${STATE_FILE:-/var/lib/vmstation/autosleep/state}"
LOG_FILE="${LOG_FILE:-/var/log/vmstation/autosleep.log}"
HOOKS_DIR="${HOOKS_DIR:-/opt/vmstation/autosleep/pre-sleep.d}"

# Default configuration (can be overridden by config file)
INACTIVITY_TIMEOUT_MINUTES="${INACTIVITY_TIMEOUT_MINUTES:-120}"
CHECK_INTERVAL_MINUTES="${CHECK_INTERVAL_MINUTES:-5}"
GRACE_PERIOD_MINUTES="${GRACE_PERIOD_MINUTES:-10}"
CPU_THRESHOLD_PERCENT="${CPU_THRESHOLD_PERCENT:-10}"
NETWORK_THRESHOLD_BYTES="${NETWORK_THRESHOLD_BYTES:-1024}"
NETWORK_INTERFACE="${NETWORK_INTERFACE:-eth0}"

# Notification settings
NOTIFICATION_ENABLED="${NOTIFICATION_ENABLED:-false}"
NOTIFICATION_WEBHOOK_URL="${NOTIFICATION_WEBHOOK_URL:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date -Iseconds)
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        case "$level" in
            INFO) echo -e "${BLUE}[$level]${NC} $message" ;;
            WARN) echo -e "${YELLOW}[$level]${NC} $message" ;;
            ERROR) echo -e "${RED}[$level]${NC} $message" ;;
            *) echo "[$level] $message" ;;
        esac
    fi
}

log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }

# Load configuration from file
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from $CONFIG_FILE"
        
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            
            # Remove leading/trailing whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            
            case "$key" in
                inactivity_timeout_minutes) INACTIVITY_TIMEOUT_MINUTES="$value" ;;
                check_interval_minutes) CHECK_INTERVAL_MINUTES="$value" ;;
                grace_period_minutes) GRACE_PERIOD_MINUTES="$value" ;;
                cpu_threshold_percent) CPU_THRESHOLD_PERCENT="$value" ;;
                network_threshold_bytes) NETWORK_THRESHOLD_BYTES="$value" ;;
                network_interface) NETWORK_INTERFACE="$value" ;;
                notification_enabled) NOTIFICATION_ENABLED="$value" ;;
                notification_webhook_url) NOTIFICATION_WEBHOOK_URL="$value" ;;
            esac
        done < <(grep -v '^\[' "$CONFIG_FILE" 2>/dev/null || true)
    fi
}

# Initialize state file
init_state() {
    local state_dir
    state_dir=$(dirname "$STATE_FILE")
    
    mkdir -p "$state_dir"
    
    if [[ ! -f "$STATE_FILE" ]]; then
        cat > "$STATE_FILE" << EOF
LAST_ACTIVITY=$(date +%s)
SLEEP_PENDING=false
SLEEP_ENABLED=true
LAST_CHECK=$(date +%s)
EOF
        log_info "Initialized state file at $STATE_FILE"
    fi
}

# Load state
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$STATE_FILE"
    else
        LAST_ACTIVITY=$(date +%s)
        SLEEP_PENDING=false
        SLEEP_ENABLED=true
    fi
}

# Save state
save_state() {
    cat > "$STATE_FILE" << EOF
LAST_ACTIVITY=$LAST_ACTIVITY
SLEEP_PENDING=$SLEEP_PENDING
SLEEP_ENABLED=$SLEEP_ENABLED
LAST_CHECK=$(date +%s)
EOF
}

# Update activity timestamp
update_activity() {
    LAST_ACTIVITY=$(date +%s)
    SLEEP_PENDING=false
    save_state
    log_info "Activity detected, reset idle timer"
}

# Check for running Kubernetes pods (excluding system namespaces)
check_pods() {
    if ! command -v kubectl &>/dev/null; then
        log_warn "kubectl not available, skipping pod check"
        return 1  # Assume activity if we can't check
    fi
    
    # Check if we can reach the API server
    if ! kubectl cluster-info &>/dev/null; then
        log_warn "Cannot reach Kubernetes API, skipping pod check"
        return 1
    fi
    
    local excluded_namespaces="kube-system kube-public kube-node-lease monitoring"
    local running_pods=0
    
    # Get pods and filter out system namespaces
    while IFS= read -r line; do
        local ns
        ns=$(echo "$line" | awk '{print $1}')
        
        local is_excluded=false
        for excluded in $excluded_namespaces; do
            if [[ "$ns" == "$excluded" ]]; then
                is_excluded=true
                break
            fi
        done
        
        if [[ "$is_excluded" == "false" ]]; then
            ((running_pods++))
        fi
    done < <(kubectl get pods --all-namespaces --field-selector=status.phase=Running -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name --no-headers 2>/dev/null || true)
    
    if [[ $running_pods -gt 0 ]]; then
        log_info "Found $running_pods running user pods"
        return 0  # Activity detected
    fi
    
    return 1  # No activity
}

# Check CPU usage
check_cpu() {
    local cpu_usage
    
    # Get CPU idle percentage and calculate usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | cut -d'.' -f1 2>/dev/null || echo "0")
    
    if [[ "$cpu_usage" -gt "$CPU_THRESHOLD_PERCENT" ]]; then
        log_info "CPU usage ${cpu_usage}% exceeds threshold ${CPU_THRESHOLD_PERCENT}%"
        return 0  # Activity detected
    fi
    
    return 1  # No activity
}

# Check network activity
check_network() {
    local interface="$NETWORK_INTERFACE"
    local stats_rx="/sys/class/net/${interface}/statistics/rx_bytes"
    local stats_tx="/sys/class/net/${interface}/statistics/tx_bytes"
    
    if [[ ! -f "$stats_rx" ]] || [[ ! -f "$stats_tx" ]]; then
        log_warn "Network interface $interface not found"
        return 1
    fi
    
    local rx_bytes_1 tx_bytes_1
    rx_bytes_1=$(cat "$stats_rx")
    tx_bytes_1=$(cat "$stats_tx")
    
    sleep 1
    
    local rx_bytes_2 tx_bytes_2
    rx_bytes_2=$(cat "$stats_rx")
    tx_bytes_2=$(cat "$stats_tx")
    
    local total_bytes
    total_bytes=$(( (rx_bytes_2 - rx_bytes_1) + (tx_bytes_2 - tx_bytes_1) ))
    
    if [[ $total_bytes -gt $NETWORK_THRESHOLD_BYTES ]]; then
        log_info "Network activity ${total_bytes} bytes/sec exceeds threshold"
        return 0  # Activity detected
    fi
    
    return 1  # No activity
}

# Check for active SSH sessions
check_ssh() {
    local ssh_sessions
    ssh_sessions=$(who | grep -c 'pts/' 2>/dev/null || echo "0")
    
    if [[ $ssh_sessions -gt 0 ]]; then
        log_info "Found $ssh_sessions active SSH sessions"
        return 0  # Activity detected
    fi
    
    return 1  # No activity
}

# Check all activity indicators
check_activity() {
    # Any activity indicator returning 0 means activity detected
    check_pods && return 0
    check_cpu && return 0
    check_network && return 0
    check_ssh && return 0
    
    return 1  # No activity detected
}

# Send notification
send_notification() {
    local message="$1"
    
    log_info "Notification: $message"
    
    if [[ "$NOTIFICATION_ENABLED" == "true" ]] && [[ -n "$NOTIFICATION_WEBHOOK_URL" ]]; then
        local hostname
        hostname=$(hostname)
        
        curl -s -X POST "$NOTIFICATION_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{
                \"text\": \"$message\",
                \"node\": \"$hostname\",
                \"timestamp\": \"$(date -Iseconds)\"
            }" &>/dev/null || log_warn "Failed to send notification"
    fi
}

# Run pre-sleep hooks
run_pre_sleep_hooks() {
    if [[ -d "$HOOKS_DIR" ]]; then
        log_info "Running pre-sleep hooks..."
        
        for script in "$HOOKS_DIR"/*; do
            if [[ -x "$script" ]]; then
                log_info "Executing hook: $script"
                if ! "$script"; then
                    log_warn "Hook failed: $script"
                fi
            fi
        done
    fi
}

# Initiate sleep
initiate_sleep() {
    local hostname
    hostname=$(hostname)
    
    log_info "Initiating sleep sequence for $hostname"
    
    # Send notification
    send_notification "$hostname is going to sleep due to inactivity"
    
    # Run pre-sleep hooks
    run_pre_sleep_hooks
    
    # Sync filesystems
    log_info "Syncing filesystems..."
    sync
    
    # Actually suspend
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

# Main monitoring loop
run_monitor() {
    log_info "Starting VMStation auto-sleep monitor"
    log_info "Configuration:"
    log_info "  Inactivity timeout: ${INACTIVITY_TIMEOUT_MINUTES} minutes"
    log_info "  Check interval: ${CHECK_INTERVAL_MINUTES} minutes"
    log_info "  Grace period: ${GRACE_PERIOD_MINUTES} minutes"
    log_info "  CPU threshold: ${CPU_THRESHOLD_PERCENT}%"
    log_info "  Network threshold: ${NETWORK_THRESHOLD_BYTES} bytes/sec"
    
    init_state
    
    while true; do
        load_state
        
        # Check if sleep is enabled
        if [[ "${SLEEP_ENABLED:-true}" != "true" ]]; then
            log_info "Auto-sleep disabled, skipping check"
            sleep $((CHECK_INTERVAL_MINUTES * 60))
            continue
        fi
        
        # Check for activity
        if check_activity; then
            update_activity
        else
            local current_time
            current_time=$(date +%s)
            
            local idle_seconds=$((current_time - LAST_ACTIVITY))
            local idle_minutes=$((idle_seconds / 60))
            local timeout_seconds=$((INACTIVITY_TIMEOUT_MINUTES * 60))
            local grace_seconds=$((GRACE_PERIOD_MINUTES * 60))
            
            log_info "Node idle for ${idle_minutes} minutes (timeout: ${INACTIVITY_TIMEOUT_MINUTES} minutes)"
            
            if [[ $idle_seconds -ge $timeout_seconds ]]; then
                if [[ "$SLEEP_PENDING" != "true" ]]; then
                    SLEEP_PENDING=true
                    save_state
                    
                    send_notification "$(hostname) will sleep in ${GRACE_PERIOD_MINUTES} minutes due to inactivity"
                    log_info "Sleep pending, grace period started"
                elif [[ $idle_seconds -ge $((timeout_seconds + grace_seconds)) ]]; then
                    initiate_sleep
                fi
            fi
        fi
        
        save_state
        sleep $((CHECK_INTERVAL_MINUTES * 60))
    done
}

# Handle signals
cleanup() {
    log_info "Received signal, shutting down..."
    exit 0
}

trap cleanup SIGTERM SIGINT

# Print usage
print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [COMMAND]

VMStation Auto-Sleep Monitor

Commands:
    start       Start the monitoring daemon (default)
    check       Run a single activity check
    status      Show current state
    enable      Enable auto-sleep
    disable     Disable auto-sleep
    reset       Reset activity timer

Options:
    -c, --config FILE   Configuration file path
    -v, --verbose       Enable verbose output
    -h, --help          Show this help message

Environment Variables:
    CONFIG_FILE                 Configuration file path
    STATE_FILE                  State file path
    LOG_FILE                    Log file path
    INACTIVITY_TIMEOUT_MINUTES  Timeout before sleep (default: 120)
    CHECK_INTERVAL_MINUTES      Check interval (default: 5)
    GRACE_PERIOD_MINUTES        Grace period before sleep (default: 10)

EOF
}

# Main function
main() {
    local command="start"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            start|check|status|enable|disable|reset)
                command="$1"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Load configuration
    load_config
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    
    case "$command" in
        start)
            run_monitor
            ;;
        check)
            init_state
            if check_activity; then
                echo "Activity detected"
                exit 0
            else
                echo "No activity detected"
                exit 1
            fi
            ;;
        status)
            init_state
            load_state
            echo "Sleep enabled: ${SLEEP_ENABLED:-unknown}"
            echo "Sleep pending: ${SLEEP_PENDING:-unknown}"
            echo "Last activity: $(date -d "@${LAST_ACTIVITY:-0}" 2>/dev/null || echo "unknown")"
            ;;
        enable)
            init_state
            load_state
            SLEEP_ENABLED=true
            save_state
            echo "Auto-sleep enabled"
            ;;
        disable)
            init_state
            load_state
            SLEEP_ENABLED=false
            save_state
            echo "Auto-sleep disabled"
            ;;
        reset)
            init_state
            update_activity
            echo "Activity timer reset"
            ;;
    esac
}

main "$@"
