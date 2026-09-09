#!/bin/bash

VM_IP_FILE=".vm_ip"
VM_PASS_FILE=".vm_admin_password"
AWS_REGION="${AWS_REGION:-}"

# Auto-detect region from this instance's metadata (IMDSv2) if not already set
if [ -z "$AWS_REGION" ]; then
    IMDS_TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
    AWS_REGION=$(curl -sS -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
        "http://169.254.169.254/latest/meta-data/placement/region" 2>/dev/null)
fi

if [ -z "$AWS_REGION" ]; then
    echo "Error: Could not determine AWS region (AWS_REGION not set and instance metadata lookup failed)"
    exit 1
fi

# If no argument, boot the VM
if [ -z "$1" ]; then
    ansible-playbook ec2_boot_playbook_windows.yml

    if [ ! -f "$VM_IP_FILE" ]; then
        echo "Error: .vm_ip was not created by the playbook"
        exit 1
    fi

    echo "VM IP saved: $(cat "$VM_IP_FILE")"
    exit 0
fi

# Get VM IP from saved file or query AWS
if [ -f "$VM_IP_FILE" ]; then
    VM_IP=$(cat "$VM_IP_FILE")
else
    INSTANCE_ID=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=win-hardened-*" "Name=instance-state-name,Values=running" \
        --query 'Instances[*].[InstanceId,LaunchTime]' \
        --output text 2>/dev/null | sort -k2 | tail -1 | awk '{print $1}')

    if [ -n "$INSTANCE_ID" ]; then
        VM_IP=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress]' \
            --output text 2>/dev/null | awk '{print ($1 != "None") ? $1 : $2}')
    fi
fi

if [ -z "$VM_IP" ]; then
    echo "Error: Could not find VM IP. Is the instance running?"
    exit 1
fi

# Get Administrator password from saved file, or derive it via the launch key
if [ -f "$VM_PASS_FILE" ]; then
    VM_PASS=$(cat "$VM_PASS_FILE")
else
    INSTANCE_ID="${INSTANCE_ID:-$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=ip-address,Values=$VM_IP" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)}"

    VM_PASS=$(aws ec2 get-password-data \
        --region "$AWS_REGION" \
        --instance-id "$INSTANCE_ID" \
        --priv-launch-key "$HOME/.ssh/hardening_ssh_key" \
        --query PasswordData --output text 2>/dev/null)
fi

if [ -z "$VM_PASS" ] || [ "$VM_PASS" = "None" ]; then
    echo "Error: Could not determine Administrator password. Is $VM_PASS_FILE present or the instance ready?"
    exit 1
fi

echo "Using VM IP: $VM_IP"

WINRM_EXTRA_VARS="ansible_connection=winrm ansible_winrm_transport=ntlm ansible_winrm_server_cert_validation=ignore ansible_port=5986 ansible_user=Administrator ansible_password=${VM_PASS}"

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
        echo "  $0              - Boot the EC2 instance"
        echo "  $0 hardening    - Run Windows hardening playbook(s)"
        echo ""
        echo "NOTE: support/windows_*.yml playbooks aren't included here -"
        echo "add them the same way support/*.yml was built out for RHEL."
        exit 1
        ;;
esac
