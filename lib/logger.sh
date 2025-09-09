#!/bin/bash
# logger.sh - Logging utility functions
# Part of Milestone 1

# Set default log level to INFO if not already set
LOG_LEVEL=${LOG_LEVEL:-INFO}

# Set default log file if not already set
if [[ -z "${LOG_FILE:-}" ]]; then
  # Try to use system log directory first
  if [[ -w "/var/log" ]] || sudo touch "/var/log/server_init.log" 2>/dev/null; then
    LOG_FILE="/var/log/server_init.log"
    # Ensure proper ownership if we created it with sudo
    if [[ -f "$LOG_FILE" ]] && [[ "$(stat -c '%U' "$LOG_FILE")" == "root" ]]; then
      sudo chown "$(whoami):$(whoami)" "$LOG_FILE" 2>/dev/null || true
    fi
  else
    # Fall back to user's home directory
    LOG_FILE="$HOME/server_init.log"
  fi
fi

# ANSI color codes
RESET='\033[0m'
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'

# Log level values for comparison
declare -A LOG_LEVELS
LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARNING]=2 [ERROR]=3 [PASS]=1)

# Maximum width for log messages
MAX_LOG_WIDTH=120

# Padding for levels to ensure alignment
LEVEL_PADDING=9  # Allow for longest level (WARNING) plus some spacing

# Line ending consistency
LF=$'\n'
normalize_line_endings() {
    # Convert CRLF and CR to LF for consistent Unix line endings
    echo "$1" | sed 's/\r\n/\n/g' | sed 's/\r/\n/g'
}

# Enhanced logging function with improved formatting and line ending consistency
log() {
  local level=$1
  local message="$2"
  local level_color=""
  
  # Normalize line endings in message
  message=$(normalize_line_endings "$message")
  
  # Set color based on log level
  case $level in
    DEBUG)   level_color="${CYAN}" ;;
    INFO)    level_color="${GREEN}" ;;
    WARNING) level_color="${YELLOW}" ;;
    ERROR)   level_color="${RED}" ;;
    PASS)    level_color="${GREEN}" ;;
    *)       level_color="${WHITE}" ;;
  esac
  
  # Only log if the level is greater than or equal to the configured log level
  if [[ ${LOG_LEVELS[$level]} -ge ${LOG_LEVELS[$LOG_LEVEL]} ]]; then
    # Format: [TIMESTAMP] [LEVEL]      message
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Calculate padding for level to ensure alignment
    local level_len=${#level}
    local padding_len=$((LEVEL_PADDING - level_len))
    local padding=$(printf "%${padding_len}s" "")
    
    # Get terminal width if possible, limit to reasonable bounds
    local term_width
    if command -v tput >/dev/null 2>&1; then
      term_width=$(tput cols 2>/dev/null || echo "$MAX_LOG_WIDTH")
      # Ensure width is reasonable (between 80 and 200 chars)
      if [ "$term_width" -lt 80 ]; then
        term_width=80
      elif [ "$term_width" -gt 200 ]; then
        term_width=200
      fi
    else
      term_width=$MAX_LOG_WIDTH
    fi
    
    # Timestamp and level prefix
    local prefix="[${timestamp}] [${level}]${padding}"
    local prefix_no_color="[${timestamp}] [${level}]${padding}"
    local prefix_len=${#prefix_no_color}
    
    # Calculate max message length
    local max_msg_len=$((term_width - prefix_len - 2))  # -2 for good measure
    
    # Handle multi-line messages properly
    if [[ "$message" == *$'\n'* ]]; then
      # Multi-line message - process each line separately
      local first_line=true
      while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$first_line" == true ]]; then
          # First line gets full prefix
          _log_single_line "$level" "$line" "$timestamp" "$level_color" "$padding" "$prefix_len" "$max_msg_len"
          first_line=false
        else
          # Continuation lines get indented
          _log_continuation_line "$line" "$timestamp" "$level" "$padding" "$prefix_len" "$max_msg_len"
        fi
      done <<< "$message"
    else
      # Single line message
      _log_single_line "$level" "$message" "$timestamp" "$level_color" "$padding" "$prefix_len" "$max_msg_len"
    fi
  fi
}

# Helper function to log a single line with proper wrapping
_log_single_line() {
  local level="$1"
  local message="$2"  
  local timestamp="$3"
  local level_color="$4"
  local padding="$5"
  local prefix_len="$6"
  local max_msg_len="$7"
  
  if [ ${#message} -le $max_msg_len ]; then
    # Message fits on a single line
    echo -e "[${BOLD}${timestamp}${RESET}] [${level_color}${level}${RESET}]${padding}${WHITE}${message}${RESET}"
    printf "[%s] [%s]%s%s\n" "$timestamp" "$level" "$padding" "$message" >> "${LOG_FILE}"
  else
    # Message needs wrapping
    _log_wrapped_line "$level" "$message" "$timestamp" "$level_color" "$padding" "$prefix_len" "$max_msg_len"
  fi
}

# Helper function to log continuation lines  
_log_continuation_line() {
  local message="$1"
  local timestamp="$2"
  local level="$3"
  local padding="$4"
  local prefix_len="$5"
  local max_msg_len="$6"
  
  local indent=$(printf "%${prefix_len}s" "")
  
  if [ ${#message} -le $max_msg_len ]; then
    # Continuation line fits
    echo -e "${indent}${WHITE}${message}${RESET}"
    printf "%s%s\n" "$indent" "$message" >> "${LOG_FILE}"
  else
    # Continuation line needs wrapping
    _log_wrapped_continuation "$message" "$indent" "$max_msg_len"
  fi
}

# Helper function to log wrapped lines
_log_wrapped_line() {
  local level="$1"
  local message="$2"
  local timestamp="$3"
  local level_color="$4"
  local padding="$5"
  local prefix_len="$6"
  local max_msg_len="$7"
  
  # Print first line with full prefix
  local first_part="${message:0:$max_msg_len}"
  echo -e "[${BOLD}${timestamp}${RESET}] [${level_color}${level}${RESET}]${padding}${WHITE}${first_part}${RESET}"
  printf "[%s] [%s]%s%s\n" "$timestamp" "$level" "$padding" "$first_part" >> "${LOG_FILE}"
  
  # Print remaining parts with continuation indicator
  local remaining_msg="${message:$max_msg_len}"
  local indent=$(printf "%${prefix_len}s" "")
  
  _log_wrapped_continuation "$remaining_msg" "$indent" "$max_msg_len"
}

# Helper function to log wrapped continuation parts
_log_wrapped_continuation() {
  local remaining_msg="$1"
  local indent="$2"
  local max_msg_len="$3"
  
  while [ ${#remaining_msg} -gt 0 ]; do
    if [ ${#remaining_msg} -le $max_msg_len ]; then
      # Last part
      echo -e "${indent}${WHITE}↳ ${remaining_msg}${RESET}"
      printf "%s↳ %s\n" "$indent" "$remaining_msg" >> "${LOG_FILE}"
      remaining_msg=""
    else
      # More parts to come
      local line_msg="${remaining_msg:0:$max_msg_len}"
      echo -e "${indent}${WHITE}↳ ${line_msg}${RESET}"
      printf "%s↳ %s\n" "$indent" "$line_msg" >> "${LOG_FILE}"
      remaining_msg="${remaining_msg:$max_msg_len}"
    fi
  done
}

# Convenience functions for each log level
log_debug() {
  log "DEBUG" "$1"
}

log_info() {
  log "INFO" "$1"
}

log_warn() {
  log "WARNING" "$1"
}

log_error() {
  log "ERROR" "$1"
}

log_pass() {
  log "PASS" "$1"
}

# =============================================================================
# Enhanced Logging Functions for External Process Management
# =============================================================================

# Log section header with visual separator
log_section() {
  local section_name="$1"
  local separator_char="${2:-=}"
  local separator_length=80
  
  local separator=$(printf "%*s" $separator_length | tr ' ' "$separator_char")
  local header_text="$section_name"
  local header_len=${#header_text}
  local padding_len=$(( (separator_length - header_len - 2) / 2 ))
  local left_padding=$(printf "%*s" $padding_len | tr ' ' "$separator_char")
  local right_padding_len=$(( separator_length - header_len - 2 - padding_len ))
  local right_padding=$(printf "%*s" $right_padding_len | tr ' ' "$separator_char")
  
  echo ""
  log_info "$separator"
  log_info "$left_padding $header_text $right_padding"
  log_info "$separator"
}

# Log subsection header with visual separator
log_subsection() {
  local subsection_name="$1"
  local separator_char="${2:--}"
  local separator_length=60
  
  local separator=$(printf "%*s" $separator_length | tr ' ' "$separator_char")
  
  echo ""
  log_info "$separator"
  log_info "$subsection_name"
  log_info "$separator"
}

# Execute command with enhanced logging and output capture
execute_with_structured_logging() {
  local cmd="$1"
  local description="${2:-}"
  local suppress_output="${3:-false}"
  local log_level="${4:-INFO}"
  local temp_log_file="/tmp/exec_$$.log"
  
  log_debug "Command: $cmd"
  
  # Only show progress message if description is provided
  if [[ -n "$description" ]]; then
    log_info "🔄 $description..."
  fi
  
  # Create temporary log file
  : > "$temp_log_file"
  
  # Execute command and capture output
  local start_time=$(date +%s)
  local exit_code=0
  
  if [[ "$suppress_output" == "true" ]]; then
    # Silent execution - capture all output
    if ! eval "$cmd" > "$temp_log_file" 2>&1; then
      exit_code=$?
    fi
  else
    # Show progress while capturing output
    if ! eval "$cmd" 2>&1 | tee "$temp_log_file"; then
      exit_code=$?
    fi
  fi
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  # Process the output
  if [[ -s "$temp_log_file" ]]; then
    local line_count=$(wc -l < "$temp_log_file")
    
    if [[ $exit_code -eq 0 ]]; then
      if [[ "$suppress_output" == "true" ]]; then
        # Only show completion message if description was provided
        if [[ -n "$description" ]]; then
          log_info "✓ $description completed successfully (${duration}s, $line_count lines of output)"
        fi
        log_debug "Command output summary:"
        head -3 "$temp_log_file" | while IFS= read -r line; do
          log_debug "  $(normalize_line_endings "$line")"
        done
        if [[ $line_count -gt 6 ]]; then
          log_debug "  ... ($((line_count - 6)) more lines)"
        fi
        if [[ $line_count -gt 3 ]]; then
          tail -3 "$temp_log_file" | while IFS= read -r line; do
            log_debug "  $(normalize_line_endings "$line")"
          done
        fi
      else
        # Only show completion message if description was provided
        if [[ -n "$description" ]]; then
          log_info "✓ $description completed successfully (${duration}s)"
        fi
      fi
    else
      # Always show error messages, even without description
      if [[ -n "$description" ]]; then
        log_error "✗ $description failed with exit code $exit_code (${duration}s)"
      else
        log_error "✗ Command failed with exit code $exit_code (${duration}s)"
      fi
      log_error "Error output:"
      tail -10 "$temp_log_file" | while IFS= read -r line; do
        log_error "  $(normalize_line_endings "$line")"
      done
    fi
    
    # Append processed output to main log file
    {
      if [[ -n "$description" ]]; then
        echo "# External Process Output: $description"
      else
        echo "# External Process Output: [Command execution]"
      fi
      echo "# Command: $cmd"
      echo "# Exit Code: $exit_code"
      echo "# Duration: ${duration}s"
      echo "# Output Lines: $line_count"
      echo "# Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
      echo "#" 
      while IFS= read -r line; do
        printf "# %s\n" "$(normalize_line_endings "$line")"
      done < "$temp_log_file"
      echo "#"
    } >> "$LOG_FILE"
  else
    if [[ $exit_code -eq 0 ]]; then
      # Only show completion message if description was provided
      if [[ -n "$description" ]]; then
        log_info "✓ $description completed successfully (${duration}s, no output)"
      fi
    else
      # Always show error messages, even without description
      if [[ -n "$description" ]]; then
        log_error "✗ $description failed with exit code $exit_code (${duration}s, no output)"
      else
        log_error "✗ Command failed with exit code $exit_code (${duration}s, no output)"
      fi
    fi
  fi
  
  # Cleanup
  rm -f "$temp_log_file"
  
  return $exit_code
}

# Progress indicator for long-running operations
log_progress() {
  local current="$1"
  local total="$2"
  local description="${3:-Progress}"
  local bar_length=50
  
  local percentage=$((current * 100 / total))
  local filled_length=$((current * bar_length / total))
  local bar=$(printf "%*s" $filled_length | tr ' ' '█')
  local empty=$(printf "%*s" $((bar_length - filled_length)) | tr ' ' '░')
  
  printf "\r[INFO] %s: [%s%s] %d%% (%d/%d)" "$description" "$bar" "$empty" "$percentage" "$current" "$total"
  
  if [[ $current -eq $total ]]; then
    echo ""  # New line when complete
    log_info "✓ $description completed: 100% ($total/$total)"
  fi
}

# Capture and format external tool output
log_external_tool_output() {
  local tool_name="$1"
  local output="$2"
  local exit_code="${3:-0}"
  
  log_info "External tool output from $tool_name:"
  
  if [[ $exit_code -eq 0 ]]; then
    echo "$output" | while IFS= read -r line; do
      if [[ -n "$line" ]]; then
        log_info "  [$tool_name] $(normalize_line_endings "$line")"
      fi
    done
  else
    echo "$output" | while IFS= read -r line; do
      if [[ -n "$line" ]]; then
        log_error "  [$tool_name] $(normalize_line_endings "$line")"
      fi
    done
  fi
}

# Ensure log file directory exists and is writable
log_dir="$(dirname "${LOG_FILE}")"
if [[ ! -d "$log_dir" ]]; then
  mkdir -p "$log_dir" 2>/dev/null || true
fi

# Initialize log file if it doesn't exist or ensure it's writable
if [[ ! -f "${LOG_FILE}" ]]; then
  if [[ -w "$log_dir" ]]; then
    touch "${LOG_FILE}" 2>/dev/null || true
  elif [[ "$log_dir" == "/var/log" ]]; then
    # Try with sudo for system log directory
    sudo touch "${LOG_FILE}" 2>/dev/null || true
    sudo chown "$(whoami):$(whoami)" "${LOG_FILE}" 2>/dev/null || true
  fi
elif [[ ! -w "${LOG_FILE}" ]] && [[ -f "${LOG_FILE}" ]]; then
  # File exists but not writable, try to fix ownership
  if [[ "$(stat -c '%U' "$LOG_FILE")" == "root" ]]; then
    sudo chown "$(whoami):$(whoami)" "${LOG_FILE}" 2>/dev/null || true
  fi
fi 