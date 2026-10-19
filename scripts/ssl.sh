#!/usr/bin/env bash
# ============================================================================
# 3xui-cloudflare-provisioner - Automated SSL Certificate via acme.sh & Cloudflare
# ============================================================================

CERT_DIR="/etc/ssl/v2ray"

install_acme() {
    if [[ -f "/root/.acme.sh/acme.sh" ]]; then
        log_info "acme.sh is already installed."
        return 0
    fi

    log_step "Installing acme.sh certificate manager"
    local acme_email="admin-$(random_lowercase 6)@$(echo "$DOMAIN" | tr -d '[:space:]')"
    curl -sSL https://get.acme.sh | sh -s email="$acme_email" >/dev/null 2>&1 || {
        log_warn "Standard acme.sh installer had non-zero exit; verifying binary..."
    }

    if [[ ! -f "/root/.acme.sh/acme.sh" ]]; then
        log_error "Failed to install acme.sh."
        return 1
    fi

    /root/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1 || true
    log_success "acme.sh installed and configured."
}

issue_cloudflare_ssl() {
    local token="$1"
    local zone_id="$2"
    local full_domain="$3"

    install_acme

    log_step "Issuing Let's Encrypt ECC certificate for ${full_domain}"
    mkdir -p "$CERT_DIR"

    export CF_Token="$token"
    export CF_Zone_ID="$zone_id"

    # Issue ECC certificate using Cloudflare DNS-01 API
    /root/.acme.sh/acme.sh --issue \
        --dns dns_cf \
        -d "$full_domain" \
        --keylength ec-256 \
        --server letsencrypt \
        --dnssleep 15 || {
            log_warn "Let's Encrypt issue attempt failed; retrying with ZeroSSL..."
            /root/.acme.sh/acme.sh --issue \
                --dns dns_cf \
                -d "$full_domain" \
                --keylength ec-256 \
                --dnssleep 15
        }

    # Install certificate to permanent directory
    /root/.acme.sh/acme.sh --install-cert -d "$full_domain" --ecc \
        --key-file "$CERT_DIR/cert.key" \
        --fullchain-file "$CERT_DIR/cert.crt" >/dev/null

    if [[ ! -s "$CERT_DIR/cert.crt" || ! -s "$CERT_DIR/cert.key" ]]; then
        log_error "Certificate files not found in ${CERT_DIR}."
        return 1
    fi

    chmod 644 "$CERT_DIR/cert.crt"
    chmod 600 "$CERT_DIR/cert.key"

    log_success "Valid SSL Certificate issued and installed in ${CERT_DIR}."
    return 0
}
