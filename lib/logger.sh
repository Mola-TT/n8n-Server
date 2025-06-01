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

# Logging function with timestamp and level
log() {
  local level=$1
  local message=$2
  local level_color=""
  
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
    
    # Get terminal width if possible
    local term_width
    if command -v tput >/dev/null 2>&1; then
      term_width=$(tput cols 2>/dev/null || echo "$MAX_LOG_WIDTH")
    else
      term_width=$MAX_LOG_WIDTH
    fi
    
    # Timestamp and level prefix
    local prefix="[${timestamp}] [${level}]${padding}"
    local prefix_no_color="[${timestamp}] [${level}]${padding}"
    local prefix_len=${#prefix_no_color}
    
    # Calculate max message length
    local max_msg_len=$((term_width - prefix_len - 2))  # -2 for good measure
    
    if [ ${#message} -le $max_msg_len ]; then
      # Message fits on a single line, print it normally
      echo -e "[${BOLD}${timestamp}${RESET}] [${level_color}${level}${RESET}]${padding}${WHITE}${message}${RESET}"
      echo "[${timestamp}] [${level}]${padding}${message}" >> ${LOG_FILE}
    else
      # Message is too long, we need to wrap it
      # Print first line
      echo -e "[${BOLD}${timestamp}${RESET}] [${level_color}${level}${RESET}]${padding}${WHITE}${message:0:$max_msg_len}${RESET}"
      echo "[${timestamp}] [${level}]${padding}${message:0:$max_msg_len}" >> ${LOG_FILE}
      
      # Calculate continuing lines indentation
      local indent=$(printf "%${prefix_len}s" "")
      
      # Print remaining message with proper indentation
      local remaining_msg="${message:$max_msg_len}"
      while [ ${#remaining_msg} -gt 0 ]; do
        local this_part_len=$max_msg_len
        if [ ${#remaining_msg} -le $max_msg_len ]; then
          # Last part
          local line_msg="${remaining_msg}"
          echo -e "${indent}${WHITE}${line_msg}${RESET}"
          echo "${indent}${line_msg}" >> ${LOG_FILE}
          remaining_msg=""
        else
          # More parts to come
          local line_msg="${remaining_msg:0:$max_msg_len}"
          echo -e "${indent}${WHITE}${line_msg}${RESET}"
          echo "${indent}${line_msg}" >> ${LOG_FILE}
          remaining_msg="${remaining_msg:$max_msg_len}"
        fi
      done
    fi
  fi
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