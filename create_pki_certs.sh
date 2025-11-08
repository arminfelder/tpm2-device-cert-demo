#!/usr/bin/env bash

source vars.sh

function get_vm_gateway_ip() {
    # Try via virsh net-dumpxml (default libvirt network is usually 192.168.122.1)
    if command -v virsh >/dev/null 2>&1; then
        gw=$(virsh net-dumpxml default 2>/dev/null | awk -F"['\"]" '/<ip address=/{print $2; exit}')
        if [[ -n "$gw" ]]; then
            echo "$gw"
            return 0
        fi
    fi
    # Fallback: resolve default network bridge and read its IPv4 address
    bridge=$(ip -o link show | awk -F': ' '/state UP/ {print $2}' | grep -E '^(virbr0|.*br.*)$' | head -n1)
    if [[ -n "$bridge" ]]; then
        gw=$(ip -4 addr show "$bridge" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
        if [[ -n "$gw" ]]; then
            echo "$gw"
            return 0
        fi
    fi
    # Last resort: parse routing table default via bridge
    gw=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
    [[ -n "$gw" ]] && echo "$gw" || return 1
}

function create_server_cert() {
    mkdir -p pki/server
    pushd pki/server
    # Generate server key
    openssl genrsa -out server.key 2048
    chmod 666 server.key
    # Create CSR with CN=localhost
    openssl req -new -key server.key -out server.csr -subj "/CN=localhost"
    # Create SAN config for localhost and 192.168.122.1
    cat > san.cnf <<EOF
subjectAltName=DNS:localhost,IP:127.0.0.1,IP:$(get_vm_gateway_ip)
extendedKeyUsage=serverAuth
keyUsage=digitalSignature,keyEncipherment
EOF
    # Sign CSR with CA to produce server certificate
    openssl x509 -req -in server.csr -CA ../ca/ca.cert -CAkey ../ca/ca.key -CAcreateserial -out server.crt -days 825 -sha256 -extfile san.cnf
    # Verify
    openssl verify -CAfile ../ca/ca.cert server.crt
    popd
}

function create_broker_cert() {
    mkdir -p pki/mqtt
    pushd pki/mqtt
    # Generate server key
    openssl genrsa -out server.key 2048
    chmod 666 server.key
    # Create CSR with CN=localhost
    openssl req -new -key server.key -out server.csr -subj "/CN=localhost"
    # Create SAN config for localhost and 192.168.122.1
    cat > san.cnf <<EOF
subjectAltName=DNS:localhost,IP:127.0.0.1,IP:$(get_vm_gateway_ip)
extendedKeyUsage=serverAuth
keyUsage=digitalSignature,keyEncipherment
EOF
    # Sign CSR with CA to produce server certificate
    openssl x509 -req -in server.csr -CA ../ca/ca.cert -CAkey ../ca/ca.key -CAcreateserial -out server.crt -days 825 -sha256 -extfile san.cnf
    # Verify
    openssl verify -CAfile ../ca/ca.cert server.crt
    popd
}

function create_ca() {
    mkdir -p pki/ca
    pushd pki/ca
    openssl genrsa -out ca.key 4096
    chmod 600 ca.key
    openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.cert -subj "/CN=My Root CA"
    popd
}

function create_bootstrap_cert() {
    mkdir -p pki/bootstrap
    pushd pki/bootstrap
    openssl genrsa -out bootstrap.key 2048
    chmod 600 bootstrap.key
    openssl req -new -key bootstrap.key -out bootstrap.csr -subj "/CN=bootstrap_${VM_NAME}"
    START_DATE=$(date -u +"%Y%m%d%H%M%SZ")
    END_DATE=$(date -u -d "+1 hour" +"%Y%m%d%H%M%SZ")
    openssl x509 -req -in bootstrap.csr -CA ../ca/ca.cert -CAkey ../ca/ca.key -CAcreateserial -out bootstrap.crt -days 1
    openssl verify -CAfile ../ca/ca.cert bootstrap.crt
    popd
}


function main() {
    create_ca
    create_bootstrap_cert
    create_server_cert
}

main