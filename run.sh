#!/bin/bash

# ==========================================
# GLOBAL CONFIGURATION & PACKAGE LISTS
# ==========================================
FEDORA_VERSION=$(rpm -E %fedora)
PURGE_MODE=false

DNF_PACKAGES=(
    fish just btop ripgrep fd-find git-delta
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
    filelight ark okular "materia*"
)

FLATPAKS=(
    net.waterfox.waterfox com.discordapp.Discord com.github.tchx84.Flatseal
    com.bitwarden.desktop org.telegram.desktop it.mijorus.gearlever 
    org.gnome.World.PikaBackup org.videolan.VLC com.github.wwmm.easyeffects 
    io.github.dweymouth.supersonic io.github.dvlv.boxbuddyrs 
    de.leopoldluley.Clapgrep im.nheko.Nheko io.github.flattool.Ignition 
    io.github.flattool.Warehouse io.missioncenter.MissionCenter 
    com.vysp3r.ProtonPlus org.libretro.RetroArch net.lutris.Lutris 
    com.github.iwalton3.jellyfin-media-player io.podman_desktop.PodmanDesktop 
    org.filezillaproject.Filezilla dev.zed.Zed io.github.shiftey.Desktop 
    org.gtk.Gtk3theme.Breeze org.gtk.Gtk3theme.adw-gtk3 
    org.gtk.Gtk3theme.adw-gtk3-dark org.gustavoperedo.FontDownloader
    sh.loft.devpod com.heroicgameslauncher.hgl org.prismlauncher.PrismLauncher
    org.blender.Blender org.audacityteam.Audacity org.inkscape.Inkscape
    com.github.hugolabe.Wike com.slack.Slack com.github.johnfactotum.Foliate 
    org.mozilla.Thunderbird org.nicotine_plus.Nicotine com.vscodium.codium 
    io.github.victoralvesf.aonsoku org.signal.Signal org.bleachbit.BleachBit 
    com.usebottles.bottles md.obsidian.Obsidian com.obsproject.Studio
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

    echo "1/6 Reverting shell to bash..."
    usermod -s /bin/bash "$ACTUAL_USER"
    rm -rf "$USER_HOME/.oh-my-zsh" "$USER_HOME/.zshrc"
    
    echo "2/6 Uninstalling Determinate Nix & configs..."
    if [ -f "/nix/nix-installer" ]; then
        /nix/nix-installer uninstall --no-confirm
    fi
    rm -f /usr/local/bin/nixmanager
    rm -rf "$USER_HOME/.config/nixpkgs_fedora"

    echo "3/6 Disabling services..."
    systemctl disable --now tailscaled libvirtd snapd.socket 2>/dev/null
    rm -f /snap 2>/dev/null

    echo "4/6 Removing Flatpaks..."
    flatpak uninstall -y "${FLATPAKS[@]}" 2>/dev/null
    flatpak uninstall --unused -y 2>/dev/null

    echo "5/6 Removing DNF Workstation packages..."
    dnf5 remove -y "${DNF_PACKAGES[@]}" 2>/dev/null

    echo "6/6 Removing repositories..."
    dnf5 remove -y terra-release rpmfusion-free-release rpmfusion-nonfree-release 2>/dev/null

    echo "--- Purge Complete! Please reboot. ---"
    exit 0
fi

# ==========================================
# MAIN INSTALLATION ROUTINE
# ==========================================
echo "--- Starting Fedora Workstation Setup ---"

# 0. Bootstrap Core Dependencies
echo "Bootstrapping core utilities..."
dnf install -y dnf5 dnf5-plugins git curl wget zsh tar unzip util-linux sudo

# 1. Repository Configuration
echo "Configuring repositories..."
dnf5 install -y --skip-broken \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm

dnf5 install -y --nogpgcheck --repofrompath "terra,https://repos.fyralabs.com/terra$FEDORA_VERSION" terra-release

# 2. KDE Group Installs
echo "Installing KDE Environment Groups..."
dnf5 group install --skip-broken -y "kde-desktop" "kde-apps" "kde-media"
dnf5 -y remove firefox

# 3. Comprehensive DNF Package Install
echo "Installing workstation packages..."
dnf5 upgrade -y --refresh
dnf5 install -y --skip-broken "${DNF_PACKAGES[@]}"

# 4. Enable Services
echo "Enabling system services..."
systemctl enable --now tailscaled
systemctl enable --now libvirtd
systemctl enable --now snapd.socket

mkdir -p /var/lib/snapd/snap
ln -s /var/lib/snapd/snap /snap 2>/dev/null || true

# 5. Flatpak Setup
echo "Configuring Flatpaks..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub "${FLATPAKS[@]}"

# ==========================================
# 6. NIX PACKAGE MANAGER SETUP
# ==========================================
echo "Setting up Determinate Nix and nixpkgs_fedora flake..."
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm

sudo -H -u "$ACTUAL_USER" mkdir -p "$USER_HOME/.config/nixpkgs_fedora"
sudo -H -u "$ACTUAL_USER" tee "$USER_HOME/.config/nixpkgs_fedora/flake.nix" > /dev/null << 'EOF'
{
  description = "nixpkgs-fedora custom flake with unfree packages enabled";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }: {
    legacyPackages.x86_64-linux = import nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
  };
}
EOF

# Ensure Plasma respects Nix applications globally on reboot
sudo -H -u "$ACTUAL_USER" mkdir -p "$USER_HOME/.config/environment.d"
sudo -H -u "$ACTUAL_USER" tee "$USER_HOME/.config/environment.d/10-nix.conf" > /dev/null << 'EOF'
XDG_DATA_DIRS=$HOME/.nix-profile/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}
EOF

# Remove existing installation to guarantee the latest version is applied on re-runs
rm -f /usr/local/bin/nixmanager

# Write nixmanager to a temporary file, then move to destination
cat << 'EOF' > /tmp/nixmanager.sh
#!/bin/bash
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
SCRIPT_NAME=$(basename "$0")

usage() { echo -e "${BLUE}Usage: $SCRIPT_NAME
