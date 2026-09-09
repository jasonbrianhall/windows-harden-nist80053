#!/bin/bash
ansible-playbook kvm_boot_playbook_windows.yml --ask-become-pass \
  -e "source_image=/var/lib/libvirt/images/Windows10.qcow2" \
  -e "winrm_port=5985" \
  -e "winrm_transport=basic"
