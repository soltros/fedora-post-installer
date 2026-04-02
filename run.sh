#!/bin/bash

# Default to current system version, but allow override
FEDORA_VERSION=$(rpm -E %fedora)

# Handle flags (e.g., --version 43)
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -v|--version) FEDORA_VERSION="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root (use sudo)"
  exit 1
fi

echo "--- Starting Fedora $FEDORA_VERSION KDE Heavy Workstation Setup ---"

# 1. Add current user to wheel group
if [ -n "$SUDO_USER" ]; then
    usermod -aG wheel "$SUDO_USER"
    echo "Added $SUDO_USER to the wheel group."
fi

# 2. Repository Configuration (RPM Fusion & Terra)
echo "Configuring repositories..."
# Install plugins and RPM Fusion
dnf5 install -y dnf5-plugins \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm

# Add Terra Repository
dnf5 config-manager add-repo https://terra.fyralabs.com/terra.repo
echo "Terra repository and RPM Fusion enabled."

# 3. KDE Group Installs
echo "Installing KDE Environment Groups..."
dnf5 group install --skip-broken -y "kde-desktop" "kde-apps" "kde-media"

# 4. Comprehensive DNF Package Install
echo "Installing workstation packages..."

DNF_PACKAGES=(
    # Shells & Terminal
    fish zsh ptyxis starship just btop ripgrep fd-find git-delta
    
    # System Core & Hardware
    lm_sensors udisks2 udiskie linux-firmware* powertop smartmontools 
    usbutils pciutils fwupd fwupd-plugin-flashrom fwupd-plugin-modem-manager 
    fwupd-plugin-uefi-capsule-data
    
    # Graphics & Display
    sddm xorg-x11-server-Xwayland switcheroo-control
    mesa-dri-drivers mesa-filesystem mesa-libEGL mesa-libGL mesa-libgbm 
    mesa-va-drivers mesa-vulkan-drivers
    
    # Audio (PipeWire Stack)
    pipewire pipewire-pulse pipewire-alsa pipewire-gstreamer 
    pipewire-jack-audio-connection-kit pipewire-jack-audio-connection-kit-libs 
    pipewire-libs pipewire-plugin-libcamera pipewire-pulseaudio pipewire-utils 
    wireplumber wireplumber-libs playerctl
    
    # Bluetooth
    bluez bluez-cups bluez-libs bluez-obexd
    
    # Virtualization & Networking
    libvirt-daemon-kvm libvirt-client tailscale nebula nmap iperf3 
    wireguard-tools
    
    # Gaming & Performance
    gamemode gamemode-devel mangohud goverlay corectrl steam-devices steam
    
    # Filesystems, Desktop Tools & Snaps
    exfatprogs ntfs-3g btrfs-progs gimp deja-dup papirus-icon-theme snapd
    
    # Themes (Native Repo)
    "materia*"
)

dnf5 upgrade -y --refresh
dnf5 install -y "${DNF_PACKAGES[@]}"

# 5. Install Feishin (Latest RPM)
echo "Installing Feishin..."
FEISHIN_URL=$(curl -s https://api.github.com/repos/jeffvli/feishin/releases/latest | grep "browser_download_url.*rpm" | cut -d '"' -f 4)
if [ -n "$FEISHIN_URL" ]; then
    wget -O /tmp/feishin.rpm "$FEISHIN_URL"
    dnf5 install -y /tmp/feishin.rpm
    rm /tmp/feishin.rpm
fi

# 6. Enable Services
echo "Enabling system services..."
systemctl enable sddm
systemctl enable --now tailscaled
systemctl enable --now libvirtd
systemctl enable --now bluetooth
systemctl enable --now snapd.socket

# Optional: Classic snap support symlink
ln -s /var/lib/snapd/snap /snap 2>/dev/null

# 7. Flatpak Setup
echo "Configuring Flatpaks..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

FLATPAKS=(
    net.waterfox.waterfox com.discordapp.Discord com.github.tchx84.Flatseal
    com.bitwarden.desktop com.valvesoftware.Steam org.telegram.desktop
    it.mijorus.gearlever org.gnome.World.PikaBackup org.videolan.VLC
    com.github.wwmm.easyeffects io.github.dweymouth.supersonic
    io.github.dvlv.boxbuddyrs de.leopoldluley.Clapgrep im.nheko.Nheko
    io.github.flattool.Ignition io.github.flattool.Warehouse
    io.missioncenter.MissionCenter com.vysp3r.ProtonPlus org.libretro.RetroArch
    net.lutris.Lutris org.libreoffice.LibreOffice com.github.iwalton3.jellyfin-media-player
    io.podman_desktop.PodmanDesktop org.filezillaproject.Filezilla dev.zed.Zed
    io.github.shiftey.Desktop org.gtk.Gtk3theme.Breeze org.gtk.Gtk3theme.adw-gtk3
    org.gtk.Gtk3theme.adw-gtk3-dark org.gustavoperedo.FontDownloader
    sh.loft.devpod com.heroicgameslauncher.hgl org.prismlauncher.PrismLauncher
    org.blender.Blender org.audacityteam.Audacity org.inkscape.Inkscape
    org.kde.kdenlive com.github.hugolabe.Wike org.kde.kcalc com.slack.Slack
    com.github.johnfactotum.Foliate org.kde.filelight org.kde.ark
    org.kde.okular org.mozilla.Thunderbird org.nicotine_plus.Nicotine
    com.vscodium.codium
)
flatpak install -y flathub "${FLATPAKS[@]}"

echo "--- Setup Complete! Please reboot to finalize all changes. ---"
