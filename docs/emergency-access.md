# Notfallplan: SSH-Zugang nach Key-Verlust

## Übersicht

Da `PasswordAuthentication no` gesetzt ist, gibt es **keinen Passwort-Fallback**.
Dieser Plan beschreibt alle Optionen, wenn SSH-Keys verloren gehen.

---

## Szenario 1: Primärer Deploy-Key verloren (Emergency-Key noch vorhanden)

**Symptom**: `ssh_keys/<hostname>/id_ed25519` fehlt oder beschädigt.
**Voraussetzung**: Emergency-Key existiert unter `ssh_keys/emergency/<hostname>/id_ed25519`.

### Schritt 1 — Manueller Notfallzugang prüfen

```bash
ssh -i ssh_keys/emergency/<hostname>/id_ed25519 \
    -p <port> deploy@<host-ip>
```

### Schritt 2 — Neuen primären Key deployen

```bash
ansible-playbook playbooks/hardening/ssh_only.yml \
    --limit <hostname> \
    --private-key ssh_keys/emergency/<hostname>/id_ed25519 \
    -e "ssh_key_rotate=true"
```

### Schritt 3 — Emergency-Key danach rotieren

```bash
ansible-playbook playbooks/maintenance/emergency_access.yml \
    --limit <hostname> \
    -e "ssh_emergency_key_rotate=true"
```

---

## Szenario 2: Alle Controller-Keys verloren (Emergency-Key-Backup vorhanden)

**Symptom**: Gesamtes `ssh_keys/`-Verzeichnis verloren (Controller defekt/gelöscht).
**Voraussetzung**: Off-Site-Backup des `ssh_keys/emergency/`-Verzeichnisses vorhanden.

### Schritt 1 — Emergency-Keys aus Backup wiederherstellen

```bash
# GPG-verschlüsseltes Backup entschlüsseln (falls vorhanden):
gpg --decrypt ssh_keys_emergency_backup_<datum>.tar.gz.gpg | tar -xz

# Oder manuell vom USB-Stick:
cp -r /media/usb/ssh_keys_emergency/ ./ssh_keys/emergency/
chmod -R 700 ./ssh_keys/emergency/
```

### Schritt 2 — Weiter wie Szenario 1

---

## Szenario 3: Alle Keys verloren, kein Backup (Out-of-Band-Zugang)

**Symptom**: Kein SSH-Zugang, keine Keys, kein Backup.
**Lösung**: Out-of-Band-Konsole des Hosts verwenden.

### Cloud-Provider

| Provider | Konsolen-Zugang |
|----------|----------------|
| Hetzner Cloud | Console → Server → Konsole öffnen |
| AWS EC2 | EC2 Instance Connect oder Systems Manager Session Manager |
| Azure | Azure Portal → VM → Serielle Konsole |
| Proxmox/VMware | Direkt über Hypervisor-Konsole |
| Bare Metal | IPMI / iDRAC / iLO → Remote Console |

### Nach Out-of-Band-Zugang

```bash
# Als root einloggen (via Konsole):
sudo su -

# Neuen temporären Key manuell hinterlegen:
echo "<neuer_public_key>" >> /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys

# Sshd-Status prüfen:
systemctl status ssh
```

Dann normalen SSH-Zugang wiederherstellen:

```bash
ansible-playbook playbooks/hardening/ssh_only.yml \
    --limit <hostname> \
    -e "ssh_key_rotate=true"
```

---

## Szenario 4: Einzelner Key kompromittiert (Laptop gestohlen)

**Symptom**: Key könnte unbefugt genutzt werden.
**Lösung**: Key sofort widerrufen, neuen deployen.

```bash
# Key sofort sperren (auf allen Hosts):
ansible-playbook playbooks/maintenance/revoke_key.yml \
    -e "revoke_key_file=ssh_keys/<hostname>/id_ed25519.pub"

# Oder auf bestimmten Hosts:
ansible-playbook playbooks/maintenance/revoke_key.yml \
    -e "revoke_key_file=ssh_keys/<hostname>/id_ed25519.pub" \
    --limit <hostname>

# Danach neuen Key deployen:
ansible-playbook playbooks/hardening/ssh_only.yml \
    --limit <hostname> \
    -e "ssh_key_rotate=true"
```

---

## Prävention — Regelmäßige Maßnahmen

### Emergency-Keys deployen (einmalig nach Bootstrap)

```bash
ansible-playbook playbooks/maintenance/emergency_access.yml
```

### Emergency-Keys testen (monatlich empfohlen)

```bash
ansible-playbook playbooks/maintenance/emergency_access.yml \
    --tags emergency_check
```

### Keys off-site sichern

```bash
# Manuell (GPG-verschlüsselt auf USB):
tar -czf - ssh_keys/emergency/ | \
    gpg --symmetric --cipher-algo AES256 \
    -o /media/usb/ssh_keys_emergency_$(date +%Y%m%d).tar.gz.gpg

# Berechtigungen überprüfen:
ls -la ssh_keys/emergency/
```

### Vault-Backup

```bash
# .vault_pass ebenfalls sichern (enthält das Vault-Passwort):
gpg --symmetric --cipher-algo AES256 \
    -o /media/usb/vault_pass_backup_$(date +%Y%m%d).gpg \
    .vault_pass
```

---

## Wichtige Pfade

| Datei | Zweck |
|-------|-------|
| `ssh_keys/<host>/id_ed25519` | Primärer Deploy-Key (privat) |
| `ssh_keys/emergency/<host>/id_ed25519` | Emergency Break-Glass Key (privat) |
| `ssh_keys/known_hosts` | SSH Host-Keys (MITM-Schutz) |
| `ssh_keys/backups/` | Zeitgestempelte Backups der primären Keys |
| `.vault_pass` | Ansible Vault Passwort |

**Alle `ssh_keys/`-Inhalte sind in `.gitignore` — werden nie committed.**

---

## Kontakt & Eskalation

Bei Sicherheitsvorfällen (kompromittierter Key, unbefugter Zugriff):

1. Betroffene Keys sofort widerrufen: `revoke_key.yml`
2. Auditd-Logs auf betroffenen Hosts prüfen: `journalctl -u auditd`
3. SSH-Auth-Log prüfen: `grep "Accepted publickey" /var/log/auth.log`
4. Incident-Response-Prozess einleiten
