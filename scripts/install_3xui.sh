#!/usr/bin/env bash
# ============================================================================
# 3xui-cloudflare-provisioner - Official 3X-UI Panel installation
# ============================================================================

install_3xui_panel() {
    log_step "Installing official 3X-UI panel"

    if systemctl is-active --quiet x-ui; then
        log_info "3X-UI is already installed and running. Preserving existing installation."
        systemctl stop x-ui 2>/dev/null || true
        return 0
    fi

    log_info "Downloading and executing official 3X-UI installer..."
    # The official 3x-ui installer non-interactive install
    curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh | bash -s -- -y >/dev/null 2>&1 || {
        log_warn "Direct curl pipe encountered warning; retrying via temporary script..."
        local tmp_sh
        tmp_sh="$(mktemp /tmp/3xui-install.XXXXXX.sh)"
        curl -sSL https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$tmp_sh"
        bash "$tmp_sh" -y
        rm -f "$tmp_sh" 2>/dev/null || true
    }

    if [[ ! -d "/usr/local/x-ui" && ! -d "/etc/x-ui" ]]; then
        log_error "3X-UI installation could not be verified."
        return 1
    fi

    # Temporarily stop service for custom configuration
    systemctl stop x-ui 2>/dev/null || true
    log_success "3X-UI base installation completed."
    return 0
}
