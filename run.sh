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

# Identify the actual user for personal configs
ACTUAL_USER=$SUDO_USER
USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

echo "--- Starting Fedora $FEDORA_VERSION KDE Heavy Workstation Setup ---"

# 1. Repository Configuration
echo "Configuring repositories..."
dnf5 install -y --skip-broken dnf5-plugins

# RPM Fusion
dnf5 install -y --skip-broken \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm

# Terra Repository
dnf install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release

echo "Repositories configured."

# 2. KDE Group Installs
echo "Installing KDE Environment Groups..."
dnf5 group install --skip-broken -y "kde-desktop" "kde-apps" "kde-media"

# 3. Comprehensive DNF Package Install
echo "Installing workstation packages..."

DNF_PACKAGES=(
    # Shells & Terminal
    fish zsh just btop ripgrep fd-find git-delta
    
    # System Core & Hardware
    lm_sensors udisks2 udiskie linux-firmware* powertop smartmontools 
    usbutils pciutils fwupd fwupd-plugin-flashrom fwupd-plugin-modem-manager 
    fwupd-plugin-uefi-capsule-data
    
    # Graphics & Display
    xorg-x11-server-Xwayland switcheroo-control
    mesa-dri-drivers mesa-filesystem mesa-libEGL mesa-libGL mesa-libgbm 
    mesa-va-drivers mesa-vulkan-drivers
    
    # Audio (PipeWire Stack)
    pipewire pipewire-pulse pipewire-alsa pipewire-gstreamer 
    pipewire-jack-audio-connection-kit pipewire-jack-audio-connection-kit-libs 
    pipewire-libs pipewire-plugin-libcamera pipewire-pulseaudio pipewire-utils 
    wireplumber wireplumber-libs playerctl
    
    # Virtualization & Networking
    libvirt-daemon-kvm libvirt-client tailscale nebula nmap iperf3 
    wireguard-tools
    
    # Gaming & Performance
    gamemode gamemode-devel mangohud goverlay corectrl steam-devices steam
    
    # Filesystems, Desktop Tools & Snaps
    exfatprogs ntfs-3g btrfs-progs gimp deja-dup papirus-icon-theme snapd
    
    # KDE Apps (DNF versions to avoid Flatpak duplication)
    kdenlive kcalc filelight ark okular
    
    # Themes
    "materia*"
)

dnf5 upgrade -y --refresh --skip-broken
dnf5 install -y --skip-broken "${DNF_PACKAGES[@]}"

# 4. Enable Services
echo "Enabling system services..."
systemctl enable --now tailscaled
systemctl enable --now libvirtd
systemctl enable --now snapd.socket

# Classic snap support symlink
ln -s /var/lib/snapd/snap /snap 2>/dev/null

# 5. Flatpak Setup
echo "Configuring Flatpaks..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

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

flatpak install -y flathub "${FLATPAKS[@]}"

# 6. User-Specific Zsh Setup
echo "Configuring Zsh for $ACTUAL_USER..."

# Install Oh My Zsh as the user
if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
    sudo -u "$ACTUAL_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Install Plugins
ZSH_CUSTOM="$USER_HOME/.oh-my-zsh/custom"
sudo -u "$ACTUAL_USER" mkdir -p "$ZSH_CUSTOM/plugins"

for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    if [ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]; then
        sudo -u "$ACTUAL_USER" git clone "https://github.com/zsh-users/$plugin" "$ZSH_CUSTOM/plugins/$plugin"
    fi
done

# Generate .zshrc
sudo -u "$ACTUAL_USER" tee "$USER_HOME/.zshrc" > /dev/null <<EOF
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME="terminalparty"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source \$ZSH/oh-my-zsh.sh

export LANG=en_US.UTF-8
export EDITOR="nano"
export VISUAL="nano"
export PATH="\$PATH:\$HOME/.local/bin"

if command -v starship &> /dev/null; then
    eval "\$(starship init zsh)"
fi
EOF

# Use usermod to change shell as root (avoids /etc/shells warnings)
usermod -s /usr/bin/zsh "$ACTUAL_USER"

echo "--- Setup Complete! Please reboot. ---"
