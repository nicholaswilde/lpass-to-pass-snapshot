#!/usr/bin/env bash
################################################################################
#
# check-sync-status.sh
# ----------------
# A Bash utility to check if the local password store (pass) is out of date
# compared to the LastPass vault (lpass).
#
# @author Nicholas Wilde
# @date 29 Dec 2025
#
################################################################################

set -e
# set -o pipefail

# Constants & Colors
readonly RESET=$(tput sgr0)
readonly MOCHA_RED='\033[38;2;243;139;168m'      # Errors
readonly MOCHA_YELLOW='\033[38;2;249;226;175m'   # Warnings
readonly MOCHA_BLUE='\033[38;2;137;180;250m'     # Info
readonly MOCHA_LAVENDER='\033[38;2;180;190;254m' # Debug
DEBUG="false"

# Logging function (consistent with lpass-to-pass-snapshot.sh)
function log() {
  local type="$1"
  local color="$RESET"
  
  if [ "${type}" = "DEBU" ] && [ "${DEBUG}" != "true" ]; then
    return 0
  fi

  case "$type" in
    INFO) color="$MOCHA_BLUE";;
    WARN) color="$MOCHA_YELLOW";;
    ERRO) color="$MOCHA_RED";;
    DEBU) color="$MOCHA_LAVENDER";;
    *)    type="LOGS";;
  esac

  local message="$2"
  echo -e "${color}${type}${RESET}[$(date +'%Y-%m-%d %H:%M:%S')] ${message}"
}

function check_dependencies() {
  local missing=0
  if ! command -v lpass &>/dev/null; then
    log "ERRO" "lpass is not installed."
    missing=1
  fi
  if ! command -v date &>/dev/null; then
    log "ERRO" "date command is not installed."
    missing=1
  fi
  if [[ $missing -eq 1 ]]; then
    exit 1
  fi
}

function parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--debug)
        DEBUG="true"
        shift
        ;;
      -h|--help)
        echo "Usage: $0 [--debug]"
        exit 0
        ;;
      *)
        shift
        ;;
    esac
  done
}

function main() {
  parse_args "$@"
  check_dependencies

  # 1. Determine Password Store Directory
  local pass_dir="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
  if [[ ! -d "$pass_dir" ]]; then
     # Fallback for gopass
     local gopass_dir="${HOME}/.local/share/gopass/stores/root"
     if [[ -d "$gopass_dir" ]]; then
        pass_dir="$gopass_dir"
     else
        log "ERRO" "Password store directory not found at $pass_dir or $gopass_dir."
        exit 1
     fi
  fi

  log "INFO" "Checking sync status..."
  log "DEBU" "Using password store: $pass_dir"

  # 2. Get latest modification time from Pass
  # Using find to get all .gpg files, print modification timestamp (%T@), sort numeric, take last.
  local latest_pass_file_info
  local latest_pass_time=0
  
  if latest_pass_file_info=$(find "$pass_dir" -type f -name "*.gpg" -printf '%T@\n' 2>/dev/null | sort -n | tail -1); then
     # Cut to remove fractional seconds if present
     latest_pass_time=$(echo "$latest_pass_file_info" | cut -d. -f1)
  fi

  if [[ "$latest_pass_time" -eq 0 ]]; then
    log "WARN" "No password files found in $pass_dir. Assuming empty store (Timestamp: 0)."
  fi

  # 3. Get latest modification time from LastPass
  if ! lpass status -q >/dev/null 2>&1; then
     log "ERRO" "Not logged into LastPass. Please run 'lpass login'."
     exit 1
  fi

  log "INFO" "Fetching LastPass modification times (this may take a moment)..."
  
  local lpass_output
  # Using lpass ls --long as requested. 
  # Allow non-zero exit code by using || true, so we can process partial output.
  lpass_output=$(lpass ls --long 2>&1 || true)
  
  if [[ -z "$lpass_output" ]]; then
     log "ERRO" "Failed to get any output from 'lpass ls --long'."
     exit 1
  fi

  # Check for known error strings in stdout but DO NOT EXIT
  # lpass ls --long might return partial results along with errors (like unbase64 issues for specific items)
  if [[ "$lpass_output" == *"Error:"* || "$lpass_output" == *"Could not unbase64"* ]]; then
     log "WARN" "LastPass CLI returned error(s) in output, but we will attempt to parse valid entries."
     if [[ "$DEBUG" == "true" ]]; then
       echo "$lpass_output" | grep "Error" || true
     fi
  fi

  local latest_lpass_time=0
  local count=0
  
  # Parse dates from ls --long output
  # Example line: "    2024-09-13 03:27 walgreens.com [id: ...]"
  while IFS= read -r line; do
      # Extract first two words which should be Date and Time
      local dt
      dt=$(echo "$line" | awk '{print $1, $2}')
      
      # Validate it looks like a date (roughly YYYY-MM-DD)
      if [[ ! "$dt" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
          continue
      fi
      
      ((++count))
      
      local ts
      # Convert to unix timestamp. 
      ts=$(date -d "$dt" +%s 2>/dev/null || echo 0)
      
      # Debug first few to ensure parsing is working
      if [[ "$count" -le 3 ]]; then
         log "DEBU" "Parsed: '$dt' -> $ts"
      fi

      if (( ts > latest_lpass_time )); then
          latest_lpass_time=$ts
      fi
  done <<< "$lpass_output"

  if [[ "$count" -eq 0 ]]; then
     log "WARN" "No entries found in LastPass or failed to parse ls --long output."
     log "DEBU" "First 3 lines of output:"
     echo "$lpass_output" | head -n 3
  else
     log "INFO" "Scanned $count LastPass entries."
  fi

  # 4. Compare and Report
  local pass_date_str="Never"
  local lpass_date_str="Never"
  
  if [[ "$latest_pass_time" -gt 0 ]]; then
    pass_date_str=$(date -d "@$latest_pass_time" "+%Y-%m-%d %H:%M:%S")
  fi
  if [[ "$latest_lpass_time" -gt 0 ]]; then
    lpass_date_str=$(date -d "@$latest_lpass_time" "+%Y-%m-%d %H:%M:%S")
  fi

  log "INFO" "Latest Local Update:  $pass_date_str"
  log "INFO" "Latest Remote Update: $lpass_date_str"

  if (( latest_lpass_time > latest_pass_time )); then
    local diff=$(( latest_lpass_time - latest_pass_time ))
    log "WARN" "Status: OUT OF DATE"
    log "WARN" "LastPass is newer by approx $diff seconds."
    exit 1
  else
    log "INFO" "Status: SYNCHRONIZED (or local is newer)"
    exit 0
  fi
}

main "$@"
