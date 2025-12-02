#!/bin/bash
# logging.sh - Logging utilities for VMStation orchestration
# Part of VMStation Cluster Setup
#
# Provides consistent logging across all orchestration scripts:
# - Timestamped log entries
# - Colored console output
# - File logging support
# - Log level filtering

# shellcheck disable=SC2034  # Variables are used by sourcing scripts

# Colors for output
readonly LOG_RED='\033[0;31m'
readonly LOG_GREEN='\033[0;32m'
readonly LOG_YELLOW='\033[1;33m'
readonly LOG_BLUE='\033[0;34m'
readonly LOG_CYAN='\033[0;36m'
readonly LOG_BOLD='\033[1m'
readonly LOG_NC='\033[0m'

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# Current log level (default: INFO)
LOG_LEVEL="${LOG_LEVEL:-$LOG_LEVEL_INFO}"

# Log file (empty means no file logging)
LOG_FILE="${LOG_FILE:-}"

# Whether to use colors (auto-detect if not set)
if [[ -z "${LOG_USE_COLORS:-}" ]]; then
    if [[ -t 1 ]]; then
        LOG_USE_COLORS="true"
    else
        LOG_USE_COLORS="false"
    fi
fi

# Get current timestamp
_log_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Write to log file if configured
_log_to_file() {
    local level="$1"
    local message="$2"
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(_log_timestamp)] [$level] $message" >> "$LOG_FILE"
    fi
}

# Core log function
_log() {
    local level="$1"
    local level_num="$2"
    local color="$3"
    local icon="$4"
    shift 4
    local message="$*"
    
    # Check log level
    if [[ $level_num -lt $LOG_LEVEL ]]; then
        return
    fi
    
    # Log to file
    _log_to_file "$level" "$message"
    
    # Console output
    if [[ "$LOG_USE_COLORS" == "true" ]]; then
        echo -e "${color}${icon}${LOG_NC} $message"
    else
        echo "[$level] $message"
    fi
}

# Log functions
log_debug() {
    _log "DEBUG" "$LOG_LEVEL_DEBUG" "$LOG_CYAN" "⋯" "$@"
}

log_info() {
    _log "INFO" "$LOG_LEVEL_INFO" "$LOG_BLUE" "ℹ" "$@"
}

log_success() {
    _log "SUCCESS" "$LOG_LEVEL_INFO" "$LOG_GREEN" "✓" "$@"
}

log_warn() {
    _log "WARN" "$LOG_LEVEL_WARN" "$LOG_YELLOW" "⚠" "$@"
}

log_error() {
    _log "ERROR" "$LOG_LEVEL_ERROR" "$LOG_RED" "✗" "$@"
}

log_step() {
    _log "STEP" "$LOG_LEVEL_INFO" "$LOG_CYAN" "→" "$@"
}

log_header() {
    _log "HEADER" "$LOG_LEVEL_INFO" "${LOG_BOLD}${LOG_CYAN}" "━━" "$@"
}

# Initialize log file
init_log_file() {
    local log_file="$1"
    LOG_FILE="$log_file"
    
    # Create log directory if needed
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    mkdir -p "$log_dir"
    
    # Write header
    echo "" >> "$LOG_FILE"
    echo "=== VMStation Orchestration Log ===" >> "$LOG_FILE"
    echo "Started at: $(_log_timestamp)" >> "$LOG_FILE"
    echo "===================================" >> "$LOG_FILE"
}

# Progress bar
show_progress() {
    local current="$1"
    local total="$2"
    local label="${3:-}"
    
    local percentage=$((current * 100 / total))
    local filled=$((percentage / 5))
    local empty=$((20 - filled))
    
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    if [[ "$LOG_USE_COLORS" == "true" ]]; then
        echo -e "${LOG_BOLD}[${current}/${total}]${LOG_NC} [${bar}] ${percentage}%${label:+ - }${label}"
    else
        echo "[${current}/${total}] [${bar}] ${percentage}%${label:+ - }${label}"
    fi
}

# Print separator line
log_separator() {
    if [[ "$LOG_USE_COLORS" == "true" ]]; then
        echo -e "${LOG_CYAN}────────────────────────────────────────${LOG_NC}"
    else
        echo "----------------------------------------"
    fi
}

# Print a box around a message
log_box() {
    local message="$1"
    local len=${#message}
    local border=""
    for ((i=0; i<len+4; i++)); do border+="═"; done
    
    if [[ "$LOG_USE_COLORS" == "true" ]]; then
        echo -e "${LOG_CYAN}╔${border}╗${LOG_NC}"
        echo -e "${LOG_CYAN}║${LOG_NC}  ${LOG_BOLD}${message}${LOG_NC}  ${LOG_CYAN}║${LOG_NC}"
        echo -e "${LOG_CYAN}╚${border}╝${LOG_NC}"
    else
        echo "+${border}+"
        echo "|  ${message}  |"
        echo "+${border}+"
    fi
}
