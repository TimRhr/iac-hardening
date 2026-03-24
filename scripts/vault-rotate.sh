#!/usr/bin/env bash
# =============================================================================
# scripts/vault-rotate.sh
# Ansible Vault Passwort-Rotation
#
# Verwendung:
#   ./scripts/vault-rotate.sh
# =============================================================================
set -euo pipefail

OLD_PASS_FILE=".vault_pass"
NEW_PASS_FILE=".vault_pass.new"

VAULT_FILES=(
  "inventory/group_vars/all/vault.yml"
)

echo "═══════════════════════════════════════════════"
echo "  Ansible Vault Passwort-Rotation"
echo "═══════════════════════════════════════════════"

[ ! -f "$OLD_PASS_FILE" ] && { echo "❌ $OLD_PASS_FILE nicht gefunden!"; exit 1; }

echo "Neues Vault-Passwort eingeben:"
read -rs NEW_PASSWORD
echo ""
echo "Neues Passwort bestätigen:"
read -rs NEW_PASSWORD_CONFIRM
echo ""

[ "$NEW_PASSWORD" != "$NEW_PASSWORD_CONFIRM" ] && { echo "❌ Passwörter stimmen nicht überein!"; exit 1; }

echo "$NEW_PASSWORD" > "$NEW_PASS_FILE"
chmod 600 "$NEW_PASS_FILE"

echo "Rotiere Vault-Dateien..."
for vault_file in "${VAULT_FILES[@]}"; do
  if [ -f "$vault_file" ] && head -1 "$vault_file" | grep -q "ANSIBLE_VAULT"; then
    ansible-vault rekey "$vault_file" \
      --vault-password-file "$OLD_PASS_FILE" \
      --new-vault-password-file "$NEW_PASS_FILE"
    echo "  ✅ Rotiert: $vault_file"
  fi
done

mv "$NEW_PASS_FILE" "$OLD_PASS_FILE"
echo ""
echo "✅ Passwort-Rotation abgeschlossen"
