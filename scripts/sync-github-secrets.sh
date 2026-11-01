#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIR="$(dirname "$TF_DIR")"
APP_DIR="$BASE_DIR/app"
SSH_KEY="/root/.ssh/github_actions_diplom"

for tool in terraform git gh ssh awk; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required command is missing: $tool" >&2
    exit 1
  fi
done

[[ -f "$SSH_KEY" ]] || {
  echo "SSH key is missing: $SSH_KEY" >&2
  exit 1
}

gh auth status --hostname github.com

APP_REMOTE="$(git -C "$APP_DIR" remote get-url origin)"
APP_REPO="$(gh repo view "$APP_REMOTE" \
  --json nameWithOwner \
  --jq '.nameWithOwner')"

VM_IP="$(terraform -chdir="$TF_DIR" output -raw vm_external_ip)"
[[ -n "$VM_IP" ]] || {
  echo "Terraform returned an empty VM IP." >&2
  exit 1
}

FINGERPRINT_OUTPUT="$(
  ssh \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    -o ConnectTimeout=15 \
    -o IdentitiesOnly=yes \
    -i "$SSH_KEY" \
    "ubuntu@$VM_IP" \
    'sudo -n ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub -E sha256'
)"

FINGERPRINT="$(awk '{print $2}' <<< "$FINGERPRINT_OUTPUT")"

if [[ ! "$FINGERPRINT" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]; then
  echo "Unexpected fingerprint format." >&2
  exit 1
fi

echo
printf 'Target repository: %s\n' "$APP_REPO"
printf 'VM_HOST: %s\n' "$VM_IP"
printf 'VM_HOST_FINGERPRINT: %s\n' "$FINGERPRINT"
echo

read -r -p "Update these two GitHub Actions secrets? Type yes: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Cancelled."
  exit 0
fi

gh secret set VM_HOST \
  --repo "$APP_REPO" \
  --app actions \
  --body "$VM_IP"

gh secret set VM_HOST_FINGERPRINT \
  --repo "$APP_REPO" \
  --app actions \
  --body "$FINGERPRINT"

echo "Both GitHub Actions secrets were updated successfully."
