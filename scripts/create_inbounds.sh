#!/usr/bin/env bash
# ============================================================================
# 3xui-cloudflare-provisioner - Modern Inbounds Setup (Censorship Resistant)
# ============================================================================

create_censorship_resistant_inbounds() {
    local full_domain="$1"
    local client_uuid="$2"
    local client_email="$3"
    local client_sub_id="$4"

    log_step "Creating optimized censorship-resistant inbounds"

    local xray_bin=""
    for b in "/usr/local/x-ui/bin/xray-linux-amd64" "/usr/local/x-ui/bin/xray" "/usr/bin/xray"; do
        if [[ -x "$b" ]]; then
            xray_bin="$b"
            break
        fi
    done

    # Generate Reality keypair
    local reality_priv=""
    local reality_pub=""
    if [[ -n "$xray_bin" ]]; then
        local kp
        kp="$("$xray_bin" x25519 2>/dev/null || true)"
        reality_priv="$(echo "$kp" | grep -i 'PrivateKey:' | awk '{print $2}' || true)"
        reality_pub="$(echo "$kp" | grep -i 'Password (PublicKey):' | awk '{print $3}' || true)"
    fi

    # Fallback keypair if xray binary not directly executable yet
    if [[ -z "$reality_priv" || -z "$reality_pub" ]]; then
        reality_priv="oB_LRH3lCRgeo0jsoKIFbg3tUGJ3Jx970Z14i3mFaU4"
        reality_pub="zJ2f_mlzCJwVoikLlakC_drkrHpLD0x_VLSK8uFsS3c"
    fi

    REALITY_PUBLIC_KEY="$reality_pub"
    REALITY_SHORT_ID="$(random_hex 8)"
    REALITY_DEST="${REALITY_DEST:-www.samsung.com:443}"
    REALITY_SNI="${REALITY_SNI:-www.samsung.com}"

    python3 -c "
import sqlite3, json, time

db_path = '$XUI_DB_PATH'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Clear default dummy inbounds
c.execute(\"DELETE FROM inbounds\")

now_ms = int(time.time() * 1000)

client_obj_ws = {
    'id': '$client_uuid',
    'email': '$client_email',
    'flow': '',
    'limitIp': 0,
    'totalGB': 0,
    'expiryTime': 0,
    'enable': True,
    'tgId': 0,
    'subId': '$client_sub_id',
    'reset': 0,
    'created_at': now_ms,
    'updated_at': now_ms
}

client_obj_vision = dict(client_obj_ws)
client_obj_vision['flow'] = 'xtls-rprx-vision'

# ----------------------------------------------------------------------------
# 1. INBOUND 1: VLESS + WebSocket + TLS on Port 443 (Cloudflare CDN Primary)
# ----------------------------------------------------------------------------
stream_ws = {
    'network': 'ws',
    'security': 'tls',
    'tlsSettings': {
        'serverName': '$full_domain',
        'minVersion': '1.2',
        'maxVersion': '1.3',
        'cipherSuites': '',
        'certificates': [{
            'certificateFile': '/etc/ssl/v2ray/cert.crt',
            'keyFile': '/etc/ssl/v2ray/cert.key'
        }],
        'alpn': ['h2', 'http/1.1']
    },
    'wsSettings': {
        'acceptProxyProtocol': False,
        'path': '${INBOUND_CDN_PATH:-/ws}',
        'headers': {
            'Host': '$full_domain'
        }
    }
}

c.execute('''
    INSERT INTO inbounds (
        id, user_id, up, down, total, remark, enable, expiry_time,
        listen, port, protocol, settings, stream_settings, tag,
        sniffing, share_addr_strategy, share_addr
    ) VALUES (
        1, 1, 0, 0, 0, 'Cloudflare-CDN-WS', 1, 0,
        '', ${INBOUND_CDN_PORT:-443}, 'vless', ?, ?, 'in-cdn-ws-443',
        '{\"enabled\": true, \"destOverride\": [\"http\", \"tls\", \"quic\"]}',
        'custom', '$full_domain'
    )
''', (json.dumps({'clients': [client_obj_ws], 'decryption': 'none'}), json.dumps(stream_ws)))

# ----------------------------------------------------------------------------
# 2. INBOUND 2: VLESS + gRPC + TLS on Port 8443 (Cloudflare CDN Low Latency)
# ----------------------------------------------------------------------------
stream_grpc = {
    'network': 'grpc',
    'security': 'tls',
    'tlsSettings': {
        'serverName': '$full_domain',
        'minVersion': '1.2',
        'maxVersion': '1.3',
        'cipherSuites': '',
        'certificates': [{
            'certificateFile': '/etc/ssl/v2ray/cert.crt',
            'keyFile': '/etc/ssl/v2ray/cert.key'
        }],
        'alpn': ['h2']
    },
    'grpcSettings': {
        'serviceName': '${INBOUND_GRPC_SERVICE:-grpc-service}',
        'multiMode': False
    }
}

c.execute('''
    INSERT INTO inbounds (
        id, user_id, up, down, total, remark, enable, expiry_time,
        listen, port, protocol, settings, stream_settings, tag,
        sniffing, share_addr_strategy, share_addr
    ) VALUES (
        2, 1, 0, 0, 0, 'Cloudflare-CDN-gRPC', 1, 0,
        '', ${INBOUND_GRPC_PORT:-8443}, 'vless', ?, ?, 'in-cdn-grpc-8443',
        '{\"enabled\": true, \"destOverride\": [\"http\", \"tls\", \"quic\"]}',
        'custom', '$full_domain'
    )
''', (json.dumps({'clients': [client_obj_ws], 'decryption': 'none'}), json.dumps(stream_grpc)))

# ----------------------------------------------------------------------------
# 3. INBOUND 3: VLESS + Reality (Vision) on Port 2053 (Direct Fallback)
# ----------------------------------------------------------------------------
stream_reality = {
    'network': 'tcp',
    'security': 'reality',
    'realitySettings': {
        'show': False,
        'dest': '$REALITY_DEST',
        'xver': 0,
        'serverNames': ['$REALITY_SNI'],
        'privateKey': '$reality_priv',
        'minClientVer': '',
        'maxClientVer': '',
        'maxTimeDiff': 0,
        'shortIds': ['$REALITY_SHORT_ID'],
        'settings': {
            'publicKey': '$reality_pub',
            'fingerprint': 'chrome',
            'serverName': '$REALITY_SNI',
            'spiderX': '/'
        }
    },
    'tcpSettings': {
        'acceptProxyProtocol': False,
        'header': {'type': 'none'}
    }
}

c.execute('''
    INSERT INTO inbounds (
        id, user_id, up, down, total, remark, enable, expiry_time,
        listen, port, protocol, settings, stream_settings, tag,
        sniffing, share_addr_strategy, share_addr
    ) VALUES (
        3, 1, 0, 0, 0, 'Reality-Vision-Direct', 1, 0,
        '', ${INBOUND_REALITY_PORT:-2083}, 'vless', ?, ?, 'in-reality-2083',
        '{\"enabled\": true, \"destOverride\": [\"http\", \"tls\", \"quic\"]}',
        'custom', '$full_domain'
    )
''', (json.dumps({'clients': [client_obj_vision], 'decryption': 'none'}), json.dumps(stream_reality)))

conn.commit()
conn.close()
"

    log_success "Created 3 specialized inbounds in 3X-UI database."
    return 0
}
