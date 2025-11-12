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

function download_image() {
    wget -O "$IMAGE" "${REMOTE_SRC}${IMAGE}"
    if ! validate_checksum; then
      echo "Image validation failed!"
      exit 1
    fi
}

function validate_checksum() {
  if ! sha512sum -c SHA512SUMS --ignore-missing; then
      echo "Checksum verification failed!"
      return 1
  fi
  return 0
}

function verify_image() {
  wget -O SHA512SUMS "${REMOTE_SRC}$CHECKSUMS"
  if [ ! -f "$IMAGE" ]; then
      echo "Downloading $IMAGE..."
      download_image
      
  else
      if ! validate_checksum; then
          echo "Image validation failed, replace image!"
          download_image
      fi
  fi
}

function vm_exists() {
    virsh dominfo "$VM_NAME" &>/dev/null
    return $?
}

function get_vm_ip() {
    local mac
    mac=$(virsh domiflist "$VM_NAME" | grep -oE "[0-9A-Fa-f:]{17}")
    virsh net-dhcp-leases default | grep "$mac" | awk '{print $5}' | cut -d'/' -f1
}

function is_vm_running() {
    virsh domstate "$VM_NAME" 2>/dev/null | grep -q "running"
    return $?
}

function delete_vm() {
    echo "Deleting existing VM: $VM_NAME"
    if is_vm_running; then
        echo "------------------------"
        echo "VM "
        echo "Stopping running VM: $VM_NAME"
        virsh shutdown "$VM_NAME" &>/dev/null
        sleep 5
    fi
    virsh destroy "$VM_NAME" &>/dev/null
    virsh undefine "$VM_NAME" --remove-all-storage &>/dev/null
}

function copy_image_to_libvirt() {
    sudo cp "$IMAGE" "$LIBVIRT_IMAGES_DIR/"
}

function create_vm() {
    virt-install --name "$VM_NAME" --memory 2048 --noreboot \
        --os-variant detect=on,name=debian13 \
        --disk=size=20,backing_store="${LIBVIRT_IMAGES_DIR}/${IMAGE},bus=virtio,format=qcow2" \
        --tpm model=tpm-crb,type=emulator,version=2.0 \
        --cloud-init user-data="$(pwd)/cloud-init/user-data.yaml,meta-data=$(pwd)/cloud-init/meta-data.yaml,network-config=$(pwd)/cloud-init/network-config.yaml" \
        --noautoconsole
}

function get_vm_ip() {
    local mac
    mac=$(virsh domiflist "$VM_NAME" | grep -oE "[0-9A-Fa-f:]{17}")
    local ip
    ip=""
    local max_attempts=30
    local attempt=1

    while [[ -z "$ip" ]] && ((attempt <= max_attempts)); do
        ip=$(virsh net-dhcp-leases default | grep "$mac" | awk '{print $5}' | cut -d'/' -f1)
        if [[ -z "$ip" ]]; then
            sleep 1
            ((attempt++))
        fi
    done
    echo $ip
}

function generate_ssh_configs() {
    local vm_ip=$(get_vm_ip)
    echo "Host ${VM_NAME}
              hostname ${vm_ip}
              Port 22
              user root" > ssh_config-root
}

function get_vm_disk_info() {
    virsh domblklist "$VM_NAME" | tail -n +3 | awk '{print $1 " -> " $2}'
}

function print_connection_info() {
    local vm_ip
    vm_ip=$(get_vm_ip)
    echo "VM Connection Information:"
    echo "------------------------"
    echo "VM Name: $VM_NAME"
    echo "IP Address: $vm_ip"
    echo "root password: $ROOT_PSW"
    echo "Disk Information:"
    get_vm_disk_info
    echo "Serial Console: virsh console $VM_NAME"
    echo "Connect as root: ./connect-as-root.sh"
    echo "------------------------"
}

function patch_cloudinit_config() {
    echo "writes the CA public key into the cloud init config"
    #export SSH_CA_PUBKEY=$(cat $CA_DIR/id_ed25519.pub)
    export VM_NAME=$VM_NAME
    export ROOT_PSW=$ROOT_PSW
    export PKI_SERVER_CERT=$(cat ./pki/server/server.crt | base64 -w0 )
    export BOOTSTRAP_CERT=$(cat ./pki/bootstrap/bootstrap.crt | base64 -w0 )
    export BOOTSTRAP_KEY=$(cat ./pki/bootstrap/bootstrap.key | base64 -w0 )
    export BROKER_CA_CERT=$(cat ./mqtt-certs/ca/ca.cert | base64 -w0 )
    export VM_GATEWAY_IP=$( get_vm_gateway_ip )
    echo "$(envsubst '$ROOT_PSW,$VM_NAME,$BOOTSTRAP_CERT,$BOOTSTRAP_KEY,$PKI_SERVER_CERT,$VM_GATEWAY_IP,$BROKER_CA_CERT' < ./cloud-init/user-data.yaml.tmpl)" > ./cloud-init/user-data.yaml
}

function main() {
    verify_image
    patch_cloudinit_config
    if vm_exists; then
        delete_vm
    fi

    copy_image_to_libvirt
    create_vm

    generate_ssh_configs
    print_connection_info

}

main