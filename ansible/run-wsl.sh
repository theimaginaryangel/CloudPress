#!/bin/bash
set -ex

# WSL environment setup for Ansible
# Skip installs to save time on slow WSL network
# export DEBIAN_FRONTEND=noninteractive
# apt-get update
# apt-get install -y python3 python3-pip curl unzip
# pip3 install ansible boto3 botocore --break-system-packages || pip3 install ansible boto3 botocore

# AWS CLI
# if ! command -v aws &> /dev/null; then
#    ...
# fi

# SSM Plugin
# if ! command -v session-manager-plugin &> /dev/null; then
#     curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
#     dpkg -i session-manager-plugin.deb
#     rm session-manager-plugin.deb
# fi

# Setup SSH key for Ansible
mkdir -p ~/.ssh
cd /mnt/d/Cloudpress/terraform/environments/dev3
terraform.exe output -raw ec2_private_key | tr -d '\r' > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa

# Run Ansible
cd /mnt/d/Cloudpress/ansible
export ANSIBLE_CONFIG=/mnt/d/Cloudpress/ansible/ansible.cfg
ansible-playbook -i "${INSTANCE_ID}," -u ubuntu playbook.yml --private-key ~/.ssh/id_rsa -e "site_id=test-site-03 domain=test-site-03.test.cloudpress.local db_host=$DB_HOST aws_region=$AWS_REGION"
