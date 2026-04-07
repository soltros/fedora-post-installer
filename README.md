# fedora-post-installer

A comprehensive post-installation shell script optimized for Fedora Workstation (specifically the KDE Plasma spin). 

This script handles repository configuration, multi-manager package installations (DNF, Flatpak, Nix), user environment customization, and includes built-in verification loops to ensure reliable deployments.

## Features & Architecture

* **Repository Bootstrapping**: Initializes core utilities before enabling RPM Fusion (Free and Non-Free) and the Terra repository.
* **Failsafe Package Management**: Implements an active verification phase. It checks the installation status of all requested DNF and Flatpak packages and automatically retries any that failed due to temporary mirror sync issues or network timeouts.
* **Nix Package Manager Integration**: 
    * Installs Nix via the Determinate Systems installer (native SELinux support).
    * Configures a local, hidden flake (`~/.config/nixpkgs_fedora`) with unfree packages enabled.
    * Generates `nixmanager`, a custom CLI wrapper located in `/usr/local/bin`, simplifying standard package operations and automatically syncing desktop shortcuts for Nix profiles.
* **Environment & Shell**: 
    * Installs core KDE desktop, apps, and media groups.
    * Configures Zsh as the default shell, installing Oh My Zsh and essential plugins (autosuggestions, syntax-highlighting) for the calling user.
* **Software Provisioning**: 
    * *Core CLI tools*: fish, zsh, starship, btop, ripgrep, just.
    * *System utilities*: Tailscale, PipeWire stack, libvirt, fwupd, snapd.
    * *Gaming tools*: Steam, MangoHud, GameMode, CoreCtrl.
    * *Flatpaks*: Enables Flathub and installs a comprehensive suite including Discord, Waterfox, Obsidian, Signal, and Aonsoku.
* **Final Audit Report**: Concludes with a comprehensive pass/fail checklist verifying the status of all software arrays, system services, frameworks, and shell configurations.

## Usage

The script must be run locally. It relies on `$SUDO_USER` to properly configure personal files and environments, so it must be executed via `sudo` rather than from a direct root shell.

1. Clone the repository and navigate into the directory:
```bash
git clone https://github.com/soltros/fedora-post-installer.git
cd fedora-post-installer
```

2. Make the script executable:
```bash
chmod +x run.sh
```

3. Execute the script:
```bash
sudo ./run.sh
```

### Optional Arguments

* **Override Fedora Version**: The script defaults to your current system version. To force a specific version repository:
  ```bash
  sudo ./run.sh --version 43
  ```

* **System Purge**: To revert the environment, remove Nix, uninstall Flatpaks/DNF packages, and rollback the shell to bash:
  ```bash
  sudo ./run.sh --remove
  ```
  *(Note: This requires a manual confirmation prompt before executing the teardown).*

## Important Notes

* **Privilege Handling**: Do not run this script by logging in as root (e.g., `su -`). You must run it as your standard user via `sudo ./run.sh`. The script extracts your actual username to correctly map the Zsh, Nix, and Flatpak configurations to your home directory.
* **Customization**: The baseline software suites can be modified by editing the `DNF_PACKAGES` and `FLATPAKS` arrays located at the top of the `run.sh` file.
* **Reboot**: A system reboot is mandatory after the script completes to properly apply kernel updates, user group changes, systemd services, and the default shell swap.
