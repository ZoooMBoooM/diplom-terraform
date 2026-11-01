#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIR="$(dirname "$TF_DIR")"
ANSIBLE_DIR="$BASE_DIR/ansible"
SSH_KEY="/root/.ssh/github_actions_diplom"

for tool in terraform ansible-playbook ssh nc curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required command is missing: $tool" >&2
    exit 1
  fi
done

for required_file in \
  "$SSH_KEY" \
  "$SSH_KEY.pub" \
  "$ANSIBLE_DIR/ansible.cfg" \
  "$ANSIBLE_DIR/playbooks/site.yml"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Required file is missing: $required_file" >&2
    exit 1
  fi
done

PLAN_FILE="$(mktemp /tmp/diplom-plan.XXXXXX)"
trap 'rm -f "$PLAN_FILE"' EXIT

cd "$TF_DIR"

terraform init
terraform validate
terraform plan -out="$PLAN_FILE"

read -r -p "Apply this Terraform plan? Type yes: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Cancelled."
  exit 0
fi

terraform apply "$PLAN_FILE"

VM_IP="$(terraform output -raw vm_external_ip)"
if [[ -z "$VM_IP" ]]; then
  echo "Terraform returned an empty VM IP." >&2
  exit 1
fi

echo "Ubuntu public IP: $VM_IP"

mkdir -p "$ANSIBLE_DIR/inventory"
printf '[web]\ndiplom-vm ansible_host=%s ansible_user=ubuntu\n' \
  "$VM_IP" > "$ANSIBLE_DIR/inventory/hosts.ini"

SSH_READY=false
for attempt in $(seq 1 60); do
  if nc -z -w 3 "$VM_IP" 22 >/dev/null 2>&1; then
    SSH_READY=true
    break
  fi
  echo "Waiting for TCP port 22: attempt $attempt/60"
  sleep 5
done

if [[ "$SSH_READY" != "true" ]]; then
  echo "TCP port 22 is unavailable on $VM_IP." >&2
  exit 1
fi

echo "If SSH asks about a new host key, verify its fingerprint."
ssh \
  -o StrictHostKeyChecking=ask \
  -o ConnectTimeout=15 \
  -o IdentitiesOnly=yes \
  -i "$SSH_KEY" \
  "ubuntu@$VM_IP" \
  'sudo timeout 600 cloud-init status --wait --long'

cd "$ANSIBLE_DIR"

ansible-playbook \
  -i inventory/hosts.ini \
  playbooks/site.yml

curl \
  --fail \
  --silent \
  --show-error \
  --connect-timeout 10 \
  --max-time 30 \
  "http://$VM_IP:8080/" \
  >/dev/null

echo
echo "Deployment completed."
echo "Application: http://$VM_IP:8080/"
echo "GitHub VM_HOST must be: $VM_IP"
echo "Host fingerprint:"
ssh \
  -o StrictHostKeyChecking=yes \
  -o ConnectTimeout=15 \
  -o IdentitiesOnly=yes \
  -i "$SSH_KEY" \
  "ubuntu@$VM_IP" \
  'sudo ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub -E sha256'
