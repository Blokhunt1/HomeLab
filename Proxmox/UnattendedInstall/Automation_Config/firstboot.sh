#!/bin/bash
# firstboot.sh - First Boot Hook: Install Terraform and run a Terraform configuration
exec > /var/log/firstboot.log 2>&1

# Update package lists and install prerequisites
apt-get update
apt-get install -y wget unzip gnupg software-properties-common

# Add HashiCorp’s GPG key and repository for Terraform
wget -qO- https://apt.releases.hashicorp.com/gpg | gpg --dearmor > /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list
apt-get update

# Install Terraform
apt-get install -y terraform