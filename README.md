# IT Support Toolkit

A PowerShell automation script for Windows 10/11 system maintenance, initial PC deployment, and troubleshooting.

## Usage

Run the following command in Administrator PowerShell on the target machine:

```powershell
irm https://raw.githubusercontent.com/Bersa96/-it-toolkit/main/Install.ps1 | iex
```

## Features

### Application Deployment
Automated silent installation of standard software via Windows Package Manager (winget):
* WhatsApp Desktop
* Google Chrome
* Mozilla Firefox
* Adobe Acrobat Reader 64-bit
* PDF24 Creator
* 7-Zip Archiver
* VLC Media Player
* AnyDesk Remote
* Zoom Client
* Notion Desktop

### System Tweaks
* Enables system-wide Dark Mode
* Displays "This PC" and User Profile shortcuts on Desktop
* Configures File Explorer to open to This PC
* Shows hidden files and file extensions
* Removes Searchbox and Widgets from the Taskbar
* Enables "End Task" option in the Taskbar context menu
* Enables Clipboard History (Win + V)
* Disables telemetry and advertising ID

### System Maintenance
* Runs DISM RestoreHealth and SFC scannow
* Clears print spooler queue and restarts print service
* Resets network stack and flushes DNS cache
* Disables Windows Auto-Update

## License

MIT License
