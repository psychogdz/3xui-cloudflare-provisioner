#!/usr/bin/env bash
# ============================================================================
# 3xui-cloudflare-provisioner - Common utilities, logging, and helpers
# ============================================================================

# ANSI color codes
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

LOG_FILE="/var/log/3xui-provisioner.log"
INFO_FILE="/root/provisioner-info.txt"

init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/3xui-provisioner.log"
    chmod 600 "$LOG_FILE" 2>/dev/null || true
}

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" >> "$LOG_FILE"
}

log_info() {
    printf "${BLUE}ℹ${NC} %s\n" "$1"
    log "INFO" "$1"
}

log_step() {
    printf "\n${BOLD}${CYAN}▶ %s${NC}\n" "$1"
    log "STEP" "$1"
}

log_success() {
    printf "${GREEN}✔ %s${NC}\n" "$1"
    log "SUCCESS" "$1"
}

log_warn() {
    printf "${YELLOW}⚠ %s${NC}\n" "$1"
    log "WARN" "$1"
}

log_error() {
    printf "${RED}✖ %s${NC}\n" "$1" >&2
    log "ERROR" "$1"
}

on_error_trap() {
    local exit_code="$1"
    local line_no="$2"
    log_error "Installation interrupted at line ${line_no} with exit code ${exit_code}."
    printf "${YELLOW}Check the log file for full details: ${LOG_FILE}${NC}\n"
    exit "$exit_code"
}

random_alphanumeric() {
    local length="${1:-16}"
    LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length" || true
}

random_lowercase() {
    local length="${1:-8}"
    LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c "$length" || true
}

random_hex() {
    local length="${1:-8}"
    LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c "$length" || true
}

get_public_ip() {
    local ip=""
    for endpoint in \
        "https://api.ipify.org" \
        "https://icanhazip.com" \
        "https://ifconfig.me/ip" \
        "https://ipinfo.io/ip"; do
        ip="$(curl -s4m 4 "$endpoint" 2>/dev/null | tr -d '[:space:]')" || true
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    echo ""
    return 1
}

# Python helper for robust JSON manipulation without requiring jq
json_extract() {
    local json_str="$1"
    local key_path="$2"
    python3 -c "
import sys, json
try:
    data = json.loads('''$json_str''')
    for k in '$key_path'.split('.'):
        if not k: continue
        if isinstance(data, list):
            data = data[int(k)]
        else:
            data = data[k]
    if isinstance(data, (dict, list)):
        print(json.dumps(data))
    else:
        print(data)
except Exception:
    sys.exit(1)
" 2>/dev/null || echo ""
}
