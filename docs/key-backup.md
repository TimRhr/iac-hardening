# SSH-Key-Backup-Strategie

## Übersicht

SSH-Keys liegen ausschließlich lokal im `ssh_keys/`-Verzeichnis des Ansible-Controllers.
Bei Verlust des Controllers (Crash, Brand, Diebstahl) wären alle Keys verloren — inklusive
Emergency-Keys. Diese Anleitung beschreibt das Off-Site-Backup.

**Was wird gesichert:**
- `ssh_keys/<hostname>/id_ed25519` — Primäre Deploy-Keys
- `ssh_keys/emergency/<hostname>/id_ed25519` — Emergency Break-Glass Keys
- `ssh_keys/known_hosts` — Vertrauenswürdige Host-Keys (MITM-Schutz)
- `ssh_keys/backups/` — Rotierte/archivierte Keys

**Was wird NICHT gesichert (und ist nicht nötig):**
- `reports/` — Reproduzierbar durch erneuten Scan
- `.vault_pass` — Separate Backup-Strategie (s.u.)

---

## Schnellstart

```bash
# 1. GPG-Backup-Key erzeugen (einmalig):
gpg --full-gen-key   # Typ: RSA 4096 oder Ed25519

# 2. Fingerprint ermitteln:
gpg --list-keys | grep -A1 "backup"

# 3. Backup ausführen:
BACKUP_GPG_FINGERPRINT="<fingerprint>" ./scripts/backup-keys.sh

# 4. Backup-Datei auf USB-Stick oder sicheren Cloud-Speicher kopieren
```

---

## Konfiguration

### Umgebungsvariablen

| Variable | Default | Beschreibung |
|----------|---------|--------------|
| `BACKUP_GPG_FINGERPRINT` | — | GPG-Key-Fingerprint (Pflicht bei GPG-Modus) |
| `BACKUP_DEST` | `~/.ansible-key-backups` | Lokales Backup-Ziel |
| `USE_SYMMETRIC` | `false` | Symmetrische Verschlüsselung (Passwort) |
| `SOURCE_DIR` | `<project>/ssh_keys` | Zu sicherndes Verzeichnis |
| `KEEP_BACKUPS` | `10` | Anzahl beizubehaltender Backups |
| `VERBOSE` | `false` | Debug-Ausgaben |

### Vault-Variable

Für Backup-Keys die via Ansible verwaltet werden:

```bash
# vault.yml (verschlüsselt) ergänzen:
ansible-vault edit inventory/group_vars/all/vault.yml
```

```yaml
# GPG-Fingerprint des Backup-Keys (kein Geheimnis — öffentlich)
vault_backup_gpg_fingerprint: "ABCD1234EFGH5678..."
```

---

## Backup-Varianten

### Variante 1: GPG-Key (empfohlen)

Sicherster Ansatz: Backup ist nur mit dem Backup-Privatschlüssel entschlüsselbar.

```bash
# Backup erstellen:
BACKUP_GPG_FINGERPRINT="<fingerprint>" ./scripts/backup-keys.sh

# Auf USB-Stick sichern:
BACKUP_GPG_FINGERPRINT="<fingerprint>" \
BACKUP_DEST="/media/usb/ansible-backups" \
  ./scripts/backup-keys.sh

# Wiederherstellen:
gpg --decrypt ~/.ansible-key-backups/ansible-keys_<datum>.tar.gz.gpg \
  | tar -xz -C ./
```

### Variante 2: Symmetrisch (Passwort)

Einfacher, kein separater GPG-Key nötig. Passwort sicher aufbewahren!

```bash
# Backup erstellen (fragt nach Passwort):
USE_SYMMETRIC=true ./scripts/backup-keys.sh

# Wiederherstellen:
gpg --decrypt ansible-keys_<datum>.tar.gz.gpg | tar -xz -C ./
```

### Variante 3: Direkt auf USB-Stick

```bash
# USB-Stick einbinden, dann:
BACKUP_GPG_FINGERPRINT="<fingerprint>" \
BACKUP_DEST="/media/usb/ansible-backups" \
  ./scripts/backup-keys.sh

# Alle Backups auflisten:
ls -lh /media/usb/ansible-backups/
```

---

## Automatisches Backup (Cron)

```bash
# Crontab bearbeiten:
crontab -e
```

```cron
# Täglich um 02:00 Uhr — SSH-Key-Backup
0 2 * * * BACKUP_GPG_FINGERPRINT="<fingerprint>" \
           /pfad/zu/iac-hardening/scripts/backup-keys.sh \
           >> /var/log/ansible-key-backup.log 2>&1
```

Oder auf USB-Stick (nur wenn gemountet):

```cron
# Täglich um 02:00 — Backup auf USB (falls gemountet)
0 2 * * * [ -d /media/usb/ansible-backups ] && \
           BACKUP_GPG_FINGERPRINT="<fingerprint>" \
           BACKUP_DEST="/media/usb/ansible-backups" \
           /pfad/zu/iac-hardening/scripts/backup-keys.sh
```

---

## Vault-Passwort-Backup

Das `.vault_pass` sollte **getrennt** von den SSH-Keys gesichert werden.
Wenn beides im selben Backup liegt und das Backup kompromittiert wird, verliert man alles.

```bash
# Vault-Passwort separat verschlüsseln:
gpg --symmetric --cipher-algo AES256 \
    -o ~/.vault-pass-backup-$(date +%Y%m%d).gpg \
    .vault_pass

# Auf zweitem USB-Stick sichern (anderer als SSH-Key-Backup!)
```

---

## Backup-Wiederherstellung

### Vollständige Wiederherstellung (Controller verloren)

```bash
# 1. Neuen Controller aufsetzen, Ansible + GPG installieren
# 2. Backup-GPG-Key importieren (aus sicherem Speicher):
gpg --import backup-private-key.asc

# 3. SSH-Key-Backup entschlüsseln:
gpg --decrypt ansible-keys_<datum>.tar.gz.gpg | tar -xz

# 4. Verzeichnis an richtigen Ort verschieben:
mv ssh_keys/ /pfad/zu/iac-hardening/

# 5. Berechtigungen setzen:
find /pfad/zu/iac-hardening/ssh_keys -type f -name "id_ed25519" -exec chmod 600 {} \;
find /pfad/zu/iac-hardening/ssh_keys -type d -exec chmod 700 {} \;

# 6. Verbindung testen:
ssh -i ssh_keys/<hostname>/id_ed25519 -p <port> deploy@<host>
```

### Einzelnen Host-Key wiederherstellen

```bash
# Backup entschlüsseln in temporäres Verzeichnis:
gpg --decrypt ansible-keys_<datum>.tar.gz.gpg \
  | tar -xz -C /tmp/key-restore/

# Spezifischen Key herauskopieren:
cp /tmp/key-restore/ssh_keys/<hostname>/id_ed25519 \
   ssh_keys/<hostname>/id_ed25519
chmod 600 ssh_keys/<hostname>/id_ed25519

# Temporäre Dateien löschen:
rm -rf /tmp/key-restore/
```

---

## Checkliste — Regelmäßige Backup-Hygiene

| Häufigkeit | Aufgabe |
|------------|---------|
| Nach jedem Hardening | `./scripts/backup-keys.sh` ausführen |
| Wöchentlich | Backup-Datei auf Off-Site-Medium kopieren |
| Monatlich | Backup-Integrität prüfen (Decrypt-Test) |
| Halbjährlich | Emergency-Key-Backup testen (`emergency_access.yml --tags emergency_check`) |
| Jährlich | GPG-Backup-Key rotieren |

---

## Wichtige Hinweise

```
⚠️  ssh_keys/ ist in .gitignore — nie ins Git committen!
⚠️  Vault-Passwort und SSH-Keys auf GETRENNTEN Medien sichern
⚠️  Backup-GPG-Privatschlüssel sicher verwahren (analog zu SSH-Keys)
⚠️  Backup regelmäßig testen — ungetestete Backups sind wertlos
```
