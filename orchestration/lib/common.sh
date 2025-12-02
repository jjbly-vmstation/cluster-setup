#!/bin/bash
# common.sh - Shared functions for VMStation orchestration
# Part of VMStation Cluster Setup
#
# Provides common utilities used across orchestration scripts:
# - Directory detection
# - Version comparison
# - Git repository management
# - State management
# - Retry logic

# Prevent double-sourcing
if [[ -n "${_COMMON_SH_LOADED:-}" ]]; then
    return 0
fi
_COMMON_SH_LOADED=1

# Get script directory (for the caller)
get_script_dir() {
    cd "$(dirname "${BASH_SOURCE[1]}")" && pwd
}

# Get repository root
get_repo_root() {
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)
    
    # Walk up to find .git directory
    local current="$script_dir"
    while [[ "$current" != "/" ]]; do
        if [[ -d "$current/.git" ]]; then
            echo "$current"
            return 0
        fi
        current=$(dirname "$current")
    done
    
    # Fallback: assume orchestration is in repo root
    dirname "$script_dir"
}

# Compare semantic versions
# Returns 0 if version1 >= version2
version_gte() {
    local version1="$1"
    local version2="$2"
    printf '%s\n%s\n' "$version2" "$version1" | sort -V -C
}

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Ensure a command exists, error if not
require_command() {
    local cmd="$1"
    local package="${2:-$1}"
    
    if ! command_exists "$cmd"; then
        log_error "Required command '$cmd' not found. Install with: $package"
        return 1
    fi
}

# Clone or update a git repository
clone_or_update_repo() {
    local repo_url="$1"
    local target_dir="$2"
    local branch="${3:-main}"
    
    if [[ -d "$target_dir/.git" ]]; then
        log_info "Updating repository: $target_dir"
        if ! git -C "$target_dir" fetch --prune 2>/dev/null; then
            log_warn "Failed to fetch updates for $target_dir"
            return 1
        fi
        if ! git -C "$target_dir" checkout "$branch" 2>/dev/null; then
            log_warn "Failed to checkout $branch in $target_dir"
            return 1
        fi
        if ! git -C "$target_dir" pull origin "$branch" 2>/dev/null; then
            log_warn "Failed to pull updates for $target_dir"
            return 1
        fi
    else
        log_info "Cloning repository: $repo_url -> $target_dir"
        mkdir -p "$(dirname "$target_dir")"
        if ! git clone --branch "$branch" "$repo_url" "$target_dir" 2>/dev/null; then
            log_error "Failed to clone $repo_url"
            return 1
        fi
    fi
    
    return 0
}

# Check if local repo exists (for offline mode)
local_repo_exists() {
    local target_dir="$1"
    [[ -d "$target_dir/.git" ]]
}

# Get current branch of a repository
get_repo_branch() {
    local repo_dir="$1"
    git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# Get current commit SHA of a repository
get_repo_commit() {
    local repo_dir="$1"
    git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null
}

# Save state to file
save_state() {
    local state_file="$1"
    shift
    
    mkdir -p "$(dirname "$state_file")"
    
    # Write all key=value pairs
    {
        echo "# VMStation state file"
        echo "# Generated at $(date -Iseconds)"
        for pair in "$@"; do
            echo "$pair"
        done
    } > "$state_file"
}

# Load state from file
load_state() {
    local state_file="$1"
    
    if [[ -f "$state_file" ]]; then
        # shellcheck source=/dev/null
        source "$state_file"
        return 0
    fi
    return 1
}

# Retry a command with exponential backoff
retry_command() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    shift 2
    local cmd=("$@")
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if "${cmd[@]}"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "Command failed, retrying in ${delay}s (attempt $attempt/$max_attempts)"
            sleep "$delay"
            delay=$((delay * 2))
        fi
        ((attempt++))
    done
    
    log_error "Command failed after $max_attempts attempts: ${cmd[*]}"
    return 1
}

# Wait for a condition with timeout
wait_for() {
    local description="$1"
    local timeout="${2:-60}"
    shift 2
    local check_cmd=("$@")
    
    local start_time
    start_time=$(date +%s)
    
    log_info "Waiting for $description (timeout: ${timeout}s)..."
    
    while true; do
        if "${check_cmd[@]}" 2>/dev/null; then
            log_success "$description is ready"
            return 0
        fi
        
        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout waiting for $description"
            return 1
        fi
        
        sleep 2
    done
}

# Create a backup of a file or directory
create_backup() {
    local source="$1"
    local backup_dir="${2:-/tmp/vmstation-backups}"
    
    if [[ ! -e "$source" ]]; then
        log_warn "Source does not exist, skipping backup: $source"
        return 0
    fi
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local basename
    basename=$(basename "$source")
    local backup_path="$backup_dir/${basename}.${timestamp}"
    
    mkdir -p "$backup_dir"
    
    if cp -r "$source" "$backup_path"; then
        log_info "Created backup: $backup_path"
        echo "$backup_path"
        return 0
    else
        log_error "Failed to create backup of $source"
        return 1
    fi
}

# Check if running as root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Ensure script is running as root
require_root() {
    if ! is_root; then
        log_error "This operation requires root privileges"
        return 1
    fi
}

# Get the OS type
get_os_type() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "$ID"
    elif command_exists uname; then
        uname -s | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

# Check if we're in a CI environment
is_ci_environment() {
    [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${JENKINS_URL:-}" ]]
}

# Generate a unique run ID
generate_run_id() {
    date +%Y%m%d_%H%M%S_$$
}

# Cleanup function to be called on exit
cleanup_on_exit() {
    local exit_code=$?
    
    # Call any registered cleanup functions
    if [[ -n "${_CLEANUP_FUNCTIONS:-}" ]]; then
        for func in $_CLEANUP_FUNCTIONS; do
            if declare -f "$func" &>/dev/null; then
                "$func" || true
            fi
        done
    fi
    
    return $exit_code
}

# Register a cleanup function
register_cleanup() {
    local func="$1"
    _CLEANUP_FUNCTIONS="${_CLEANUP_FUNCTIONS:-} $func"
}

# Set up signal handlers
setup_signal_handlers() {
    trap cleanup_on_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
}
