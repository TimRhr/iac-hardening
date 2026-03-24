#!/usr/bin/env bash
# =============================================================================
# scripts/vault-setup.sh
# Ansible Vault Ersteinrichtung
#
# Verwendung:
#   ./scripts/vault-setup.sh              # Interaktiv — Passwort eingeben
#   ./scripts/vault-setup.sh --generate   # Zufälliges Passwort generieren
# =============================================================================
set -euo pipefail

VAULT_PASS_FILE=".vault_pass"
VAULT_FILES=(
  "inventory/group_vars/all/vault.yml"
)

echo "═══════════════════════════════════════════════"
echo "  Ansible Vault Ersteinrichtung"
echo "═══════════════════════════════════════════════"
echo ""

# ── Vault-Passwort setzen ─────────────────────────────────────────────────────
if [ "${1:-}" = "--generate" ]; then
  VAULT_PASSWORD=$(openssl rand -base64 32)
  echo "$VAULT_PASSWORD" > "$VAULT_PASS_FILE"
  chmod 600 "$VAULT_PASS_FILE"
  echo "✅ Zufälliges Vault-Passwort generiert: $VAULT_PASS_FILE"
  echo ""
  echo "⚠️  WICHTIG: Dieses Passwort sicher aufbewahren!"
  echo "   Ohne Passwort sind die Vault-Dateien nicht entschlüsselbar."
  echo ""
else
  if [ -f "$VAULT_PASS_FILE" ]; then
    echo "ℹ️  Vault-Passwort-Datei existiert bereits: $VAULT_PASS_FILE"
  else
    echo "Vault-Passwort eingeben (wird in $VAULT_PASS_FILE gespeichert):"
    read -rs VAULT_PASSWORD
    echo ""
    echo "Passwort bestätigen:"
    read -rs VAULT_PASSWORD_CONFIRM
    echo ""

    if [ "$VAULT_PASSWORD" != "$VAULT_PASSWORD_CONFIRM" ]; then
      echo "❌ Passwörter stimmen nicht überein!"
      exit 1
    fi

    echo "$VAULT_PASSWORD" > "$VAULT_PASS_FILE"
    chmod 600 "$VAULT_PASS_FILE"
    echo "✅ Vault-Passwort gespeichert: $VAULT_PASS_FILE"
  fi
fi

# ── ansible.cfg vault_password_file aktivieren ───────────────────────────────
if grep -q "^# vault_password_file" ansible.cfg 2>/dev/null; then
  sed -i 's/^# vault_password_file = .vault_pass/vault_password_file = .vault_pass/' ansible.cfg
  echo "✅ vault_password_file in ansible.cfg aktiviert"
fi

# ── Vault-Dateien verschlüsseln ───────────────────────────────────────────────
echo ""
echo "Vault-Dateien verschlüsseln..."
for vault_file in "${VAULT_FILES[@]}"; do
  if [ -f "$vault_file" ]; then
    # Prüfen ob bereits verschlüsselt
    if head -1 "$vault_file" | grep -q "ANSIBLE_VAULT"; then
      echo "  ℹ️  Bereits verschlüsselt: $vault_file"
    else
      ansible-vault encrypt "$vault_file" --vault-password-file "$VAULT_PASS_FILE"
      echo "  ✅ Verschlüsselt: $vault_file"
    fi
  else
    echo "  ⚠️  Nicht gefunden: $vault_file"
  fi
done

echo ""
echo "═══════════════════════════════════════════════"
echo "  Vault-Setup abgeschlossen!"
echo "═══════════════════════════════════════════════"
echo ""
echo "Nächste Schritte:"
echo "  1. Vault-Datei bearbeiten:"
echo "     ansible-vault edit inventory/group_vars/all/vault.yml"
echo ""
echo "  2. Secrets eintragen:"
echo "     vault_bootloader_grub_password: 'starkes_passwort'"
echo "     vault_aide_alert_mail: 'admin@example.com'"
echo ""
echo "  3. Playbook ausführen:"
echo "     ansible-playbook playbooks/hardening/site.yml"
echo "     (vault_password_file wird automatisch aus ansible.cfg gelesen)"
echo ""
echo "  4. .vault_pass in .gitignore eintragen (bereits vorhanden)!"

# ── Pre-Commit Hook installieren ──────────────────────────────────────────────
if [ -d ".git/hooks" ]; then
  cp scripts/pre-commit-vault-check.sh .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  echo "✅ Pre-Commit Hook installiert (.git/hooks/pre-commit)"
  echo "   Verhindert Commits von unverschlüsselten vault.yml Dateien."
fi
