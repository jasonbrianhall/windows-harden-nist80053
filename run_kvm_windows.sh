#!/bin/bash

VM_IP_FILE=".vm_ip"

# If no argument, boot the VM
if [ -z "$1" ]; then
    if [ -z "$WIN_ADMIN_PASSWORD" ]; then
        read -sp "Local Administrator password (baked into the source image): " WIN_ADMIN_PASSWORD
        echo
        export WIN_ADMIN_PASSWORD
    fi

    ansible-playbook kvm_boot_playbook_windows.yml --ask-become-pass

    if [ ! -f "$VM_IP_FILE" ]; then
        echo "Error: .vm_ip was not created by the playbook"
        exit 1
    fi

    echo "VM IP saved: $(cat "$VM_IP_FILE")"
    exit 0
fi

# Get VM IP from saved file or query virsh
if [ -f "$VM_IP_FILE" ]; then
    VM_IP=$(cat "$VM_IP_FILE")
else
    VM_NAME=$(virsh list --all | grep win-hardened | tail -1 | awk '{print $2}')
    VM_IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | grep ipv4 | awk '{print $4}' | cut -d'/' -f1)
fi

if [ -z "$VM_IP" ]; then
    echo "Error: Could not find VM IP. Is the VM running?"
    exit 1
fi

if [ -z "$WIN_ADMIN_PASSWORD" ]; then
    read -sp "Local Administrator password: " WIN_ADMIN_PASSWORD
    echo
fi

echo "Using VM IP: $VM_IP"

WINRM_EXTRA_VARS="ansible_connection=winrm ansible_winrm_transport=ntlm ansible_winrm_server_cert_validation=ignore ansible_port=5986 ansible_user=Administrator ansible_password=${WIN_ADMIN_PASSWORD}"

# Run hardening playbooks based on argument
case "$1" in
    hardening)
        ansible-playbook -i "$VM_IP", -e "$WINRM_EXTRA_VARS" support/windows_hardening.yml
        ;;
    baseline)
        ansible-playbook -i "$VM_IP", -e "$WINRM_EXTRA_VARS" support/windows_baseline.yml
        ;;
    check_stig)
        ansible-playbook -i "$VM_IP", -e "$WINRM_EXTRA_VARS" support/windows_stig_scan.yml
        ;;
    *)
        echo "Usage: $0 [boot|hardening|baseline|check_stig]"
        echo ""
        echo "  $0              - Boot the VM"
        echo "  $0 hardening    - Run Windows hardening playbook(s)"
        echo ""
        echo "NOTE: support/windows_*.yml playbooks aren't included here -"
        echo "add them the same way support/*.yml was built out for RHEL."
        exit 1
        ;;
esac
