#!/usr/bin/env bash
# shellcheck disable=SC2034
# ============================================================================
# 3xui-cloudflare-provisioner - Next-Gen Censorship-Resistant 3X-UI Provisioner
#
# Automatically provisions an Ubuntu/Debian VPS with:
#   * Official 3X-UI panel with dynamic, cryptographically secure credentials
#   * Cloudflare CDN Proxied DNS (A record) automated via Cloudflare API
#   * Genuine Let's Encrypt ECC Certificate automated via DNS-01 API
#   * Battle-tested VLESS + WebSocket + TLS (Port 443) bypass for Iranian ISPs
#   * Multiplexed VLESS + gRPC + TLS (Port 8443) for low-latency streaming
#   * Direct VLESS + Reality Vision fallback (Port 2053)
#   * TCP BBR congestion control optimization
#
# One-liner usage:
#   curl -sSL https://raw.githubusercontent.com/psychogdz/3xui-cloudflare-provisioner/main/install.sh | sudo bash
#
# Automated usage with flags:
#   sudo ./install.sh --domain example.com --cf-token <token> --yes
# ============================================================================
set -Eeuo pipefail

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Download scripts if running via standalone one-liner pipe without repo cloned
if [[ -z "$SCRIPT_DIR" || ! -f "$SCRIPT_DIR/scripts/common.sh" ]]; then
    REPO_RAW_URL="https://raw.githubusercontent.com/psychogdz/3xui-cloudflare-provisioner/main"
    TMP_DIR="$(mktemp -d /tmp/3xui-provisioner.XXXXXX)"
    mkdir -p "$TMP_DIR/scripts"

    for script_name in common.sh system.sh cloudflare.sh ssl.sh install_3xui.sh \
                       configure_panel.sh create_client.sh create_inbounds.sh \
                       subscription.sh summary.sh; do
        curl -sSL "${REPO_RAW_URL}/scripts/${script_name}" -o "$TMP_DIR/scripts/${script_name}" || {
            echo "Failed to download scripts from GitHub." >&2
            exit 1
        }
    done
    SCRIPT_DIR="$TMP_DIR"
fi

# Load all modules
# shellcheck source=scripts/common.sh
. "$SCRIPT_DIR/scripts/common.sh"
# shellcheck source=scripts/system.sh
. "$SCRIPT_DIR/scripts/system.sh"
# shellcheck source=scripts/cloudflare.sh
. "$SCRIPT_DIR/scripts/cloudflare.sh"
# shellcheck source=scripts/ssl.sh
. "$SCRIPT_DIR/scripts/ssl.sh"
# shellcheck source=scripts/install_3xui.sh
. "$SCRIPT_DIR/scripts/install_3xui.sh"
# shellcheck source=scripts/configure_panel.sh
. "$SCRIPT_DIR/scripts/configure_panel.sh"
# shellcheck source=scripts/create_client.sh
. "$SCRIPT_DIR/scripts/create_client.sh"
# shellcheck source=scripts/create_inbounds.sh
. "$SCRIPT_DIR/scripts/create_inbounds.sh"
# shellcheck source=scripts/subscription.sh
. "$SCRIPT_DIR/scripts/subscription.sh"
# shellcheck source=scripts/summary.sh
. "$SCRIPT_DIR/scripts/summary.sh"

trap 'on_error_trap $? $LINENO' ERR

show_help() {
    cat <<EOF
3xui-cloudflare-provisioner - Automated Censorship-Resistant VPS Provisioner

Usage:
  sudo ./install.sh [options]

Options:
  -d, --domain <domain>        Root domain registered in Cloudflare (e.g. example.com)
  -t, --cf-token <token>       Cloudflare API Token (Zone:DNS:Edit permission)
  -s, --subdomain <prefix>     Subdomain prefix (default: auto-generated e.g. node-7f2a)
  -z, --zone-id <zone_id>      Cloudflare Zone ID (optional, auto-queried if omitted)
  -c, --config <file>          Path to config.env configuration file
  -p, --panel-port <port>      3X-UI web panel port (default: 2053)
  -u, --username <name>        Admin username (default: random admin_xxxx)
  -P, --password <pass>        Admin password (default: random 24-char string)
  --bbr <true/false>           Enable/disable TCP BBR (default: true)
  -y, --yes, --non-interactive Non-interactive mode (fail instead of prompting)
  -h, --help                   Show this help menu

Examples:
  Interactive installation:
    sudo ./install.sh

  Fully automated one-liner:
    sudo ./install.sh --domain viomet.online --cf-token cfut_xxx --subdomain vpn --yes
EOF
}

# ----------------------------------------------------------------------------
# Command line arguments parsing
# ----------------------------------------------------------------------------
DOMAIN="${DOMAIN:-}"
CF_TOKEN="${CF_TOKEN:-}"
CF_ZONE_ID="${CF_ZONE_ID:-}"
SUBDOMAIN="${SUBDOMAIN:-}"
PANEL_PORT="${PANEL_PORT:-2053}"
PANEL_USERNAME="${PANEL_USERNAME:-}"
PANEL_PASSWORD="${PANEL_PASSWORD:-}"
ENABLE_BBR="${ENABLE_BBR:-true}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--domain)
            DOMAIN="$2"; shift 2 ;;
        -t|--cf-token)
            CF_TOKEN="$2"; shift 2 ;;
        -z|--zone-id)
            CF_ZONE_ID="$2"; shift 2 ;;
        -s|--subdomain)
            SUBDOMAIN="$2"; shift 2 ;;
        -c|--config)
            if [[ -f "$2" ]]; then
                # shellcheck disable=SC1090
                . "$2"
            fi
            shift 2 ;;
        -p|--panel-port)
            PANEL_PORT="$2"; shift 2 ;;
        -u|--username)
            PANEL_USERNAME="$2"; shift 2 ;;
        -P|--password)
            PANEL_PASSWORD="$2"; shift 2 ;;
        --bbr)
            ENABLE_BBR="$2"; shift 2 ;;
        -y|--yes|--non-interactive)
            NON_INTERACTIVE="true"; shift ;;
        -h|--help)
            show_help; exit 0 ;;
        *)
            echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
    esac
done

# ----------------------------------------------------------------------------
# Initialization and interactive prompt fallback
# ----------------------------------------------------------------------------
init_logging
check_root

printf "\n"
printf "${BOLD}${CYAN}================================================================================${NC}\n"
printf "${BOLD}${CYAN}          3X-UI CLOUDFLARE PROVISIONER (ANTI-CENSORSHIP EDITION)                ${NC}\n"
printf "${BOLD}${CYAN}================================================================================${NC}\n"
printf "\n"

# Interactive prompt if domain or token are missing
if [[ -z "$DOMAIN" && "$NON_INTERACTIVE" != "true" ]]; then
    printf "${BOLD}${YELLOW}Please enter your domain registered on Cloudflare:${NC}\n"
    read -r -p "Domain (e.g. example.com): " DOMAIN
fi

if [[ -z "$CF_TOKEN" && "$NON_INTERACTIVE" != "true" ]]; then
    printf "${BOLD}${YELLOW}Please enter your Cloudflare API Token (Zone:DNS:Edit):${NC}\n"
    read -r -p "API Token: " CF_TOKEN
fi

if [[ -z "$SUBDOMAIN" && "$NON_INTERACTIVE" != "true" ]]; then
    printf "${BOLD}${YELLOW}Subdomain prefix (leave blank for random, e.g. node-ab12):${NC}\n"
    read -r -p "Subdomain [random]: " SUBDOMAIN
fi

if [[ -z "$DOMAIN" || -z "$CF_TOKEN" ]]; then
    log_error "Domain and Cloudflare API Token are required for censorship-resistant provisioning."
    exit 1
fi

# Clean domain and subdomain strings
DOMAIN="$(echo "$DOMAIN" | tr -d '[:space:]' | sed 's|^https*://||' | sed 's|/$||')"
if [[ -z "$SUBDOMAIN" ]]; then
    SUBDOMAIN="node-$(random_lowercase 4)"
fi

# Determine full domain
if [[ "$DOMAIN" == *"$SUBDOMAIN"* ]]; then
    FULL_DOMAIN="$DOMAIN"
else
    FULL_DOMAIN="${SUBDOMAIN}.${DOMAIN}"
fi

# ----------------------------------------------------------------------------
# Execution Pipeline
# ----------------------------------------------------------------------------
check_system_compat
install_dependencies
enable_bbr

log_step "Detecting Server Public IPv4"
SERVER_IP="$(get_public_ip)"
if [[ -z "$SERVER_IP" ]]; then
    log_error "Failed to detect public IPv4 address of this server."
    exit 1
fi
log_success "Server IPv4 detected: ${SERVER_IP}"

verify_cloudflare_token "$CF_TOKEN"

if [[ -z "$CF_ZONE_ID" ]]; then
    CF_ZONE_ID="$(get_zone_id "$CF_TOKEN" "$DOMAIN")"
fi
log_success "Cloudflare Zone ID resolved: ${CF_ZONE_ID}"

setup_cloudflare_dns "$CF_TOKEN" "$CF_ZONE_ID" "$FULL_DOMAIN" "$SERVER_IP"
issue_cloudflare_ssl "$CF_TOKEN" "$CF_ZONE_ID" "$FULL_DOMAIN"
install_3xui_panel
configure_panel_database "$FULL_DOMAIN"
generate_client_identity
create_censorship_resistant_inbounds "$FULL_DOMAIN" "$CLIENT_UUID" "$CLIENT_EMAIL" "$CLIENT_SUB_ID"
configure_firewall
start_and_verify_service "$SERVER_IP" "$FULL_DOMAIN"
print_and_save_summary "$SERVER_IP" "$FULL_DOMAIN"
