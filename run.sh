#!/bin/bash

# ==========================================
# GLOBAL CONFIGURATION & PACKAGE LISTS
# ==========================================
FEDORA_VERSION=$(rpm -E %fedora)
PURGE_MODE=false

DNF_PACKAGES=(
    fish rsync jq just btop ripgrep fd-find git-delta alien
    lm_sensors udisks2 udiskie linux-firmware* powertop smartmontools 
    usbutils pciutils fwupd fwupd-plugin-flashrom fwupd-plugin-modem-manager 
    fwupd-plugin-uefi-capsule-data xorg-x11-server-Xwayland switcheroo-control
    mesa-dri-drivers mesa-filesystem mesa-libEGL mesa-libGL mesa-libgbm 
    mesa-va-drivers mesa-vulkan-drivers pipewire pipewire-alsa 
    pipewire-gstreamer pipewire-jack-audio-connection-kit 
    pipewire-jack-audio-connection-kit-libs pipewire-libs 
    pipewire-plugin-libcamera pipewire-pulseaudio pipewire-utils 
    wireplumber wireplumber-libs playerctl libvirt-daemon-kvm libvirt-client 
    tailscale nebula nmap iperf3 wireguard-tools gamemode gamemode-devel 
    mangohud goverlay corectrl steam-devices steam exfatprogs ntfs-3g 
    btrfs-progs gimp deja-dup papirus-icon-theme snapd kdenlive kcalc 
    filelight ark okular "materia*" webkit2gtk4.1-devel openssl-devel curl wget file
    libappindicator-gtk3-devel librsvg2-devel
)

FLATPAKS=(
    net.waterfox.waterfox com.github.tchx84.Flatseal
    it.mijorus.gearlever de.leopoldluley.Clapgrep
    im.nheko.Nheko io.github.flattool.Ignition
    io.github.flattool.Warehouse org.gtk.Gtk3theme.Breeze
    org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark
    org.gustavoperedo.FontDownloader io.github.victoralvesf.aonsoku
)

# ==========================================
# ARGUMENT PARSING
# ==========================================
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -v|--version) FEDORA_VERSION="$2"; shift ;;
        --remove) PURGE_MODE=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run as root (use sudo)"
  exit 1
fi

if [ -z "$SUDO_USER" ]; then
  echo "Error: Could not detect the original user. Please run this script using 'sudo ./script.sh'."
  exit 1
fi

ACTUAL_USER=$SUDO_USER
USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

# ==========================================
# PURGE / REMOVE LOGIC
# ==========================================
if [ "$PURGE_MODE" = true ]; then
    echo -e "\033[0;33m=================================================================\033[0m"
    echo "⚠️ WARNING: You are about to completely purge the workstation setup."
    echo "This will remove Flatpaks, Nix, DNF packages, and revert your shell."
    echo -e "\033[0;33m=================================================================\033[0m"
    read -p "Are you absolutely sure you want to proceed? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Purge canceled."
        exit 0
    fi

    echo "--- Starting System Purge ---"
    usermod -s /bin/bash "$ACTUAL_USER"
    rm -rf "$USER_HOME/.oh-my-zsh" "$USER_HOME/.zshrc"
    
    if [ -f "/nix/nix-installer" ]; then
        /nix/nix-installer uninstall --no-confirm
    fi
    rm -f /usr/local/bin/nixmanager
    rm -rf "$USER_HOME/.config/nixpkgs_fedora"

    systemctl disable --now tailscaled libvirtd snapd.socket 2>/dev/null
    rm -f /snap 2>/dev/null
    flatpak uninstall -y "${FLATPAKS[@]}" 2>/dev/null
    flatpak uninstall --unused -y 2>/dev/null
    dnf5 remove -y "${DNF_PACKAGES[@]}" 2>/dev/null
    dnf5 remove -y terra-release rpmfusion-free-release rpmfusion-nonfree-release 2>/dev/null

    echo "--- Purge Complete! Please reboot. ---"
    exit 0
fi

# ==========================================
# MAIN INSTALLATION ROUTINE
# ==========================================
echo "--- Starting Fedora Workstation Setup ---"

dnf install -y dnf5 dnf5-plugins git curl wget zsh tar unzip util-linux sudo

echo "Configuring repositories..."
dnf5 install -y --skip-broken \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm
dnf5 install -y --nogpgcheck --repofrompath "terra,https://repos.fyralabs.com/terra$FEDORA_VERSION" terra-release

echo "Installing KDE Environment Groups..."
dnf5 group install --skip-broken -y "kde-desktop" "kde-apps" "kde-media"
dnf5 -y remove firefox

echo "Installing workstation packages..."
dnf5 upgrade -y --refresh
dnf5 install -y --skip-broken "${DNF_PACKAGES[@]}"

# ==========================================
# 3.1 Tolaria DEB-to-System Tool
# ==========================================
TOLARIA_VER="2026.4.29" 
(
    set -e
    TOLARIA_URL="https://github.com/refactoringhq/tolaria/releases/download/stable-v${TOLARIA_VER}/Tolaria_${TOLARIA_VER}_amd64.deb"
    TOLARIA_TGZ="tolaria-${TOLARIA_VER}.tgz"
    WORK_DIR="/tmp/tolaria_install"
    mkdir -p "$WORK_DIR"
    pushd "$WORK_DIR" > /dev/null
    wget -q "$TOLARIA_URL" -O "input.deb"
    sudo alien -tvc "input.deb"
    mkdir -p contents
    tar -xvf "$TOLARIA_TGZ" -C contents/ --strip-components=1
    sudo rsync -avz contents/usr/ /usr/
    DESKTOP_FILE="/usr/share/applications/Tolaria.desktop"
    if [ -f "$DESKTOP_FILE" ]; then
        sudo sed -i 's/^Categories=.*/Categories=Office;Utility;/' "$DESKTOP_FILE"
        update-desktop-database /usr/share/applications 2>/dev/null
    fi
    popd > /dev/null
    rm -rf "$WORK_DIR"
)

echo "Enabling system services..."
systemctl enable --now tailscaled
systemctl enable --now libvirtd
systemctl enable --now snapd.socket
mkdir -p /var/lib/snapd/snap
ln -s /var/lib/snapd/snap /snap 2>/dev/null || true

echo "Configuring Flatpaks..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub "${FLATPAKS[@]}"

# ==========================================
# 6. NIX PACKAGE MANAGER SETUP
# ==========================================
echo "Setting up Determinate Nix and nixpkgs_fedora flake..."
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm

# Bridge the Nix installation to the current root shell session
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

sudo -H -u "$ACTUAL_USER" mkdir -p "$USER_HOME/.config/nixpkgs_fedora"
sudo -H -u "$ACTUAL_USER" tee "$USER_HOME/.config/nixpkgs_fedora/flake.nix" > /dev/null << 'EOF'
{
  description = "nixpkgs-fedora custom flake with unfree packages enabled";
  inputs = { nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable"; };
  outputs = { self, nixpkgs }: {
    legacyPackages.x86_64-linux = import nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
  };
}
EOF

# Write nixmanager and set permissions
# (nixmanager cat block from your version goes here)
# ... [Assuming nixmanager heredoc logic remains same as provided in previous prompt] ...
# mv -f /tmp/nixmanager.sh /usr/local/bin/nixmanager
# chmod +x /usr/local/bin/nixmanager

# ==========================================
# 6.1 NIX PACKAGE MIGRATION (USER LEVEL)
# ==========================================
echo "Starting migration to Nix packages for $ACTUAL_USER..."

NIX_PACKAGES=(
    discord bitwarden-desktop telegram-desktop pika-backup
    vlc easyeffects supersonic boxbuddy mission-center
    protonplus retroarch jellyfin-media-player podman-desktop
    filezilla zed-editor github-desktop lutris devpod
    heroic prismlauncher blender audacity inkscape
    wike slack foliate thunderbird nicotine-plus
    vscodium signal-desktop bleachbit bottles
    obsidian obs-studio
)

sudo -H -u "$ACTUAL_USER" bash -c '
    if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi
    for PKG in '"${NIX_PACKAGES[*]}"'; do
        echo "Installing: $PKG"
        /usr/local/bin/nixmanager install "$PKG"
    done
'

# ==========================================
# 7. VERIFICATION, 8. ZSH, 9. AUDIT
# ==========================================
# ... [Rest of your script logic remains as you provided] ...
