#!/usr/bin/env bash
# ============================================================================
# 3xui-cloudflare-provisioner - Client Identity and UUID Generation
# ============================================================================

generate_client_identity() {
    log_step "Generating client credentials"

    CLIENT_UUID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
    CLIENT_EMAIL="${CLIENT_EMAIL:-user_$(random_lowercase 6)}"
    CLIENT_SUB_ID="$(random_alphanumeric 16)"

    log_info "Client UUID: ${CLIENT_UUID}"
    log_info "Client Email: ${CLIENT_EMAIL}"
    log_info "Client Sub ID: ${CLIENT_SUB_ID}"

    log_success "Client credentials prepared."
}
