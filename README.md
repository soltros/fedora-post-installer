# fedora-post-installer

A simple Fedora Linux post-installation script optimized for the KDE Plasma spin.

## Features

* **Repository Configuration**: Enables RPM Fusion (Free and Non-Free) and the Terra repository.
* **System Updates**: Performs a full system upgrade using `dnf5` with error-handling for unavailable packages.
* **KDE Environment**: Installs KDE desktop, apps, and media groups.
* **Software Suites**: 
    * Core CLI tools (fish, zsh, starship, btop, ripgrep, just).
    * System utilities (Tailscale, PipeWire, libvirt, fwupd, snapd).
    * Gaming tools (Steam, MangoHud, GameMode, CoreCtrl).
* **Flatpak Integration**: Enables Flathub and installs applications including Discord, Waterfox, Obsidian, Signal, and Aonsoku.
* **Personalization**: 
    * Installs Materia themes and Papirus icons via native repositories.
    * Configures Zsh with Oh My Zsh and plugins (autosuggestions, syntax-highlighting).
    * Sets Zsh as the default shell for the calling user.

## Usage

### Run via curl
To execute the script directly from the GitHub repository:
```bash
curl -sSL https://raw.githubusercontent.com/soltros/fedora-post-installer/main/run.sh | sudo bash
```

To pass a specific Fedora version via curl:
```bash
curl -sSL https://raw.githubusercontent.com/soltros/fedora-post-installer/main/run.sh | sudo bash -s -- --version 43
```

### Local Execution
1.  Download the `run.sh` file.
2.  Make the script executable:
    ```bash
    chmod +x run.sh
    ```
3.  Run the script with sudo:
    ```bash
    sudo ./run.sh
    ```

## Important Notes

* **Reboot**: A system reboot is required after the script finishes to apply kernel updates, group changes, and shell configurations.
* **User Config**: The Zsh configuration is applied to the user who invokes the `sudo` command (detected via `$SUDO_USER`).
* **Package Handling**: The script uses the `--skip-broken` flag to ensure execution continues even if specific packages are temporarily unavailable in the repositories.

---

### Customization
To modify the installed software, edit the `DNF_PACKAGES` and `FLATPAKS` arrays within `run.sh`.
