# IT Support Toolkit

A comprehensive PowerShell automation toolkit for IT Support engineers, designed for rapid Windows 10/11 system maintenance, initial PC deployment, performance tuning, and network troubleshooting.

---

## Quick Start (One-Liner Execution)

Run the following command in **PowerShell (Run as Administrator)** on the target machine:

```powershell
irm https://raw.githubusercontent.com/Bersa96/-it-toolkit/main/Install.ps1 | iex
```

> **Offline Usage via USB**: Run `_START_MENU_IT.bat` or `_RUN_TOOLKIT.bat` directly from your flash drive with automatic administrative elevation and policy bypass.

---

## Feature Modules (Structured by Workflow)

### I. DEPLOYMENT & ONBOARDING

#### 1. Standard App Deployment (Offline-First Priority)
* Automated deployment with 3-tier fallback: **Flash Drive / Local Storage -> Winget -> Direct Vendor Download**.
* Software supported: Google Chrome, Adobe Acrobat Reader, PDF24 Creator, WhatsApp Desktop, 7-Zip, VLC Media Player, AnyDesk, Zoom, Notion.

#### 2. Performance & Low-End Tuning ("Potato PC" Optimizer)
* **Smart Auto-Boost**: Automatically detects storage type (NVMe/SATA SSD vs Mechanical HDD) and installed RAM capacity.
* **HDD 100% Disk Fix**: Disables SysMain (SuperFetch), Windows Search aggressive indexing, Prefetcher, and background telemetry.
* **SSD Health & TRIM Tune**: Verifies and triggers live volume `Re-Trim`, disables unnecessary defragmentation.
* **Low RAM / Memory Saver**: Strips heavy acrylic/mica animations while keeping fonts crisp, disables Microsoft Edge startup boost/background extension preload (saves 400MB+ RAM).
* **Safe AppX Bloatware Purge**: Cleans pre-installed promotional apps/games (Candy Crush, Disney, TikTok, Cortana, etc.) without breaking Store, Calculator, Photos, or Notepad.
* **Rollback / Restore Default**: Reverts all performance and visual settings to factory defaults.

#### 3. System Integrity Repair
* Automated execution of DISM image servicing (`/Cleanup-Image /RestoreHealth`) followed by System File Checker (`sfc /scannow`).

#### 4. Printer & Spooler Recovery
* **Stuck Queue Clear**: Stops spooler, purges corrupt spooler files, and restarts services.
* **Fix Printer Offline (WSD to TCP/IP Port Converter)**: Resolves sleep/disconnect issues on network printers by converting WSD ports to Standard TCP/IP (RAW 9100).
* **Disable SNMP Status**: Prevents false offline status triggers on standard TCP/IP ports.
* **Quick Network Printer Setup**: Pre-configured setup for office printers.

---

### II. DIAGNOSTICS & SYSTEM REPAIR

#### 5. Network & DHCP Recovery
* **Safe Network Stack Reset**: Flushes DNS, clears ARP, and resets Winsock/TCP stack.
* **Fix No IPv4 / DHCP Stuck**: Diagnoses and recovers APIPA (`169.254.x.x`) address issues.
* **Deep Factory Reset (`netcfg -d`)**: Purges corrupted virtual adapters and NDIS filter drivers.
* **Reset Hosts File**: Restores `%windir%\system32\drivers\etc\hosts` to clean factory defaults.
* **Static Diagnostic IP & Dynamic DHCP Toggle**: Allows quick diagnostic IP assignment or one-click dynamic DHCP restoration.
* **Export Full Network Diagnostic Log**: Generates comprehensive hardware, NDIS bindings, WLAN signal, ping reachability, and DHCP event logs to Desktop and USB for rapid analysis.

#### 6. Windows Update Controller
* **Pause Updates for 9999 Days (~27 Years)**: Safely pauses Windows Updates dynamically via UX Settings registry without breaking the Settings UI.
* **Resume / Restore Updates**: Instantly unpauses updates and restores update services.

#### 7. Lansweeper Asset Onboarding
* Sets compliant NetBIOS hostnames and computer descriptions.
* Configures local administrative management profile, Remote UAC (`LocalAccountTokenFilterPolicy`), Remote Registry, and WMI/RPC firewall rules.
* Silently installs `LsAgent` from USB, local storage, or network share.

#### 8. Kaspersky Endpoint Deployment
* Interactive installation wizard with automatic cleanup of conflicting antivirus remnants (360 Total Security, AVG, Avast, Smadav, McAfee, Norton, Bitdefender, Malwarebytes).
* Cleans legacy SecurityCenter2 WMI provider registrations.

---

### III. COMPLIANCE & TELEMETRY CONTROL

#### 9. Software Telemetry Blocker
* **Autodesk AutoCAD Blocker**: Stops and disables Autodesk Genuine Service via IFEO debugger lock, redirects license tracking domains in `hosts`, and blocks `acad.exe` in Windows Firewall.
* **EaseUS Suite Blocker**: Blocks telemetry, popup up-sells, and background tracking for Partition Master, Data Recovery, and Todo Backup.

---

### IV. NETWORKING & REMOTE ACCESS

#### 10. SMB Share & Stealth Manager
* Converts standard shares to hidden administrative shares (with `$`) and vice-versa.
* Creates authenticated / anonymous hidden shares with full NTFS permissions.
* Toggles PC visibility in Windows Network Discovery (`FDResPub`).
* Flushes NetBIOS cache, DNS, and stale SMB client sessions.

#### 11. High-Speed LAN Scanner
* High-speed parallel ping scanner across `/24` subnets (scans 254 IPs in under 5 seconds).
* Resolves hostnames and identifies active office endpoints, servers, and printers.

#### 12. Remote Desktop (RDP) Manager
* **Native RDP Toggle**: Enables/disables Remote Desktop server and configures firewall rules.
* **Windows Home RDP Bypass**: Automatically installs and configures RDP Wrapper with community `rdpwrap.ini` updates.
* **Port Listener Verification**: Live testing on port 3389 and TermService health.

---

## Security & Privacy

This toolkit is designed with enterprise security best practices:
* **No Plaintext Secrets in Documentation**: Sensitive environment credentials, server passwords, and agency tokens are never published in this repository.
* **Dynamic Environment Variables**: For automated and unattended deployments across different client domains or workgroups, credentials can be overridden on the target machine via standard environment variables:
  * `IT_TOOLKIT_LOCAL_ADMIN_USER`
  * `IT_TOOLKIT_LOCAL_ADMIN_PASSWORD`
  * `IT_TOOLKIT_DEPLOY_USER`
  * `IT_TOOLKIT_DEPLOY_PASSWORD`
  * `IT_TOOLKIT_LSAGENT_KEY`

---

## License

Distributed under the [MIT License](LICENSE).
