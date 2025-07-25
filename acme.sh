#!/bin/bash
set -eo pipefail
# =============== CONFIGURATION ===============
# Domain configuration
PRIMARY_DOMAIN="${PRIMARY_DOMAIN:-}"
WILDCARD_DOMAIN="${WILDCARD_DOMAIN:-}"
DOMAINS=("$PRIMARY_DOMAIN" "$WILDCARD_DOMAIN")

# Cloudflare configuration (from environment)
CF_TOKEN="${CF_TOKEN:-}"
CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-}"

# Yandex Cloud configuration (from environment)
YC_CERT_ID="${YC_CERT_ID:-}"
YC_FOLDER_ID="${YC_FOLDER_ID:-}"
YC_SERVICE_ACCOUNT_ID="${YC_SERVICE_ACCOUNT_ID:-}"
YC_KEY_FILE="${YC_KEY_FILE:-/home/www/key/key.json}"

# ACME/LetsEncrypt configuration
EMAIL="${EMAIL:-}"
ACME_SERVER="${ACME_SERVER:-letsencrypt}"
CERT_DIR="${CERT_DIR:-/etc/ssl/yandex}"
LOG_FILE="${LOG_FILE:-/var/log/yandex_cert_renewal.log}"
# =============================================

# Initialize logging
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Verify dependencies
verify_dependencies() {
    local missing=()
    for cmd in yc jq openssl curl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log "Missing dependencies: ${missing[*]}"
        exit 1
    fi
}

# Get IAM token for service account
get_iam_token() {
    local attempts=3
    local delay=2
    local iam_token=""

    for ((i=1; i<=attempts; i++)); do
        iam_token=$(yc iam create-token)
        
        if [ -n "$iam_token" ]; then
            echo "$iam_token"
            return 0
        fi
        
        if [ "$i" -lt "$attempts" ]; then
            sleep "$delay"
        fi
    done

    log "Failed to get IAM token after $attempts attempts"
    return 1
}

# Renew certificate with acme.sh
renew_certificate() {
    log "Starting certificate renewal process for domains: ${DOMAINS[*]}"
    
    # Export Cloudflare credentials
    export CF_Token="$CF_TOKEN"
    export CF_Account_ID="$CF_ACCOUNT_ID"
    
    # Build domain arguments
    local domain_args=()
    for domain in "${DOMAINS[@]}"; do
        domain_args+=("-d" "$domain")
    done
    
    # Run acme.sh
    /root/.acme.sh/acme.sh --issue \
        --server "$ACME_SERVER" \
        --dns dns_cf \
        "${domain_args[@]}" \
        --keylength ec-256 \
        --key-file "$CERT_DIR/privkey.pem" \
        --fullchain-file "$CERT_DIR/fullchain.pem" \
        --cert-file "$CERT_DIR/cert.pem" \
        --log "$LOG_FILE" \
        --email "$EMAIL" \
        --force
    
    if [ $? -ne 0 ]; then
        log "Certificate renewal failed"
        exit 1
    fi
    
    log "Certificate successfully renewed"
}

# Update certificate in YC Cert Manager
update_yandex_cert() {
    log "Preparing to update certificate in Yandex Cloud"
    
    local iam_token
    iam_token=$(get_iam_token) || exit 1
    
    # Read certificate files and escape JSON
    local cert_data
    cert_data=$(jq -Rs . < "$CERT_DIR/cert.pem")
    local key_data
    key_data=$(jq -Rs . < "$CERT_DIR/privkey.pem")
    
    # Prepare API request
    local request_body
    request_body=$(cat <<EOF
{

    "updateMask": "chain,private_key",
    "chain": $cert_data,
    "private_key": $key_data
}
EOF
    )
    
    log "Sending update request to Yandex Cloud API"
    
    local response
    local status_code
    response=$(curl -sS -w "%{http_code}" -X PATCH \
        -H "Authorization: Bearer $iam_token" \
        -H "Content-Type: application/json" \
        -d "$request_body" \
        "https://certificate-manager.api.cloud.yandex.net/certificate-manager/v1/certificates/$YC_CERT_ID" 2>/dev/null)
    
    status_code=${response: -3}
    response=${response%???}
    
    if [ "$status_code" -ne 200 ]; then
        log "Failed to update certificate. HTTP $status_code. Response: $response"
        exit 1
    fi
    
    log "Certificate successfully updated in Yandex Cloud"
}


main() {
    verify_dependencies
    
    log "=== Starting certificate management process ==="
    mkdir -p "$CERT_DIR"

    renew_certificate
    update_yandex_cert
    log "=== Certificate management completed ==="
}
main
