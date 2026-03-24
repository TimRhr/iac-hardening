#!/usr/bin/env bash
# =============================================================================
# scripts/pre-commit-vault-check.sh
# Git Pre-Commit Hook: Verhindert Commit von unverschlüsselten Vault-Dateien
#
# Einrichten:
#   cp scripts/pre-commit-vault-check.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
# =============================================================================
set -euo pipefail

VAULT_FILES=(
  "inventory/group_vars/all/vault.yml"
)

FAIL=0
for vault_file in "${VAULT_FILES[@]}"; do
  if git diff --cached --name-only | grep -q "$vault_file"; then
    if ! git show ":$vault_file" 2>/dev/null | head -1 | grep -q "ANSIBLE_VAULT"; then
      echo "❌ FEHLER: $vault_file ist NICHT verschlüsselt!"
      echo "   Verschlüsseln mit: ansible-vault encrypt $vault_file"
      FAIL=1
    fi
  fi
done

[ $FAIL -eq 0 ] && exit 0
echo ""
echo "Commit abgebrochen — Vault-Dateien verschlüsseln!"
exit 1
