#!/bin/bash
# vmstation-wake.sh - Wake cluster nodes using Wake-on-LAN
# Part of VMStation Power Management
#
# This script sends Wake-on-LAN magic packets to wake up cluster nodes.
#
# Features:
# - Wake individual nodes or all nodes
# - Wake verification with retry
# - Support for multiple WoL tools
# - Cluster-aware wake order
# - Wake status reporting
#
# Usage:
#   vmstation-wake.sh <node>           # Wake specific node
#   vmstation-wake.sh --all            # Wake all nodes
#   vmstation-wake.sh --workers        # Wake all worker nodes

set -euo pipefail

# Configuration
WOL_REGISTRY="${WOL_REGISTRY:-/etc/vmstation/wol-registry.conf}"
CONFIG_DIR="${CONFIG_DIR:-/etc/vmstation/wol}"
LOG_FILE="${LOG_FILE:-/var/log/vmstation/wake.log}"

# Wake settings
RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_DELAY="${RETRY_DELAY:-10}"
VERIFICATION_TIMEOUT="${VERIFICATION_TIMEOUT:-120}"
WAKE_INTERVAL="${WAKE_INTERVAL:-5}"

# Inventory file for group-based wake
INVENTORY_FILE="${INVENTORY_FILE:-/etc/vmstation/inventory.yml}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date -Iseconds)
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    
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

# Find WoL tool
find_wol_tool() {
    if command -v wakeonlan &>/dev/null; then
        echo "wakeonlan"
    elif command -v etherwake &>/dev/null; then
        echo "etherwake"
    elif command -v wol &>/dev/null; then
        echo "wol"
    else
        log_error "No Wake-on-LAN tool found (wakeonlan, etherwake, or wol)"
        return 1
    fi
}

# Send WoL magic packet
send_magic_packet() {
    local mac="$1"
    local tool
    tool=$(find_wol_tool)
    
    case "$tool" in
        wakeonlan)
            wakeonlan "$mac"
            ;;
        etherwake)
            etherwake "$mac"
            ;;
        wol)
            wol "$mac"
            ;;
    esac
}

# Get node info from registry or config
get_node_info() {
    local hostname="$1"
    local mac=""
    local ip=""

    # Try node-specific config first
    if [[ -f "$CONFIG_DIR/${hostname}.conf" ]]; then
        mac=$(awk -F= '/^MAC_ADDRESS=/ {print $2}' "$CONFIG_DIR/${hostname}.conf" 2>/dev/null || echo "")
        ip=$(awk -F= '/^IP_ADDRESS=/ {print $2}' "$CONFIG_DIR/${hostname}.conf" 2>/dev/null || echo "")
    fi

    # Try registry file
    if [[ -z "$mac" ]] && [[ -f "$WOL_REGISTRY" ]]; then
        local line
        line=$(grep "^${hostname}|" "$WOL_REGISTRY" 2>/dev/null || echo "")
        if [[ -n "$line" ]]; then
            ip=$(echo "$line" | cut -d'|' -f2)
            mac=$(echo "$line" | cut -d'|' -f3)
        fi
    fi

    # Output as "mac ip"
    echo "$mac $ip"
}

# Get all nodes from registry
get_all_nodes() {
    if [[ -f "$WOL_REGISTRY" ]]; then
        grep -v '^#' "$WOL_REGISTRY" | grep -v '^$' | cut -d'|' -f1
    else
        # Try to list config files
        if [[ -d "$CONFIG_DIR" ]]; then
            for config in "$CONFIG_DIR"/*.conf; do
                if [[ -f "$config" ]]; then
                    grep -oP 'HOSTNAME=\K.*' "$config" 2>/dev/null || true
                fi
            done
        fi
    fi
}

# Verify node is awake
verify_node_awake() {
    local ip="$1"
    local timeout="${2:-$VERIFICATION_TIMEOUT}"
    local start_time
    start_time=$(date +%s)
    
    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -ge $timeout ]]; then
            return 1
        fi
        
        if ping -c 1 -W 2 "$ip" &>/dev/null; then
            return 0
        fi
        
        sleep 5
    done
}

# Wake single node with retry
wake_node() {
    local hostname="$1"
    local verify="${2:-false}"
    
    log_info "Waking node: $hostname"
    
    local node_info
    node_info=$(get_node_info "$hostname")
    
    local mac ip
    mac=$(echo "$node_info" | awk '{print $1}')
    ip=$(echo "$node_info" | awk '{print $2}')
    
    if [[ -z "$mac" ]]; then
        log_error "No MAC address found for $hostname"
        return 1
    fi
    
    log_info "MAC: $mac, IP: $ip"
    
    # Send wake packets with retry
    local attempt=1
    while [[ $attempt -le $RETRY_COUNT ]]; do
        log_info "Sending wake packet (attempt $attempt/$RETRY_COUNT)..."
        
        if send_magic_packet "$mac"; then
            log_info "Wake packet sent successfully"
        else
            log_warn "Failed to send wake packet"
        fi
        
        if [[ "$verify" == "true" ]] && [[ -n "$ip" ]]; then
            log_info "Waiting for node to respond..."
            sleep $RETRY_DELAY
            
            if ping -c 1 -W 5 "$ip" &>/dev/null; then
                log_success "$hostname is awake and responding"
                return 0
            fi
        else
            # Just send packet and return
            if [[ $attempt -lt $RETRY_COUNT ]]; then
                sleep $RETRY_DELAY
            fi
        fi
        
        ((attempt++))
    done
    
    if [[ "$verify" == "true" ]]; then
        log_warn "$hostname may not be fully awake yet"
        return 1
    fi
    
    log_success "Wake packets sent to $hostname"
    return 0
}

# Wake all nodes
wake_all_nodes() {
    local verify="${1:-false}"
    
    log_info "Waking all cluster nodes..."
    
    local nodes
    nodes=$(get_all_nodes)
    
    if [[ -z "$nodes" ]]; then
        log_error "No nodes found in registry"
        return 1
    fi
    
    local success=0
    local failed=0
    
    # Wake masters first (if distinguishable)
    for node in $nodes; do
        if [[ "$node" == *"master"* ]] || [[ "$node" == *"control"* ]]; then
            if wake_node "$node" "$verify"; then
                ((success++))
            else
                ((failed++))
            fi
            sleep $WAKE_INTERVAL
        fi
    done
    
    # Then wake workers
    for node in $nodes; do
        if [[ "$node" != *"master"* ]] && [[ "$node" != *"control"* ]]; then
            if wake_node "$node" "$verify"; then
                ((success++))
            else
                ((failed++))
            fi
            sleep $WAKE_INTERVAL
        fi
    done
    
    log_info "Wake summary: $success succeeded, $failed failed"
    
    if [[ $failed -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Check node status
check_node_status() {
    local hostname="$1"
    
    local node_info
    node_info=$(get_node_info "$hostname")
    local ip
    ip=$(echo "$node_info" | awk '{print $2}')
    
    if [[ -z "$ip" ]]; then
        echo "unknown"
        return
    fi
    
    if ping -c 1 -W 2 "$ip" &>/dev/null; then
        echo "awake"
    else
        echo "sleeping"
    fi
}

# List all nodes with status
list_nodes() {
    echo -e "${CYAN}Node Status${NC}"
    echo "==========="
    
    local nodes
    nodes=$(get_all_nodes)
    
    for node in $nodes; do
        local status
        status=$(check_node_status "$node")
        
        case "$status" in
            awake)
                echo -e "$node: ${GREEN}awake${NC}"
                ;;
            sleeping)
                echo -e "$node: ${YELLOW}sleeping${NC}"
                ;;
            *)
                echo -e "$node: ${RED}unknown${NC}"
                ;;
        esac
    done
}

# Print usage
print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [NODE...]

Wake VMStation cluster nodes using Wake-on-LAN.

Arguments:
    NODE                    Node hostname(s) to wake

Options:
    --all                   Wake all nodes in registry
    --masters               Wake only master/control nodes
    --workers               Wake only worker nodes
    --verify                Verify nodes are awake after sending packets
    --list                  List all nodes and their status
    --status NODE           Check status of specific node
    --retries N             Number of retry attempts (default: 3)
    --delay N               Delay between retries in seconds (default: 10)
    -h, --help              Show this help message

Environment Variables:
    WOL_REGISTRY            Path to WoL registry file
    CONFIG_DIR              Path to node config directory
    RETRY_COUNT             Number of retries (default: 3)
    RETRY_DELAY             Delay between retries (default: 10)

Examples:
    $(basename "$0") worker-01           # Wake specific node
    $(basename "$0") --all               # Wake all nodes
    $(basename "$0") --all --verify      # Wake all and verify
    $(basename "$0") --list              # List nodes and status
    $(basename "$0") --workers           # Wake only workers

EOF
}

# Main function
main() {
    local nodes=()
    local wake_all=false
    local wake_masters=false
    local wake_workers=false
    local verify=false
    local list_mode=false
    local status_node=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                wake_all=true
                shift
                ;;
            --masters)
                wake_masters=true
                shift
                ;;
            --workers)
                wake_workers=true
                shift
                ;;
            --verify)
                verify=true
                shift
                ;;
            --list)
                list_mode=true
                shift
                ;;
            --status)
                status_node="$2"
                shift 2
                ;;
            --retries)
                RETRY_COUNT="$2"
                shift 2
                ;;
            --delay)
                RETRY_DELAY="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                nodes+=("$1")
                shift
                ;;
        esac
    done
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    # Handle list mode
    if [[ "$list_mode" == "true" ]]; then
        list_nodes
        exit 0
    fi
    
    # Handle status check
    if [[ -n "$status_node" ]]; then
        local status
        status=$(check_node_status "$status_node")
        echo "$status_node: $status"
        exit 0
    fi
    
    # Check WoL tool availability
    if ! find_wol_tool &>/dev/null; then
        exit 1
    fi
    
    # Wake nodes
    local exit_code=0
    
    if [[ "$wake_all" == "true" ]]; then
        wake_all_nodes "$verify" || exit_code=1
    elif [[ "$wake_masters" == "true" ]]; then
        for node in $(get_all_nodes); do
            if [[ "$node" == *"master"* ]] || [[ "$node" == *"control"* ]]; then
                wake_node "$node" "$verify" || exit_code=1
                sleep $WAKE_INTERVAL
            fi
        done
    elif [[ "$wake_workers" == "true" ]]; then
        for node in $(get_all_nodes); do
            if [[ "$node" != *"master"* ]] && [[ "$node" != *"control"* ]]; then
                wake_node "$node" "$verify" || exit_code=1
                sleep $WAKE_INTERVAL
            fi
        done
    elif [[ ${#nodes[@]} -gt 0 ]]; then
        for node in "${nodes[@]}"; do
            wake_node "$node" "$verify" || exit_code=1
            sleep $WAKE_INTERVAL
        done
    else
        log_error "No nodes specified. Use --all, --masters, --workers, or specify node names."
        print_usage
        exit 1
    fi
    
    exit $exit_code
}

main "$@"
