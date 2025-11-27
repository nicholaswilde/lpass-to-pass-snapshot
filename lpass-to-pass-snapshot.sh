#!/usr/bin/env bash
################################################################################
#
# lpass-to-pass-snapshot.sh
# ----------------
# A Bash utility to perform a one-way snapshot of a LastPass vault (lpass)
# into the standard Unix Password Store (pass).
#
# @author Nicholas Wilde, 0xb299a622
# @date 26 Nov 2025
# @version 0.1.0
#
################################################################################

# Options
set -e
set -o pipefail

# These are constants
readonly BLUE=$(tput setaf 4)
readonly RED=$(tput setaf 1)
readonly YELLOW=$(tput setaf 3)
readonly PURPLE=$(tput setaf 5)
readonly RESET=$(tput sgr0)
readonly MOCHA_RED='\033[38;2;243;139;168m'      # Errors / Logged out
readonly MOCHA_GREEN='\033[38;2;166;227;161m'    # Success / Logged in
readonly MOCHA_YELLOW='\033[38;2;249;226;175m'   # Warnings
readonly MOCHA_BLUE='\033[38;2;137;180;250m'     # IDs / Usernames
readonly MOCHA_LAVENDER='\033[38;2;180;190;254m' # Folders / Groups
DEBUG="false"
ENABLE_BACKUP="false"
BACKUP_DIR="${HOME}"
TEST_MODE="false"
VERBOSE="false"
BAR_CHAR='█'
EMPTY_CHAR=' '

# Logging function
function log() {
  local type="$1"
  local color="$RESET"

  if [ "${type}" = "DEBU" ] && [ "${DEBUG}" != "true" ]; then
    return 0
  fi

  case "$type" in
    INFO)
      color="$MOCHA_BLUE";;
    WARN)
      color="$MOCHA_YELLOW";;
    ERRO)
      color="$MOCHA_RED";;
    DEBU)
      color="$MOCHA_LAVENDER";;
    *)
      type="LOGS";;
  esac

  if [[ -t 0 ]]; then
    local message="$2"
    echo -e "${color}${type}${RESET}[$(date +'%Y-%m-%d %H:%M:%S')] ${message}"
  else
    while IFS= read -r line; do
      echo -e "${color}${type}${RESET}[$(date +'%Y-%m-%d %H:%M:%S')] ${line}"
    done
  fi
}

# Progress Bar Functions
# Source: https://github.com/bahamas10/ysap/raw/refs/heads/main/code/2025-09-03-progress-bar-2/progress-bar

function progress-bar() {
	local current=$1
	local len=$2

    if [[ "$len" -eq 0 ]]; then len=1; fi

	local perc_done=$((current * 100 / len))

	local suffix=" $current/$len ($perc_done%)"

	local length=$((COLUMNS - ${#suffix} - 2))
    if [[ "$length" -lt 0 ]]; then length=0; fi

	local num_bars=$((perc_done * length / 100))

	local i
	local s='['
	for ((i = 0; i < num_bars; i++)); do
		s+=$BAR_CHAR
	done
	for ((i = num_bars; i < length; i++)); do
		s+=$EMPTY_CHAR
	done
	s+=']'
	s+=$suffix

	printf '\e7' # save the cursor location
	  printf '\e[%d;%dH' "$LINES" 0 # move cursor to the bottom line
	  printf '\e[0K' # clear the line
	  printf '%s' "$s" # print the progress bar
	printf '\e8' # restore the cursor location
}

function init-term() {
    shopt -s checkwinsize
    (:) # update LINES and COLUMNS
	printf '\n' # ensure we have space for the scrollbar
	  printf '\e7' # save the cursor location
	    printf '\e[%d;%dr' 0 "$((LINES - 1))" # set the scrollable region (margin)
	  printf '\e8' # restore the cursor location
	printf '\e[1A' # move cursor up
}

function deinit-term() {
    shopt -s checkwinsize
    (:)
	printf '\e7' # save the cursor location
	  printf '\e[%d;%dr' 0 "$LINES" # reset the scrollable region (margin)
	  printf '\e[%d;%dH' "$LINES" 0 # move cursor to the bottom line
	  printf '\e[0K' # clear the line
	printf '\e8' # reset the cursor location
}

# Checks if a command exists.
function commandExists() {
  command -v "$1" >/dev/null 2>&1
}

function check_dependencies() {
  log "INFO" "Checking dependencies..."
  if ! commandExists lpass ; then
    log "ERRO" "Required dependency 'lpass' (LastPass CLI) is not installed." >&2
    exit 1
  fi

  if commandExists pass; then
    PASS_CMD="pass"
  elif commandExists gopass; then
    PASS_CMD="gopass"
  else
    log "ERRO" "Required dependency 'pass' (Unix Password Store) or 'gopass' is not installed." >&2
    exit 1
  fi

  if ! commandExists jq ; then
    log "ERRO" "Required dependency 'jq' is not installed. Please install it." >&2
    exit 1
  fi
  if ! commandExists base64 ; then
    log "ERRO" "Required dependency 'base64' is not installed." >&2
    exit 1
  fi
  log "INFO" "All dependencies are installed. Using '${PASS_CMD}'."
}


# Function to load environment variables from a .env file
function load_env_file() {
  local env_file="./.env"
  if [[ -f "${env_file}" ]]; then
    log "INFO" "Loading environment variables from ${env_file}..."
    while IFS= read -r line; do
      if [[ -n "${line}" && "${line}" != \#* ]]; then
        eval "export ${line}" # Use eval to correctly export KEY=VALUE pairs
      fi
    done < "${env_file}"
  else
    log "WARN" "No .env file found at ${env_file}. Skipping environment variable loading."
  fi
}

# Normalize a string: lowercase, replace spaces with hyphens, squeeze hyphens, remove special chars
function normalize_name() {
  local input="$1"
  # Lowercase
  local cleaned="${input,,}"
  # Replace slashes with underscores
  cleaned="${cleaned//\//_}"
  # Replace spaces with hyphens
  cleaned="${cleaned// /-}"
  # Remove top-level domain (e.g., .com, .org)
  cleaned="${cleaned%.*}"
  # Squeeze multiple hyphens and remove leading/trailing hyphens using tr and sed
  cleaned=$(echo "$cleaned" | tr -s '-' | sed 's/^-//;s/-$//')
  echo "$cleaned"
}

function usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

A Bash utility to perform a one-way snapshot of a LastPass vault (lpass)
into the standard Unix Password Store (pass).

Options:
  -d, --debug           Enable debug logging.
  -b, --backup          Enable backup of the password store before import.
  --backup-dir DIR      Directory to store the backup (default: $HOME).
  -t, --test            Enable test mode (simulate import without changes).
  -v, --verbose         Enable verbose output (print entry names).
  -u, --username NAME   LastPass username.
  -h, --help            Show this help message and exit.

EOF
  exit 0
}

function parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--debug)
        DEBUG="true"
        set -x # Enable shell execution tracing
        shift
        ;;
      -b|--backup)
        ENABLE_BACKUP="true"
        shift
        ;;
      --backup-dir)
        BACKUP_DIR="$2"
        shift 2
        ;;
      -t|--test)
        TEST_MODE="true"
        shift
        ;;
      -v|--verbose)
        VERBOSE="true"
        shift
        ;;
      -u|--username)
        LPASS_USERNAME="$2"
        shift 2
        ;;
      -h|--help)
        usage
        ;;
      *)
        log "ERRO" "Unknown option: $1"
        usage
        ;;
    esac
  done
}

# Create an encrypted backup of the password store
function create_backup() {
  if [[ "${ENABLE_BACKUP}" != "true" ]]; then
    log "INFO" "Backup disabled."
    return 0
  fi

  local pass_dir="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
  
  if [[ ! -d "${pass_dir}" && "${PASS_CMD}" == "gopass" ]]; then
    pass_dir="${HOME}/.local/share/gopass/stores/root"
  fi

  if [[ ! -d "${pass_dir}" ]]; then
    log "WARN" "Password store directory not found at ${pass_dir}. Skipping backup."
    return 1
  fi

  local gpg_id_file="${pass_dir}/.gpg-id"
  if [[ ! -f "${gpg_id_file}" ]]; then
    log "ERRO" "GPG ID file not found at ${gpg_id_file}. Cannot encrypt backup."
    return 1
  fi

  local gpg_id
  gpg_id=$(head -n 1 "${gpg_id_file}")

  local timestamp
  timestamp=$(date +'%Y-%m-%d_%H-%M-%S')
  local backup_filename="pass-backup-${timestamp}.tar.gz.gpg"
  local backup_path="${BACKUP_DIR}/${backup_filename}"

  log "INFO" "Creating backup of password store at ${backup_path}..."

  # Tar and encrypt
  # We want to tar the contents of pass_dir.
  # To avoid storing full absolute paths, -C is useful.
  if tar -czf - -C "${pass_dir}" . | gpg --encrypt --recipient "${gpg_id}" --output "${backup_path}"; then
    log "INFO" "Backup created successfully."
  else
    log "ERRO" "Backup failed."
    return 1
  fi
}

# Check LastPass status and login if needed
function check_and_login_lpass() {
  # Check LastPass login status and log in if necessary
  if ! lpass status >/dev/null 2>&1; then
    log "INFO" "Not logged into LastPass. Attempting to log in..."
    if [[ -z "${LPASS_USERNAME}" ]]; then
      log "ERRO" "LPASS_USERNAME environment variable is not set. Please set it in .env or ensure you are logged into LastPass manually." >&2
      exit 1
    fi
    log "INFO" "Attempting to log in as ${LPASS_USERNAME}..."
    if ! lpass login "${LPASS_USERNAME}" ; then
      log "ERRO" "Failed to log in to LastPass as ${LPASS_USERNAME}. Please check your credentials or run 'lpass login' manually." >&2
      exit 1
    fi
  else
    log "INFO" "Already logged into LastPass."
  fi
}

# Process LastPass export and import into pass
function process_lpass_export() {
  log "INFO" "Exporting data from LastPass to temporary file..."
  
  local temp_export_file
  temp_export_file=$(mktemp)
  
  # Ensure temp file is removed on exit (or return)
  # Use double quotes to expand variable NOW, avoiding scope issues at exit
  trap "rm -f '${temp_export_file}'; deinit-term 2>/dev/null" EXIT

  # Export to temp file first to avoid multiple password prompts and race conditions
  # lpass export outputs CSV. We explicitly request fields.
  if ! lpass export --color=never --fields="url,username,password,extra,name,grouping,fav,id,attachpresent" > "${temp_export_file}"; then
      log "ERRO" "Failed to export data from LastPass."
      log "WARN" "If you see 'Could not unbase64 the given bytes', try running 'lpass logout -f' and logging in again."
      rm -f "${temp_export_file}"
      return 1
  fi

  log "INFO" "Counting total items..."
  
  local total_items
  # Use awk to count records correctly, handling multiline CSV fields
  total_items=$(awk '
    BEGIN {
      record = ""
      count = 0
    }
    {
      record = record $0 "\n"
      t = record
      gsub(/[^"]/, "", t)
      if (length(t) % 2 == 0) {
        count++
        record = ""
      }
    }
    END {
      print count
    }
  ' "${temp_export_file}")
  
  # Decrement 1 for header if file is not empty
  if [[ "$total_items" -gt 0 ]]; then
    ((total_items--))
  fi
  
  log "INFO" "Found ${total_items} items. Starting import to password store..."

  # Initialize terminal for progress bar if we are in a terminal
  if [[ -t 1 ]]; then
    init-term
    # trap is already set above
  fi

  local current_item=0

  # We use awk to robustly parse CSV from the temp file
  
  while IFS= read -u 9 -d '' -r URL; do
    # Read the rest of the 9 fields
    IFS= read -u 9 -d '' -r USERNAME
    IFS= read -u 9 -d '' -r PASSWORD
    IFS= read -u 9 -d '' -r EXTRA
    IFS= read -u 9 -d '' -r NAME
    IFS= read -u 9 -d '' -r GROUPING
    IFS= read -u 9 -d '' -r FAV_ITEM
    IFS= read -u 9 -d '' -r ID
    IFS= read -u 9 -d '' -r ATTACHPRESENT

    # Skip Header if it matches "url" and "username" (simple check)
    if [[ "${URL}" == "url" && "${USERNAME}" == "username" ]]; then
      continue
    fi
    
    ((++current_item))
    if [[ -t 1 ]]; then
        progress-bar "$current_item" "$total_items"
    fi

    # If NAME is empty, skip
    if [[ -z "${NAME}" ]]; then
       if [[ -z "${URL}" && -z "${USERNAME}" ]]; then
         continue
       fi
    fi

    # Sanitize NAME for pass path using normalize_name
    local PASS_PATH
    PASS_PATH=$(normalize_name "${NAME}")
    if [[ -z "${PASS_PATH}" ]]; then
        log "WARN" "Skipping entry with empty normalized name. Original: '${NAME}', URL: '${URL}'"
        continue
    fi

    if [[ "${VERBOSE}" == "true" ]]; then
      log "INFO" "Processing '${PASS_PATH}'..."
    fi

    # Check for attachments
    if [[ "${ATTACHPRESENT}" == "1" ]]; then
      log "WARN" "Entry '${PASS_PATH}' (LastPass ID: ${ID}) has attachments. These are NOT imported."
    fi

    # Construct the content for 'pass insert'
    local PASS_CONTENT="${PASSWORD}"
    if [[ -n "${USERNAME}" ]]; then
      PASS_CONTENT="${PASS_CONTENT}
username: ${USERNAME}"
    fi
    if [[ -n "${URL}" ]]; then
      PASS_CONTENT="${PASS_CONTENT}
url: ${URL}"
    fi
    if [[ -n "${EXTRA}" ]]; then
      PASS_CONTENT="${PASS_CONTENT}
extra: ${EXTRA}"
    fi

    if [[ "${TEST_MODE}" == "true" ]]; then
      log "INFO" "[TEST MODE] Would import '${PASS_PATH}' into password store."
      log "DEBU" "[TEST MODE] Content for '${PASS_PATH}':"
      echo "${PASS_CONTENT}"
    else
      # log "INFO" "Importing '${PASS_PATH}' into pass..." 
      # Commented out LOG INFO in non-test mode to not spam output with progress bar, 
      # or we could print it and let the progress bar overwrite/scroll. 
      # Given the progress bar logic uses fixed bottom lines, scrolling logs might break it visually 
      # unless handled carefully. For now, let's rely on progress bar.
      
      # Insert into password store, force overwrite, and accept multiline input
      if ! printf '%s' "${PASS_CONTENT}" | ${PASS_CMD} insert -f --multiline "${PASS_PATH}" >/dev/null 2>&1 ; then
        log "ERRO" "Failed to import '${PASS_PATH}' into password store." >&2
      fi
    fi
  done 9< <(cat "${temp_export_file}" | \
  awk '
    BEGIN {
      # Initialize empty record
      record = ""
    }
    {
      # Append line to record (restore newline consumed by awk read)
      record = record $0 "\n"
      
      # Check if quotes are balanced in the accumulated record
      # Create a temp string with only quotes
      t = record
      gsub(/[^"]/, "", t)
      
      # If quote count is even, we have a complete record (or potentially multiple, but CSV implies one record per line set)
      if (length(t) % 2 == 0) {
        # Process the complete record
        len = length(record)
        field = ""
        in_quote = 0
        
        # Remove the very last newline added if it matches the file end/record end
        # But we process char by char
        
        for (i=1; i<=len; i++) {
          c = substr(record, i, 1)
          
          if (in_quote) {
            if (c == "\"") {
              if (i+1 <= len && substr(record, i+1, 1) == "\"") {
                # Escaped quote ("")
                field = field "\""
                i++
              } else {
                # End of quote
                in_quote = 0
              }
            } else {
              field = field c
            }
          } else {
            if (c == "\"") {
              in_quote = 1
            } else if (c == ",") {
              # End of field
              printf "%s%c", field, 0
              field = ""
            } else if (i == len) {
              # End of record (last char is the \n we added)
              # We ignore the trailing \n for the last field content
              # But we print the field
              printf "%s%c", field, 0
              field = ""
            } else {
              field = field c
            }
          }
        }
        
        # Reset record for next
        record = ""
      }
      # If quotes are odd, we continue to next awk line (accumulating)
    }
  ')
  
  if [[ -t 1 ]]; then
    deinit-term
    trap - EXIT # Remove trap
    rm -f "${temp_export_file}"
  fi
}

# Main function to orchestrate the script execution
function main() {
  log "INFO" "Starting lpass-to-pass-snapshot script..."
  load_env_file # Load .env variables
  parse_args "$@" # Parse command line arguments (overrides .env)
  
  check_dependencies

  create_backup

  check_and_login_lpass
  process_lpass_export

  log "INFO" "Script finished."
}

# Call main to start the script
main "$@"
