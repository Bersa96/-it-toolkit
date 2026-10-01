# IT Support Toolkit

A comprehensive PowerShell automation toolkit for IT Support engineers, designed for rapid Windows 10/11 system maintenance, initial PC deployment, performance tuning, and network troubleshooting.

---

## Quick Start (One-Liner Execution)

Run the following command in **PowerShell (Run as Administrator)** on the target machine:

```powershell
irm https://raw.githubusercontent.com/Bersa96/-it-toolkit/main/Install.ps1 | iex
```

For offline use, open PowerShell as Administrator and run the actual script path, for example:

```powershell
& 'D:\Sharing\Script\Install.ps1'
# USB example: replace U: and the folder with your actual location
& 'U:\software\Install.ps1'
```

Batch launchers are not included in this repository. If execution policy blocks the script, follow your organization's approved policy; do not disable it globally.

---

## Feature Modules (Structured by Workflow)

### I. DEPLOYMENT & ONBOARDING

#### 1. Standard App Deployment (Offline-First Priority)
* Automated deployment with 3-tier fallback: **Flash Drive / Local Storage -> Winget -> Direct Vendor Download**.
* Software supported: Google Chrome, Adobe Acrobat Reader, PDF24 Creator, WhatsApp Desktop, 7-Zip, VLC Media Player, AnyDesk, Zoom, Notion.
* Offline and downloaded installers must return 0 (completed) or 3010 (restart required). Failed downloads/installations are reported per application; a failed installer is retained for diagnosis. Installer success is not an independent application health check.

#### 2. Performance & Low-End Tuning ("Potato PC" Optimizer)
* **Conservative Smart Profile**: Disables Edge startup/background operation, adding reduced animations only when detected RAM is <=8 GB. Storage detection uses NVMe or matched physical-disk metadata; unknown storage never triggers an HDD profile.
* **Volume Analysis / Optimization**: Read-only analysis or explicitly confirmed native Windows media-aware optimization. Does not disable SysMain, Prefetch, Search, or scheduled drive optimization.
* **Memory / Visual / Explorer Profiles**: Separate, previewed changes with explicit YES confirmation and read-back verification. Pagefile, telemetry and GameDVR remain unchanged. No fixed RAM-saving claim; benefits depend on workload.
* **Optional App Removal**: Previews a narrow games/news/weather list and requires REMOVE. Current-user packages only; no other-user or provisioned-package removal. Reinstall via Store if needed; tuning rollback does not restore removed apps.
* **Saved-State Rollback**: Original registry values/types are saved before changes in `%ProgramData%\ITToolkit\Performance\settings-<user SID>.xml`. Restore uses that baseline, not guessed defaults. It cannot reconstruct settings modified by older toolkit versions. Existing baseline values are retained across runs.
* Per-user changes apply to the account running the elevated toolkit. Machine-wide Edge policies can affect all users and stop background web apps/notifications. Explorer is not forcibly restarted; sign out/in when convenient.

#### 3. System Integrity Repair
* Automated execution of DISM image servicing (`/Cleanup-Image /RestoreHealth`) followed by System File Checker (`sfc /scannow`).

#### 4. Printer & Spooler Recovery
* **Stuck Queue Clear**: Stops spooler, purges corrupt spooler files, and restarts services.
* **Fix Printer Offline (WSD to TCP/IP Port Converter)**: Resolves sleep/disconnect issues on network printers by converting WSD ports to Standard TCP/IP (RAW 9100).
* **Disable SNMP Status**: Prevents false offline status triggers on standard TCP/IP ports.
* **Quick Network Printer Setup**: Pre-configured setup for office printers.
* **Printer Sharing Host Mode**: Shares one selected local printer with a unique Windows share name, verifies the spooler, and enables File and Printer Sharing firewall rules on Domain/Private profiles.
* **Printer Sharing Client Mode**: Tests TCP 445, connects to a host printer using `\\HOST\SHARE`, and verifies the local mapping.
* **Printer Share Diagnostics & Rollback**: Lists local/shared printers, writes a Desktop report, and safely unshares a host printer or removes a client mapping.
* **Connection Diagnosis and Guided Repair**: Main menu [4], submenu [10], or offered after a failed [7] connection. Captures the complete error, exception HRESULT and native code when available; checks DNS, TCP 445/135, local spooler and installed drivers. Saves a report in Windows Temp. TCP success is not proof that a share or print job works.
* Repair choices open the host login, Credential Manager or driver management; optionally start a stopped local spooler, inspect remote printer shares, or retry Connect with mapping verification. No automatic credential deletion, queue purge, host configuration, SMB1 enablement, or firewall/Point and Print weakening. Remote inventory requires suitable RPC access/permissions. Per-user mapping belongs to the account running the toolkit; finish with a Test Page under the intended user.

Printer sharing uses the host's stable DNS name or DHCP-reserved IP. Same-subnet clients can connect directly; routed clients additionally need TCP 445/RPC permitted between the relevant networks. The toolkit does not store printer credentials or grant anonymous folder access.

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
* Copies the installer to local temporary storage and verifies size and SHA-256 before launch, allowing USB removal after verification.
* Uses the legacy third-party antivirus cleanup: stops/deletes matching services and removes non-Defender/non-Kaspersky Security Center registrations and listed vendor registry keys before installer staging.
* WARNING: this is not a complete antivirus uninstall. Drivers may remain, and existing protection can be damaged even when Kaspersky installation fails or its installer is missing. Use only on deployment machines with explicit authorization.
* Failed installers remain available for diagnosis. Exit code 3010 is explicitly reported as requiring a restart, not fully ready protection.

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

#### 13. MeshAgent Setup (MeshCentral)
* Automated deployment of MeshCentral remote management agent.
* Staged local execution with architecture validation and service runtime verification (`Mesh Agent`).

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
