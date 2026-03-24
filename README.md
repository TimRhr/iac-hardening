# 🏗️ Infrastructure as Code — Ansible Hardening Projekt

Zentrales Ansible-Projekt zur automatisierten Einrichtung, Härtung und Wartung von Linux-Servern nach **BSI IT-Grundschutz SYS.1.3** und **CIS Benchmark Level 2**.

---

## 📋 Inhaltsverzeichnis

1. [Voraussetzungen](#voraussetzungen)
2. [Projektstruktur](#projektstruktur)
3. [Schnellstart — Neuen Server aufsetzen](#schnellstart)
4. [Vault-Setup (Secrets)](#vault-setup)
5. [Playbook-Referenz](#playbook-referenz)
6. [Inventory konfigurieren](#inventory)
7. [Häufige Operationen](#operationen)
8. [Tag-Referenz](#tags)
9. [BSI-Compliance-Übersicht](#compliance)

---

## Voraussetzungen

**Auf dem Ansible-Controller (deinem Rechner):**

```bash
# Ansible installieren
pip install ansible

# Collections installieren (einmalig)
ansible-galaxy collection install -r requirements.yml -p collections/
```

**Auf den Ziel-Servern:**
- Ubuntu 20.04/22.04/24.04 oder Debian 11/12 oder RHEL/Rocky 8/9
- SSH-Zugang (initial mit Passwort oder Root-Key)
- Python 3 (wird automatisch installiert wenn fehlend)

---

## Projektstruktur

```
infra/
├── ansible.cfg                    # Zentrale Konfiguration (Inventory, Vault, Logging)
├── requirements.yml               # Ansible-Collections
├── .gitignore                     # ssh_keys/, .vault_pass nie committen!
├── scripts/
│   ├── vault-setup.sh             # Vault erstmalig einrichten
│   └── vault-rotate.sh            # Vault-Passwort rotieren
│
├── inventory/
│   ├── hosts.yml                  # Server-Inventar (IPs, Gruppen)
│   └── group_vars/
│       ├── all/
│       │   ├── main.yml           # Globale Variablen (für alle Server)
│       │   └── vault.yml          # 🔒 Verschlüsselte Secrets (Vault)
│       ├── webservers/main.yml    # Nur für Webserver-Gruppe
│       └── dbservers/main.yml     # Nur für DB-Server-Gruppe
│
├── playbooks/
│   ├── deployment/
│   │   ├── bootstrap.yml          # Ersteinrichtung neuer Server
│   │   └── syslog_server.yml      # Zentralen Syslog-Server einrichten
│   ├── hardening/
│   │   ├── site.yml               # ⭐ VOLLSTÄNDIGES Hardening (SSH + OS)
│   │   ├── ssh_only.yml           # Nur SSH-Härtung
│   │   ├── os_only.yml            # Nur OS-Härtung
│   │   ├── logging.yml            # Nur Remote-Logging
│   │   └── aide.yml               # Nur AIDE (Filesystem-Monitoring)
│   ├── maintenance/
│   │   ├── update.yml             # Paket-Updates (rollierend)
│   │   ├── reboot.yml             # Kontrollierter Reboot (1 Server gleichzeitig)
│   │   ├── ssh_key_rotation.yml   # SSH-Key-Rotation (BSI SYS.1.3.A4)
│   │   └── aide_reinit.yml        # AIDE-Datenbank neu initialisieren
│   └── monitoring/
│       ├── check.yml              # Health Check & Status-Report
│       └── vuln_scan.yml          # Vulnerability-Scan (OpenSCAP + Trivy)
│
├── roles/
│   ├── ssh_hardening/             # SSH-Härtung (CIS + BSI)
│   └── os_hardening/             # OS-Härtung (CIS L2 + BSI SYS.1.3)
│
├── ssh_keys/                      # 🔒 Generierte SSH-Keys (nicht ins Git!)
│   └── <hostname>/
│       ├── id_ed25519             # Privater Key (chmod 600)
│       ├── id_ed25519.pub         # Öffentlicher Key
│       └── rotation.yml           # Rotations-Metadaten
│
└── reports/                       # 📋 Compliance- & Scan-Reports (nicht ins Git!)
    └── <hostname>/
        ├── <hostname>_ssh_report_<datum>.txt
        ├── <hostname>_os_report_<datum>.txt
        ├── <hostname>_lynis_<datum>.txt
        ├── oscap_<datum>.html
        └── trivy_<datum>.txt
```

---

## Schnellstart

### Neuen Server von Null aufsetzen

```
Schritt 1: Inventory   →   Schritt 2: Vault   →   Schritt 3: Bootstrap   →   Schritt 4: Hardening
```

#### Schritt 1 — Server ins Inventory eintragen

```yaml
# inventory/hosts.yml
all:
  children:
    webservers:
      hosts:
        web01:
          ansible_host: 192.168.1.10   # ← IP deines Servers
```

#### Schritt 2 — Vault einrichten (Secrets verschlüsseln)

```bash
# Vault-Passwort setzen und vault.yml verschlüsseln
./scripts/vault-setup.sh

# Secrets eintragen (öffnet Editor)
ansible-vault edit inventory/group_vars/all/vault.yml
```

Mindestens diese Werte setzen:
```yaml
vault_aide_alert_mail: "admin@example.com"     # AIDE-Alerts
vault_bootloader_grub_password: "StarkesPasswort123!"
```

#### Schritt 3 — Bootstrap (Ersteinrichtung)

Einmalig: Deploy-User anlegen, sudo konfigurieren, Python installieren.

```bash
# Mit root (frische Cloud-VM / VPS)
ansible-playbook playbooks/deployment/bootstrap.yml \
  -u root --ask-pass --limit web01

# Mit Ubuntu-User (AWS, Hetzner Cloud-Init)
ansible-playbook playbooks/deployment/bootstrap.yml \
  -u ubuntu -e "bootstrap_initial_user=ubuntu" --limit web01
```

#### Schritt 4 — Vollständiges Hardening

```bash
# Erst Dry-Run (keine Änderungen, nur Vorschau)
ansible-playbook playbooks/hardening/site.yml --check --diff --limit web01

# Hardening ausführen
ansible-playbook playbooks/hardening/site.yml --limit web01
```

Nach dem Hardening:
- SSH-Key liegt unter `ssh_keys/web01/id_ed25519`
- Verbindung: `ssh -i ssh_keys/web01/id_ed25519 -p 22 deploy@192.168.1.10`
- Reports unter `reports/web01/`

---

## Vault-Setup

Sensitive Daten werden mit **Ansible Vault** verschlüsselt. Niemals im Klartext in Git committen!

```bash
# Erstmalig einrichten
./scripts/vault-setup.sh

# Inhalte bearbeiten
ansible-vault edit inventory/group_vars/all/vault.yml

# Passwort rotieren (z.B. jährlich)
./scripts/vault-rotate.sh

# Einzelne Werte verschlüsseln (für direkte Verwendung in Vars)
ansible-vault encrypt_string 'geheimes_passwort' --name 'mein_secret'
```

**Verfügbare Vault-Variablen:**

| Variable | Beschreibung |
|---|---|
| `vault_ssh_key_passphrase` | Passphrase für SSH-Deploy-Key |
| `vault_bootloader_grub_password` | GRUB-Passwort (Klartext → wird zu PBKDF2) |
| `vault_aide_alert_mail` | E-Mail für AIDE Filesystem-Alerts |
| `vault_alert_webhook_url` | Slack/Teams Webhook für Alerts |
| `vault_syslog_tls_ca_cert` | CA-Zertifikat für TLS-Syslog |
| `vault_syslog_tls_client_cert` | Client-Zertifikat für TLS-Syslog |
| `vault_syslog_tls_client_key` | Client-Key für TLS-Syslog |

---

## Playbook-Referenz

### deployment/bootstrap.yml
**Wann:** Einmalig auf einem frischen Server, bevor Hardening ausgeführt wird.  
**Was:** Deploy-User anlegen, sudo konfigurieren, Basis-Pakete installieren.

```bash
ansible-playbook playbooks/deployment/bootstrap.yml \
  -u root --ask-pass --limit web01
```

---

### hardening/site.yml ⭐
**Wann:** Nach Bootstrap, bei Neuaufsetzen, nach Konfigurationsänderungen.  
**Was:** Vollständiges SSH + OS Hardening in einem Run.

```bash
# Alle Server
ansible-playbook playbooks/hardening/site.yml

# Einzelner Server
ansible-playbook playbooks/hardening/site.yml --limit web01

# Bestimmte Gruppe
ansible-playbook playbooks/hardening/site.yml --limit webservers

# Nur SSH-Teil
ansible-playbook playbooks/hardening/site.yml --tags ssh

# Nur OS-Teil
ansible-playbook playbooks/hardening/site.yml --tags os

# Mit Key-Rotation erzwingen
ansible-playbook playbooks/hardening/site.yml \
  -e "ssh_key_rotate=true" --tags keygen
```

**Was wird gehärtet:**

| Bereich | Maßnahmen |
|---|---|
| SSH | Key-only Auth, Ed25519, starke Ciphers, Banner, Firewall |
| AppArmor | enforce-Mode, Profile für sshd/rsyslog/auditd |
| Bootloader | GRUB-Passwort, grub.cfg chmod 400, Recovery deaktiviert |
| Kernel | sysctl: ASLR, SYN-Cookies, IP-Forwarding, ICMP-Schutz |
| Dateisystem | /tmp noexec nosuid, SUID-Scan, World-Writable-Check |
| AIDE | Filesystem-Monitoring, DB-Initialisierung, Cronjob, Alert |
| Logging | rsyslog + journald persistent, Remote-Forwarding, Queue |
| PAM | pwquality, faillock, Passwort-Historie |
| sudo | timestamp_type=tty, Logging, NOPASSWD-Scan |
| Shell | TMOUT=900, PATH-Schutz, .netrc/.forward entfernen |
| Cron | cron.allow/at.allow Whitelist |
| systemd | Service-Sandboxing (NoNewPrivileges, PrivateTmp, etc.) |
| Auditd | CIS Level 2 Regeln, Remote-Plugin |
| Fail2ban | SSH Brute-Force-Schutz, Rate Limiting |
| NTP | systemd-timesyncd mit deutschen NTP-Servern |
| Updates | Unattended-Upgrades für Sicherheits-Patches |
| Lynis | Hardening-Score-Messung nach Abschluss |

---

### hardening/ssh_only.yml
**Wann:** Nur SSH-Konfiguration ändern, z.B. nach Port-Änderung oder Key-Tausch.

```bash
ansible-playbook playbooks/hardening/ssh_only.yml
ansible-playbook playbooks/hardening/ssh_only.yml --tags keygen   # Nur Keys
ansible-playbook playbooks/hardening/ssh_only.yml --tags verify   # Nur Test
```

---

### hardening/os_only.yml
**Wann:** Nur OS-Härtung wiederholen, z.B. nach System-Updates.

```bash
ansible-playbook playbooks/hardening/os_only.yml
ansible-playbook playbooks/hardening/os_only.yml --tags kernel    # sysctl
ansible-playbook playbooks/hardening/os_only.yml --tags auditd    # Auditd-Regeln
ansible-playbook playbooks/hardening/os_only.yml --tags apparmor  # AppArmor
```

---

### hardening/logging.yml
**Wann:** Remote-Logging-Ziel ändern oder Logging-Konfiguration aktualisieren.

```bash
# Remote-Server setzen
ansible-playbook playbooks/hardening/logging.yml \
  -e "syslog_remote_host=syslog.example.com"

# Auf TLS umstellen
ansible-playbook playbooks/hardening/logging.yml \
  -e "syslog_remote_protocol=tls syslog_remote_port=6514"
```

---

### deployment/syslog_server.yml
**Wann:** Einmalig, um einen dedizierten zentralen Syslog-Server einzurichten.

```bash
ansible-playbook playbooks/deployment/syslog_server.yml --limit mon01
```

Danach in `group_vars/all/main.yml`:
```yaml
syslog_remote_host: "192.168.1.30"
```

---

### maintenance/update.yml
**Wann:** Regelmäßig (wöchentlich) oder nach bekannten CVEs.  
**Wie:** Rollierend — maximal 30% der Server gleichzeitig.

```bash
# Alle Server updaten
ansible-playbook playbooks/maintenance/update.yml

# Mit automatischem Reboot wenn nötig
ansible-playbook playbooks/maintenance/update.yml \
  -e "reboot_if_needed=true"

# Nur eine Gruppe
ansible-playbook playbooks/maintenance/update.yml --limit webservers
```

---

### maintenance/ssh_key_rotation.yml
**Wann:** Automatisch (rotiert nur wenn Key älter als `ssh_key_rotation_days=180`).  
**Wie:** Sicher mit Übergangsphase — alter Key bleibt aktiv bis neuer Key verifiziert.

```bash
# Automatisch (rotiert nur veraltete Keys)
ansible-playbook playbooks/maintenance/ssh_key_rotation.yml

# Rotation erzwingen (alle Keys sofort rotieren)
ansible-playbook playbooks/maintenance/ssh_key_rotation.yml \
  -e "ssh_key_rotate=true"

# Kürzerer Zyklus (90 Tage)
ansible-playbook playbooks/maintenance/ssh_key_rotation.yml \
  -e "ssh_key_rotation_days=90"

# Dry-Run — zeigt welche Keys rotiert werden würden
ansible-playbook playbooks/maintenance/ssh_key_rotation.yml --check
```

---

### maintenance/reboot.yml
**Wann:** Nach Kernel-Updates wenn Reboot nötig ist.  
**Wie:** Immer nur 1 Server gleichzeitig mit Verifikation.

```bash
ansible-playbook playbooks/maintenance/reboot.yml
ansible-playbook playbooks/maintenance/reboot.yml --limit web01
```

---

### maintenance/aide_reinit.yml
**Wann:** Nach geplanten System-Änderungen (Updates, neue Pakete installiert).  
**Was:** AIDE-Datenbank-Baseline neu setzen.

```bash
ansible-playbook playbooks/maintenance/aide_reinit.yml --limit web01
```

---

### monitoring/check.yml
**Wann:** Täglich / nach Änderungen.  
**Was:** Uptime, Disk, Memory, laufende Dienste, Fail2ban-Bans, Reboot-Status.

```bash
ansible-playbook playbooks/monitoring/check.yml
ansible-playbook playbooks/monitoring/check.yml --limit web01
```

---

### monitoring/vuln_scan.yml
**Wann:** Wöchentlich / nach CVE-Meldungen.  
**Was:** OpenSCAP (CIS-Profil), Trivy (CVE-Scan auf Paketen).

```bash
# Vollständiger Scan
ansible-playbook playbooks/monitoring/vuln_scan.yml

# Nur CVE-Scan (Trivy)
ansible-playbook playbooks/monitoring/vuln_scan.yml --tags trivy

# Nur Konfigurations-Check (OpenSCAP)
ansible-playbook playbooks/monitoring/vuln_scan.yml --tags oscap

# Fehler bei CRITICAL CVEs erzwingen (für CI/CD)
ansible-playbook playbooks/monitoring/vuln_scan.yml \
  -e "vuln_fail_on_critical=true"
```

Reports werden gespeichert unter:
```
reports/<hostname>/
├── oscap_<datum>.html          # OpenSCAP HTML-Report (im Browser öffnen)
├── oscap_<datum>.xml           # OpenSCAP XML (maschinenlesbar)
├── trivy_<datum>.txt           # Trivy CVE-Liste (lesbar)
├── trivy_<datum>.json          # Trivy JSON (maschinenlesbar)
└── vuln_summary_<datum>.txt    # Zusammenfassung beider Scans
```

---

## Inventory

### Gruppen und Hosts definieren

```yaml
# inventory/hosts.yml
all:
  children:
    webservers:
      hosts:
        web01:
          ansible_host: 192.168.1.10
        web02:
          ansible_host: 192.168.1.11

    dbservers:
      hosts:
        db01:
          ansible_host: 192.168.1.20
      vars:
        ssh_port: 2222          # DB-Server auf anderem SSH-Port

    monitoring:
      hosts:
        mon01:
          ansible_host: 192.168.1.30
```

### Host-spezifische Überschreibungen

```yaml
# inventory/host_vars/web01.yml
ssh_port: 2222
os_timezone: "UTC"
```

### Gruppen-Variablen

```yaml
# inventory/group_vars/webservers/main.yml
ssh_allow_groups:
  - "ssh-users"
  - "deploy"
```

### Variablen-Hierarchie (höchste Priorität zuerst)

```
host_vars/<hostname>.yml      > host-spezifisch
group_vars/<gruppe>/main.yml  > gruppen-spezifisch
group_vars/all/main.yml       > global
roles/.../defaults/main.yml   > Rollen-Defaults
```

---

## Häufige Operationen

### Nach OS-Install: Kompletter Setup-Ablauf

```bash
# 1. Server ins Inventory eintragen (inventory/hosts.yml)

# 2. Vault-Secrets prüfen/setzen
ansible-vault edit inventory/group_vars/all/vault.yml

# 3. Bootstrap (einmalig)
ansible-playbook playbooks/deployment/bootstrap.yml \
  -u root --ask-pass --limit <hostname>

# 4. Dry-Run
ansible-playbook playbooks/hardening/site.yml --check --diff --limit <hostname>

# 5. Hardening
ansible-playbook playbooks/hardening/site.yml --limit <hostname>

# 6. Vulnerability-Scan
ansible-playbook playbooks/monitoring/vuln_scan.yml --limit <hostname>
```

### Wöchentliche Wartung

```bash
# Updates einspielen
ansible-playbook playbooks/maintenance/update.yml

# Health-Check
ansible-playbook playbooks/monitoring/check.yml

# Vulnerability-Scan
ansible-playbook playbooks/monitoring/vuln_scan.yml
```

### SSH-Key rotieren (manuell)

```bash
ansible-playbook playbooks/maintenance/ssh_key_rotation.yml \
  -e "ssh_key_rotate=true" --limit web01
```

### Syslog-Server wechseln

```bash
ansible-playbook playbooks/hardening/logging.yml \
  -e "syslog_remote_host=new-syslog.example.com"
```

---

## Tags

Tags ermöglichen das gezielte Ausführen einzelner Aufgaben:

```bash
ansible-playbook playbooks/hardening/site.yml --tags <tag>
```

| Tag | Was wird ausgeführt |
|---|---|
| `ssh` | Alles SSH-bezogene |
| `os` | Alles OS-bezogene |
| `keygen` | SSH-Keys generieren/deployen |
| `verify` | SSH-Login-Test |
| `kernel` | sysctl-Parameter |
| `apparmor` | AppArmor-Profile |
| `bootloader` | GRUB-Konfiguration |
| `aide` | AIDE-Initialisierung |
| `logging` | rsyslog + journald |
| `syslog` | Remote-Syslog-Forwarding |
| `auditd` | Auditd-Regeln |
| `pam` | PAM-Konfiguration |
| `sudo` | sudo-Härtung |
| `shell` | Shell-Timeout, PATH |
| `cron` | Cron-Whitelist |
| `systemd` | Service-Sandboxing |
| `fail2ban` | Fail2ban-Jails |
| `firewall` | UFW/firewalld-Regeln |
| `lynis` | Lynis-Audit |
| `audit` | Compliance-Report |
| `rotation` | SSH-Key-Rotation |
| `oscap` | OpenSCAP-Scan |
| `trivy` | Trivy CVE-Scan |

---

## Compliance

### BSI IT-Grundschutz Abdeckung

| Baustein | Anforderungen | Status |
|---|---|---|
| SYS.1.3.A4 | SSH-Konfiguration + Key-Rotation | ✅ |
| SYS.1.3.A5 | Bootloader-Schutz (GRUB) | ✅ |
| SYS.1.3.A6 | AppArmor + systemd-Sandboxing | ✅ |
| SYS.1.3.A9 | AIDE Filesystem-Monitoring | ✅ |
| OPS.1.1.2 | Ansible Vault (Secrets) | ✅ |
| OPS.1.1.5 | Remote-Syslog + Auditd | ✅ |
| DER.1 | Fail2ban + IDS-Vorbereitung | ✅ |
| DER.3 | Lynis + OpenSCAP + Trivy | ✅ |

### Wichtige Sicherheitshinweise

```
⚠️  ssh_keys/     → NIEMALS ins Git committen (.gitignore vorhanden)
⚠️  .vault_pass   → NIEMALS ins Git committen (.gitignore vorhanden)
⚠️  reports/      → NIEMALS ins Git committen (.gitignore vorhanden)
```

Vor dem ersten `git commit`:
```bash
git status   # Prüfen ob ssh_keys/ oder .vault_pass auftaucht
cat .gitignore
```
