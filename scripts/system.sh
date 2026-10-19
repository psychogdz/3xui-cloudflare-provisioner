#!/usr/bin/env bash
# ============================================================================
# 3xui-cloudflare-provisioner - System preparation, dependencies, and BBR
# ============================================================================

check_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)."
        exit 1
    fi
}

check_system_compat() {
    log_step "Checking system compatibility"
    if [[ ! -f /etc/os-release ]]; then
        log_error "Unable to detect Linux distribution (/etc/os-release not found)."
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        ubuntu|debian)
            log_success "Detected supported OS: ${PRETTY_NAME:-$ID}"
            ;;
        almalinux|rocky|centos|fedora)
            log_warn "Detected RHEL-family OS: ${PRETTY_NAME:-$ID}. Debian/Ubuntu is recommended, but proceeding."
            ;;
        *)
            log_warn "Untested distribution: ${PRETTY_NAME:-unknown}. Proceeding with standard apt/package steps."
            ;;
    esac
}

install_dependencies() {
    log_step "Installing essential packages"
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq || true
        apt-get install -y -qq \
            curl \
            socat \
            cron \
            sqlite3 \
            python3 \
            openssl \
            tar \
            gzip \
            ca-certificates \
            ufw >/dev/null 2>&1 || {
                log_warn "Quiet install had warnings; retrying in verbose mode..."
                apt-get install -y curl socat cron sqlite3 python3 openssl tar gzip ca-certificates ufw
            }
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q curl socat cronie sqlite python3 openssl tar gzip ca-certificates || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q curl socat cronie sqlite python3 openssl tar gzip ca-certificates || true
    fi

    log_success "All required dependencies installed."
}

enable_bbr() {
    if [[ "${ENABLE_BBR:-true}" != "true" ]]; then
        return 0
    fi

    log_step "Checking TCP BBR congestion control"
    local current_cc
    current_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '')"
    if [[ "$current_cc" == "bbr" ]]; then
        log_success "TCP BBR is already enabled."
        return 0
    fi

    log_info "Enabling TCP BBR and FQ queue discipline..."
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null || true

    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1 || true

    current_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '')"
    if [[ "$current_cc" == "bbr" ]]; then
        log_success "TCP BBR enabled successfully."
    else
        log_warn "Could not activate BBR on this kernel (current: ${current_cc:-unknown}). Continuing."
    fi
}

configure_firewall() {
    local panel_port="${PANEL_PORT:-2053}"
    local sub_port="${SUB_PORT:-2096}"
    local cdn_port="${INBOUND_CDN_PORT:-443}"
    local grpc_port="${INBOUND_GRPC_PORT:-8443}"

    log_step "Configuring firewall rules"
    if command -v ufw >/dev/null 2>&1; then
        # Ensure SSH is open
        ufw allow 22/tcp >/dev/null 2>&1 || true
        # Open web ports
        ufw allow 80/tcp >/dev/null 2>&1 || true
        ufw allow "${cdn_port}"/tcp >/dev/null 2>&1 || true
        ufw allow "${grpc_port}"/tcp >/dev/null 2>&1 || true
        ufw allow "${panel_port}"/tcp >/dev/null 2>&1 || true
        ufw allow "${sub_port}"/tcp >/dev/null 2>&1 || true
        log_success "Firewall rules applied for ports 22, 80, ${cdn_port}, ${grpc_port}, ${panel_port}, ${sub_port}."
    fi
}
