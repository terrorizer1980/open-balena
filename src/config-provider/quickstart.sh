#!/bin/bash

set -e

CERTS_DIR="${CERTS_DIR:-./certs}"
DOMAIN="${DOMAIN:-openbalena.local}"
FORCE="${FORCE:-}"

ADMIN_EMAIL="${ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

CMD="$(realpath "$0")"
DIR="$(dirname "${CMD}")"
CA="${DIR}/scripts/ca"

source "${DIR}/scripts/logging"

validate_input () {
  [[ ! -z "$DOMAIN" ]] || fatal_log "DOMAIN must be provided to continue" || return 1
  [[ ! -z "$ADMIN_EMAIL" ]] || fatal_log "ADMIN_EMAIL must be provided to continue" || return 1
  [[ ! -z "$ADMIN_PASSWORD" ]] || fatal_log "ADMIN_PASSWORD must be provided to continue" || return 1

  info_log "== Configuring instance with;"
  echo "  Domain: $DOMAIN"
  echo "   Email: $ADMIN_EMAIL"
  echo "Password: $ADMIN_PASSWORD"
}


validate_input || exit 1

# initialise the CA
if [ ! -f "$CERTS_DIR/pki/private/ca.key" ]; then
  "$CA" -d "$CERTS_DIR" initialise -n "OpenBalena CA"
  FORCE=1
fi

# create a wildcard certificate for HTTPS traffic
if [ ! -f "$CERTS_DIR/pki/issued/*.$DOMAIN.crt" ] || [ "$FORCE" == "1" ]; then
  "$CA" -d "$CERTS_DIR" issue -n "*.$DOMAIN"
fi

# create a certificate for VPN traffic
if [ ! -f "$CERTS_DIR/pki/issued/vpn.$DOMAIN.crt" ] || [ "$FORCE" == "1" ]; then
  "$CA" -d "$CERTS_DIR" issue -n "vpn.$DOMAIN"
fi

randstr() {
  LC_CTYPE=C tr -dc A-Za-z0-9 < /dev/urandom | fold -w "${1:-32}" | head -n 1
}

b64encode() {
    echo "$@" | base64 --wrap=0 2>/dev/null || echo "$@" | base64 --break=0 2>/dev/null
}

b64file() {
  b64encode "$(cat "$@")"
}

# buckets to create in the S3 service...
REGISTRY2_S3_BUCKET="registry-data"

# update balenaCloud API with environment values
if [ ! -z "$BALENA_DEVICE_UUID" ] && [ ! -z "$BALENA_API_KEY" ] && [ ! -z "$BALENA_API_URL" ]; then
  # add_variable [ID] [Name] [Value] 
  add_variable () {
    local ID="$1"
    local NAME="$2"
    local VALUE="$3"    

    debug_log "Add: $NAME = $VALUE"
    [[ ! -z "$VALUE" ]] || return 0;

    POST_JSON="$(cat <<EOF
{
  "device": $ID,
  "name": "$NAME",
  "value": "$VALUE"
}
EOF
)"
    POST_RESULT="$(curl -SsX POST "$BALENA_API_URL/v5/device_environment_variable" -H "Authorization: Bearer $BALENA_API_KEY" -d "$POST_JSON" -H "Content-Type: application/json" -o /dev/null -w '%{http_code}\n')"
    debug_log "JSON: $POST_JSON"
    debug_log "Result: $POST_RESULT"
    if [ "$POST_RESULT" == "201" ]; then 
      success_log "Created value for \"$NAME\"";
      return
    fi

    PATCH_JSON="$(cat <<EOF
{
  "value": "$VALUE"
}
EOF
)"
   PATCH_RESULT="$(curl -SsX PATCH "$BALENA_API_URL/v5/device_environment_variable?\$filter=(name%20eq%20%27$NAME%27)%20and%20(device/any(d:id%20eq%20$ID))" -H "Authorization: Bearer $BALENA_API_KEY" -d "$PATCH_JSON" -H "Content-Type: application/json" -o /dev/null -w '%{http_code}\n')"
    debug_log "JSON: $PATCH_JSON"
    debug_log "Result: $PATCH_RESULT"
    if [ "$PATCH_RESULT" == "200" ]; then 
      success_log "Updated value for \"$NAME\"";
      return
    fi

    error_log "Unable to set value for '$NAME'"
    return 1
  }

  info_log "== Updating configuration in balenaCloud"
  DEVICE_ID=$(curl -Ss "$BALENA_API_URL/v3/device?\$filter=uuid%20eq%20%27$BALENA_DEVICE_UUID%27" -H "Authorization: Bearer $BALENA_API_KEY" | jq .d[0].id)
  debug_log "Device Id: $DEVICE_ID"

  DELETE_RESULT="$(curl -SsX DELETE "$BALENA_API_URL/v5/device_environment_variable?\$filter=(device/any(d:id%20eq%20$DEVICE_ID))" -H "Authorization: Bearer $BALENA_API_KEY" -o /dev/null -w '%{http_code}\n')"
  debug_log "Result: $DELETE_RESULT"
  if [ "$DELETE_RESULT" == "200" ]; then 
    success_log "Removed all configuration for device $DEVICE_ID";
  fi

  # set the values for the environment
  OPENBALENA_PRODUCTION_MODE="false"
  OPENBALENA_COOKIE_SESSION_SECRET="$(randstr 32)"
  OPENBALENA_JWT_SECRET="$(randstr 32)"
  OPENBALENA_REGISTRY_SECRET_KEY="$(randstr 32)"
  OPENBALENA_REGISTRY2_S3_BUCKET="registry-data"
  OPENBALENA_RESINOS_REGISTRY_CODE="$(randstr 32)"
  OPENBALENA_ROOT_CA="$(b64file "$CERTS_DIR/pki/ca.crt")"
  OPENBALENA_ROOT_CRT="$(b64file "$CERTS_DIR/pki/issued/*.$DOMAIN.crt")"
  OPENBALENA_ROOT_KEY="$(b64file "$CERTS_DIR/pki/private/*.$DOMAIN.key")"
  OPENBALENA_VPN_CA="$(b64file "$CERTS_DIR/pki/ca.crt")"
  OPENBALENA_VPN_CA_CHAIN="$(b64file "$CERTS_DIR/pki/ca.crt")"
  OPENBALENA_VPN_SERVER_CRT="$(b64file "$CERTS_DIR/pki/issued/vpn.$DOMAIN.crt")"
  OPENBALENA_VPN_SERVER_KEY="$(b64file "$CERTS_DIR/pki/private/vpn.$DOMAIN.key")"
  OPENBALENA_VPN_SERVER_DH="$(b64file "$CERTS_DIR/pki/dh.pem")"
  OPENBALENA_VPN_SERVICE_API_KEY="$(randstr 32)"
  OPENBALENA_API_VPN_SERVICE_API_KEY="$(randstr 32)"
  OPENBALENA_TOKEN_AUTH_BUILDER_TOKEN="$(randstr 64)"
  OPENBALENA_S3_BUCKETS="registry-data"
  OPENBALENA_S3_ENDPOINT=""https://s3.${DOMAIN}""
  OPENBALENA_S3_REGION="us-east-1"
  OPENBALENA_S3_ACCESS_KEY="$(randstr 32)"
  OPENBALENA_S3_SECRET_KEY="$(randstr 32)"
  OPENBALENA_SUPERUSER_EMAIL="$ADMIN_EMAIL"
  OPENBALENA_SUPERUSER_PASSWORD="$ADMIN_PASSWORD"
  OPENBALENA_ACME_CERT_ENABLED="${ACME_CERT_ENABLED:-false}"
  OPENBALENA_HOST_NAME="$DOMAIN"
  OPENBALENA_SSH_AUTHORIZED_KEYS=""
  OPENBALENA_TOKEN_AUTH_PUB="$(b64file "$JWT_CRT")"
  OPENBALENA_TOKEN_AUTH_KEY="$(b64file "$JWT_KEY")"
  OPENBALENA_TOKEN_AUTH_KID="$(b64file "$JWT_KID")"

  # API service values
  add_variable $DEVICE_ID "API_VPN_SERVICE_API_KEY" "$OPENBALENA_API_VPN_SERVICE_API_KEY"
  add_variable $DEVICE_ID "API_SERVICE_API_KEY" "$OPENBALENA_API_VPN_SERVICE_API_KEY"
  add_variable $DEVICE_ID "BALENA_ROOT_CA" "$OPENBALENA_ROOT_CA"
  add_variable $DEVICE_ID "COOKIE_SESSION_SECRET" "$OPENBALENA_COOKIE_SESSION_SECRET"
  add_variable $DEVICE_ID "DELTA_HOST" "delta.$DOMAIN"
  add_variable $DEVICE_ID "DEVICE_CONFIG_OPENVPN_CA" "$OPENBALENA_VPN_CA"
  add_variable $DEVICE_ID "HOST" "api.$DOMAIN"
  add_variable $DEVICE_ID "IMAGE_MAKER_URL" "img.$DOMAIN"
  add_variable $DEVICE_ID "CONFD_BACKEND" "ENV"
  add_variable $DEVICE_ID "DB_HOST" "db"
  add_variable $DEVICE_ID "DB_PASSWORD" "docker"
  add_variable $DEVICE_ID "DB_PORT" "5432"
  add_variable $DEVICE_ID "DB_USER" "docker"
  add_variable $DEVICE_ID "DEVICE_CONFIG_SSH_AUTHORIZED_KEYS" "''"
  add_variable $DEVICE_ID "IMAGE_STORAGE_BUCKET" "resin-production-img-cloudformation"
  add_variable $DEVICE_ID "IMAGE_STORAGE_ENDPOINT" "s3.amazonaws.com"
  add_variable $DEVICE_ID "IMAGE_STORAGE_PREFIX" "resinos"
  add_variable $DEVICE_ID "JSON_WEB_TOKEN_EXPIRY_MINUTES" "10080"
  add_variable $DEVICE_ID "JSON_WEB_TOKEN_SECRET" "$OPENBALENA_JWT_SECRET"
  add_variable $DEVICE_ID "MIXPANEL_TOKEN" "__unused__"
  add_variable $DEVICE_ID "PRODUCTION_MODE" "false"
  add_variable $DEVICE_ID "PUBNUB_PUBLISH_KEY" "__unused__"
  add_variable $DEVICE_ID "PUBNUB_SUBSCRIBE_KEY" "__unused__"
  add_variable $DEVICE_ID "REDIS_HOST" "redis"
  add_variable $DEVICE_ID "REDIS_PORT" "6379"
  add_variable $DEVICE_ID "REGISTRY2_HOST" "registry.$DOMAIN"
  add_variable $DEVICE_ID "REGISTRY_HOST" "registry.$DOMAIN"
  add_variable $DEVICE_ID "SENTRY_DSN" "''"
  add_variable $DEVICE_ID "SUPERUSER_EMAIL" "$OPENBALENA_SUPERUSER_EMAIL"
  add_variable $DEVICE_ID "SUPERUSER_PASSWORD" "$OPENBALENA_SUPERUSER_PASSWORD"
  add_variable $DEVICE_ID "TOKEN_AUTH_BUILDER_TOKEN" "$OPENBALENA_TOKEN_AUTH_BUILDER_TOKEN"
  add_variable $DEVICE_ID "TOKEN_AUTH_CERT_ISSUER" "api.$DOMAIN"
  add_variable $DEVICE_ID "TOKEN_AUTH_CERT_KEY" "$OPENBALENA_TOKEN_AUTH_KEY"
  add_variable $DEVICE_ID "TOKEN_AUTH_CERT_KID" "$OPENBALENA_TOKEN_AUTH_KID"
  add_variable $DEVICE_ID "TOKEN_AUTH_CERT_PUB" "$OPENBALENA_TOKEN_AUTH_PUB"
  add_variable $DEVICE_ID "TOKEN_AUTH_JWT_ALGO" "ES256"
  add_variable $DEVICE_ID "VPN_HOST" "vpn.$DOMAIN"
  add_variable $DEVICE_ID "VPN_PORT" "443"
  add_variable $DEVICE_ID "BALENA_VPN_PORT" "443"
  add_variable $DEVICE_ID "VPN_SERVICE_API_KEY" "$OPENBALENA_VPN_SERVICE_API_KEY"
  add_variable $DEVICE_ID "MDNS_TLD" "$DOMAIN"

  # VPN service values
  add_variable $DEVICE_ID "BALENA_API_HOST" "api.$DOMIN"
  add_variable $DEVICE_ID "RESIN_VPN_GATEWAY" "10.2.0.1"
  add_variable $DEVICE_ID "VPN_HAPROXY_USEPROXYPROTOCOL" "true"
  add_variable $DEVICE_ID "VPN_OPENVPN_CA_CRT" "$OPENBALENA_VPN_CA"
  add_variable $DEVICE_ID "VPN_OPENVPN_SERVER_CRT" "$OPENBALENA_VPN_SERVER_CRT"
  add_variable $DEVICE_ID "VPN_OPENVPN_SERVER_DH" "$OPENBALENA_VPN_SERVER_DH"
  add_variable $DEVICE_ID "VPN_OPENVPN_SERVER_KEY" "$OPENBALENA_VPN_SERVER_KEY"
  
  # HAProxy service values
  add_variable $DEVICE_ID "BALENA_HAPROXY_CRT" "$OPENBALENA_ROOT_CRT"
  add_variable $DEVICE_ID "BALENA_HAPROXY_KEY" "$OPENBALENA_ROOT_KEY"
  add_variable $DEVICE_ID "HAPROXY_HOSTNAME" "$DOMAIN"

  # Registry service values
  add_variable $DEVICE_ID "API_TOKENAUTH_CRT" "$OPENBALENA_TOKEN_AUTH_PUB"
  add_variable $DEVICE_ID "BALENA_REGISTRY2_HOST" "registry.$DOMAIN"
  add_variable $DEVICE_ID "BALENA_TOKEN_AUTH_ISSUER" "api.$DOMAIN"
  add_variable $DEVICE_ID "BALENA_TOKEN_AUTH_REALM" "https://api.$DOMAIN/auth/v1/token"
  add_variable $DEVICE_ID "REGISTRY2_S3_BUCKET" "$OPENBALENA_REGISTRY2_S3_BUCKET"
  add_variable $DEVICE_ID "REGISTRY2_S3_REGION_ENDPOINT" "https://s3.$DOMAIN"
  add_variable $DEVICE_ID "REGISTRY2_S3_KEY" "$OPENBALENA_S3_ACCESS_KEY"
  add_variable $DEVICE_ID "REGISTRY2_S3_SECRET" "$OPENBALENA_S3_SECRET_KEY"
  add_variable $DEVICE_ID "REGISTRY2_SECRETKEY" "$OPENBALENA_REGISTRY_SECRET_KEY"
  add_variable $DEVICE_ID "REGISTRY2_STORAGEPATH" "/data"
  add_variable $DEVICE_ID "REGISTRY2_CACHE_ADDR" "127.0.0.1:6379"
  add_variable $DEVICE_ID "REGISTRY2_CACHE_DB" "0"
  add_variable $DEVICE_ID "REGISTRY2_CACHE_ENABLED" "false"
  add_variable $DEVICE_ID "REGISTRY2_CACHE_MAXMEMORY_MB" "1024"
  add_variable $DEVICE_ID "REGISTRY2_CACHE_MAXMEMORY_POLICY" "allkeys-lru"
  add_variable $DEVICE_ID "COMMON_REGION" "us-east-1"

  # S3 service values
  add_variable $DEVICE_ID "BUCKETS" "registry-data"
  add_variable $DEVICE_ID "S3_MINIO_ACCESS_KEY" "$OPENBALENA_S3_ACCESS_KEY"
  add_variable $DEVICE_ID "S3_MINIO_SECRET_KEY" "$OPENBALENA_S3_SECRET_KEY"
fi

success_log "Complete"
