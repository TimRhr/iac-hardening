#!/usr/bin/env bash
# =============================================================================
# scripts/backup-keys.sh
# GPG-verschlüsseltes Backup aller SSH-Keys
#
# Verschlüsselt ssh_keys/ mit einem separaten Backup-GPG-Key und speichert
# das Archiv an einem konfigurierten Zielort (lokal, USB, Netzwerk-Share).
#
# VORAUSSETZUNGEN:
#   - gpg installiert: sudo apt-get install gnupg
#   - Backup-GPG-Key importiert: gpg --import backup-key.pub.asc
#   - BACKUP_GPG_FINGERPRINT gesetzt (s.u.)
#
# VERWENDUNG:
#   # Standard (Backup-Ziel aus BACKUP_DEST, GPG-Key aus BACKUP_GPG_FINGERPRINT):
#   ./scripts/backup-keys.sh
#
#   # Mit explizitem GPG-Key:
#   BACKUP_GPG_FINGERPRINT="ABCD1234..." ./scripts/backup-keys.sh
#
#   # Auf USB-Stick:
#   BACKUP_DEST="/media/usb/ansible-backups" ./scripts/backup-keys.sh
#
#   # Symmetric (Passwort statt GPG-Key):
#   USE_SYMMETRIC=true ./scripts/backup-keys.sh
#
# CRON-JOB (täglich 02:00):
#   0 2 * * * /pfad/zu/iac-hardening/scripts/backup-keys.sh \
#     >> /var/log/ansible-key-backup.log 2>&1
# =============================================================================
set -euo pipefail

# ── Konfiguration (via Umgebungsvariablen überschreibbar) ─────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

SOURCE_DIR="${SOURCE_DIR:-${PROJECT_ROOT}/ssh_keys}"
BACKUP_DEST="${BACKUP_DEST:-${HOME}/.ansible-key-backups}"
BACKUP_GPG_FINGERPRINT="${BACKUP_GPG_FINGERPRINT:-}"
USE_SYMMETRIC="${USE_SYMMETRIC:-false}"
KEEP_BACKUPS="${KEEP_BACKUPS:-10}"   # Anzahl Backups die behalten werden
VERBOSE="${VERBOSE:-false}"

DATE=$(date +%Y%m%d_%H%M%S)
ARCHIVE_NAME="ansible-keys_${DATE}.tar.gz.gpg"
ARCHIVE_PATH="${BACKUP_DEST}/${ARCHIVE_NAME}"
TEMP_ARCHIVE="/tmp/ansible-keys-backup-${DATE}.tar.gz"

# ── Farben / Logging ──────────────────────────────────────────────────────────
log_info()    { echo "[$(date +%H:%M:%S)] ℹ️  $*"; }
log_success() { echo "[$(date +%H:%M:%S)] ✅  $*"; }
log_warn()    { echo "[$(date +%H:%M:%S)] ⚠️  $*" >&2; }
log_error()   { echo "[$(date +%H:%M:%S)] ❌  $*" >&2; }
log_debug()   { [ "$VERBOSE" = "true" ] && echo "[$(date +%H:%M:%S)] 🔍  $*" || true; }

# ── Hilfsfunktionen ───────────────────────────────────────────────────────────
cleanup() {
  rm -f "$TEMP_ARCHIVE"
  log_debug "Temporäre Dateien bereinigt"
}
trap cleanup EXIT

check_dependencies() {
  local missing=()
  command -v gpg  >/dev/null 2>&1 || missing+=("gpg")
  command -v tar  >/dev/null 2>&1 || missing+=("tar")
  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Fehlende Abhängigkeiten: ${missing[*]}"
    log_error "Installation: sudo apt-get install ${missing[*]}"
    exit 1
  fi
}

check_source() {
  if [ ! -d "$SOURCE_DIR" ]; then
    log_error "Quellverzeichnis nicht gefunden: $SOURCE_DIR"
    log_error "Wurden bereits Keys generiert? (ansible-playbook ... --tags keygen)"
    exit 1
  fi

  local key_count
  key_count=$(find "$SOURCE_DIR" -name "id_ed25519" -not -name "*.retired.*" | wc -l)
  if [ "$key_count" -eq 0 ]; then
    log_warn "Keine SSH-Keys in $SOURCE_DIR gefunden"
    log_warn "Wurde das Hardening bereits ausgeführt?"
    exit 0
  fi
  log_info "${key_count} SSH-Key(s) gefunden in $SOURCE_DIR"
}

create_backup_dir() {
  mkdir -p "$BACKUP_DEST"
  chmod 700 "$BACKUP_DEST"
  log_debug "Backup-Verzeichnis: $BACKUP_DEST"
}

create_archive() {
  log_info "Erstelle Archiv von $SOURCE_DIR ..."
  tar -czf "$TEMP_ARCHIVE" -C "$(dirname "$SOURCE_DIR")" "$(basename "$SOURCE_DIR")"
  local size
  size=$(du -sh "$TEMP_ARCHIVE" | cut -f1)
  log_debug "Archiv erstellt: $TEMP_ARCHIVE ($size)"
}

encrypt_gpg_key() {
  if ! gpg --list-keys "$BACKUP_GPG_FINGERPRINT" >/dev/null 2>&1; then
    log_error "GPG-Key nicht gefunden: $BACKUP_GPG_FINGERPRINT"
    log_error "Key importieren: gpg --import backup-key.pub.asc"
    exit 1
  fi
  log_info "Verschlüssele mit GPG-Key: ${BACKUP_GPG_FINGERPRINT:0:16}..."
  gpg --batch --yes \
      --trust-model always \
      --encrypt \
      --recipient "$BACKUP_GPG_FINGERPRINT" \
      --output "$ARCHIVE_PATH" \
      "$TEMP_ARCHIVE"
}

encrypt_symmetric() {
  log_info "Verschlüssele symmetrisch (Passwort-Eingabe erforderlich) ..."
  gpg --batch --yes \
      --symmetric \
      --cipher-algo AES256 \
      --output "$ARCHIVE_PATH" \
      "$TEMP_ARCHIVE"
}

encrypt_archive() {
  if [ "$USE_SYMMETRIC" = "true" ]; then
    encrypt_symmetric
  elif [ -n "$BACKUP_GPG_FINGERPRINT" ]; then
    encrypt_gpg_key
  else
    log_error "Kein Verschlüsselungsverfahren konfiguriert!"
    echo ""
    echo "Optionen:"
    echo "  1. GPG-Key (empfohlen):"
    echo "     BACKUP_GPG_FINGERPRINT='<fingerprint>' $0"
    echo ""
    echo "  2. Symmetrisch (Passwort):"
    echo "     USE_SYMMETRIC=true $0"
    echo ""
    echo "  GPG-Key-Fingerprint ermitteln:"
    echo "     gpg --list-keys"
    exit 1
  fi

  chmod 600 "$ARCHIVE_PATH"
  local size
  size=$(du -sh "$ARCHIVE_PATH" | cut -f1)
  log_success "Backup erstellt: $ARCHIVE_PATH ($size)"
}

verify_backup() {
  if [ ! -f "$ARCHIVE_PATH" ]; then
    log_error "Backup-Datei nicht erstellt: $ARCHIVE_PATH"
    exit 1
  fi

  # GPG-Integrität prüfen (ohne Entschlüsseln)
  if gpg --batch --list-packets "$ARCHIVE_PATH" >/dev/null 2>&1; then
    log_success "Backup-Integrität verifiziert (GPG-Struktur OK)"
  else
    log_warn "GPG-Struktur-Prüfung fehlgeschlagen — Backup trotzdem gespeichert"
  fi
}

rotate_old_backups() {
  local count
  count=$(find "$BACKUP_DEST" -name "ansible-keys_*.tar.gz.gpg" | wc -l)
  if [ "$count" -gt "$KEEP_BACKUPS" ]; then
    local to_delete=$(( count - KEEP_BACKUPS ))
    log_info "Bereinige $to_delete alte Backup(s) (behalte ${KEEP_BACKUPS})"
    find "$BACKUP_DEST" -name "ansible-keys_*.tar.gz.gpg" \
      | sort | head -n "$to_delete" \
      | xargs rm -f
  fi
}

print_summary() {
  echo ""
  echo "================================================================"
  echo "  Key-Backup abgeschlossen"
  echo "================================================================"
  echo "  Datum:   $(date)"
  echo "  Backup:  $ARCHIVE_PATH"
  echo "  Quelle:  $SOURCE_DIR"
  echo "================================================================"
  echo "  RESTORE-ANLEITUNG:"
  if [ "$USE_SYMMETRIC" = "true" ]; then
    echo "  gpg --decrypt $ARCHIVE_PATH | tar -xz -C <zielverzeichnis>"
  else
    echo "  gpg --decrypt $ARCHIVE_PATH | tar -xz -C <zielverzeichnis>"
  fi
  echo "================================================================"
  if [[ "$BACKUP_DEST" == "$HOME"* ]]; then
    echo "  ⚠️  Backup liegt noch LOKAL — für echte Sicherheit:"
    echo "     cp '$ARCHIVE_PATH' /media/usb/  # USB-Stick"
    echo "     # oder in sicheren Cloud-Speicher (Vault, S3 etc.)"
    echo "================================================================"
  fi
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
log_info "Starte Key-Backup ..."
log_debug "Quelle: $SOURCE_DIR"
log_debug "Ziel:   $BACKUP_DEST"

check_dependencies
check_source
create_backup_dir
create_archive
encrypt_archive
verify_backup
rotate_old_backups
print_summary
