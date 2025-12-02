#!/bin/bash
# safety.sh - Safety controls for VMStation orchestration
# Part of VMStation Cluster Setup
#
# Provides safety features for destructive operations:
# - Confirmation prompts
# - Dry-run enforcement
# - Safe mode controls
# - Automatic backups

# Prevent double-sourcing
if [[ -n "${_SAFETY_SH_LOADED:-}" ]]; then
    return 0
fi
_SAFETY_SH_LOADED=1

# Safety mode - when enabled, prevents destructive operations
VMSTATION_SAFE_MODE="${VMSTATION_SAFE_MODE:-0}"

# Dry-run mode - when enabled, no changes are made
DRY_RUN="${DRY_RUN:-false}"

# Auto-yes mode - skip confirmations (use with caution)
AUTO_YES="${AUTO_YES:-false}"

# Interactive mode
INTERACTIVE="${INTERACTIVE:-true}"

# Check if safe mode is enabled
is_safe_mode() {
    [[ "$VMSTATION_SAFE_MODE" == "1" ]] || [[ "$VMSTATION_SAFE_MODE" == "true" ]]
}

# Check if dry-run mode is enabled
is_dry_run() {
    [[ "$DRY_RUN" == "true" ]] || [[ "$DRY_RUN" == "1" ]]
}

# Check if auto-yes is enabled
is_auto_yes() {
    [[ "$AUTO_YES" == "true" ]] || [[ "$AUTO_YES" == "1" ]]
}

# Check if running interactively
is_interactive() {
    [[ "$INTERACTIVE" == "true" ]] && [[ -t 0 ]] && [[ -t 1 ]]
}

# Prompt for confirmation
# Returns 0 if confirmed, 1 if cancelled
confirm() {
    local message="${1:-Continue?}"
    
    # Auto-yes mode bypasses prompts
    if is_auto_yes; then
        log_warn "Auto-confirming: $message"
        return 0
    fi
    
    # Non-interactive mode fails without auto-yes
    if ! is_interactive; then
        log_error "Cannot prompt for confirmation in non-interactive mode"
        log_error "Use --yes or AUTO_YES=true to bypass"
        return 1
    fi
    
    echo -e "${LOG_YELLOW:-}$message${LOG_NC:-}"
    read -rp "Continue? [y/N] " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Prompt for typed confirmation (for destructive operations)
# Requires the user to type a specific phrase
confirm_destructive() {
    local action="$1"
    local confirm_phrase="${2:-DELETE}"
    
    # Auto-yes mode - still warn but proceed
    if is_auto_yes; then
        log_warn "Auto-confirming destructive operation: $action"
        return 0
    fi
    
    # Non-interactive mode fails
    if ! is_interactive; then
        log_error "Cannot perform destructive operation in non-interactive mode"
        log_error "Use --yes or AUTO_YES=true to bypass (use with caution!)"
        return 1
    fi
    
    echo ""
    log_warn "⚠️  DESTRUCTIVE OPERATION ⚠️"
    log_warn "Action: $action"
    echo ""
    echo -e "${LOG_YELLOW:-}This operation cannot be undone!${LOG_NC:-}"
    echo -e "Type '${LOG_BOLD:-}$confirm_phrase${LOG_NC:-}' to confirm, or anything else to cancel:"
    
    read -r response
    if [[ "$response" == "$confirm_phrase" ]]; then
        log_info "Destructive operation confirmed"
        return 0
    else
        log_info "Operation cancelled"
        return 1
    fi
}

# Guard for destructive operations
# Checks safe mode, dry-run mode, and prompts for confirmation
guard_destructive() {
    local operation="$1"
    local confirm_phrase="${2:-DELETE}"
    
    # Check safe mode
    if is_safe_mode; then
        log_error "Safe mode is enabled. Cannot perform: $operation"
        log_info "Disable safe mode with: export VMSTATION_SAFE_MODE=0"
        return 1
    fi
    
    # Check dry-run mode
    if is_dry_run; then
        log_info "[DRY-RUN] Would perform: $operation"
        return 1  # Return 1 to skip the operation
    fi
    
    # Prompt for confirmation
    if ! confirm_destructive "$operation" "$confirm_phrase"; then
        return 1
    fi
    
    return 0
}

# Execute a command with dry-run support
run_cmd() {
    local description="$1"
    shift
    local cmd=("$@")
    
    if is_dry_run; then
        log_info "[DRY-RUN] Would run: ${cmd[*]}"
        return 0
    fi
    
    log_step "$description"
    if ! "${cmd[@]}"; then
        log_error "Command failed: ${cmd[*]}"
        return 1
    fi
    return 0
}

# Create automatic backup before destructive operation
auto_backup() {
    local target="$1"
    local backup_dir="${2:-${STATE_DIR:-/tmp/vmstation}/backups}"
    
    if is_dry_run; then
        log_info "[DRY-RUN] Would backup: $target"
        return 0
    fi
    
    if [[ ! -e "$target" ]]; then
        log_debug "No backup needed, target does not exist: $target"
        return 0
    fi
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local basename
    basename=$(basename "$target")
    local backup_path="$backup_dir/${basename}.${timestamp}"
    
    mkdir -p "$backup_dir"
    
    log_info "Creating backup: $target -> $backup_path"
    if cp -r "$target" "$backup_path"; then
        log_success "Backup created: $backup_path"
        echo "$backup_path"
        return 0
    else
        log_error "Failed to create backup"
        return 1
    fi
}

# Validate environment before destructive operations
validate_environment() {
    local required_vars=("$@")
    local missing=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# Pre-flight check for destructive operations
preflight_check() {
    local operation="$1"
    
    log_header "Pre-flight Check: $operation"
    
    # Check if running as correct user
    if [[ $EUID -eq 0 ]] && [[ "${ALLOW_ROOT:-false}" != "true" ]]; then
        log_warn "Running as root - ensure this is intentional"
    fi
    
    # Check safe mode
    if is_safe_mode; then
        log_info "Safe mode: ENABLED (destructive operations blocked)"
    else
        log_info "Safe mode: DISABLED"
    fi
    
    # Check dry-run mode
    if is_dry_run; then
        log_info "Dry-run mode: ENABLED (no changes will be made)"
    else
        log_info "Dry-run mode: DISABLED"
    fi
    
    # Check auto-yes mode
    if is_auto_yes; then
        log_warn "Auto-yes mode: ENABLED (confirmations bypassed)"
    else
        log_info "Auto-yes mode: DISABLED"
    fi
    
    log_separator
    
    return 0
}

# Lock file management for preventing concurrent operations
acquire_lock() {
    local lock_file="$1"
    local timeout="${2:-60}"
    
    local lock_dir
    lock_dir=$(dirname "$lock_file")
    mkdir -p "$lock_dir"
    
    local start_time
    start_time=$(date +%s)
    
    while true; do
        if (set -o noclobber; echo $$ > "$lock_file") 2>/dev/null; then
            log_debug "Lock acquired: $lock_file"
            return 0
        fi
        
        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout waiting for lock: $lock_file"
            local existing_pid
            existing_pid=$(cat "$lock_file" 2>/dev/null || echo "unknown")
            log_error "Lock held by PID: $existing_pid"
            return 1
        fi
        
        sleep 1
    done
}

release_lock() {
    local lock_file="$1"
    
    if [[ -f "$lock_file" ]]; then
        rm -f "$lock_file"
        log_debug "Lock released: $lock_file"
    fi
}

# Register lock cleanup on exit
register_lock_cleanup() {
    local lock_file="$1"
    
    # Add to cleanup list
    _LOCK_FILES="${_LOCK_FILES:-} $lock_file"
    
    # Set up trap if not already done
    if [[ -z "${_LOCK_TRAP_SET:-}" ]]; then
        trap '_cleanup_locks' EXIT
        _LOCK_TRAP_SET=1
    fi
}

_cleanup_locks() {
    if [[ -n "${_LOCK_FILES:-}" ]]; then
        for lock_file in $_LOCK_FILES; do
            release_lock "$lock_file"
        done
    fi
}
