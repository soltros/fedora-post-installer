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
  echo "Error: Please run as root (use sudo)"
  exit 1
fi

# Ensure the script is run via 'sudo' so we know who the actual user is.
if [ -z "$SUDO_USER" ]; then
  echo "Error: Could not detect the original user. Please run this script using 'sudo ./script.sh' rather than from a pure root shell."
  exit 1
fi

# Identify the actual user for personal configs
ACTUAL_USER=$SUDO_USER
USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

echo "--- Starting Fedora $FEDORA_VERSION KDE Heavy Workstation Setup ---"

# 0. Bootstrap Core Dependencies
echo "Bootstrapping core utilities..."
dnf install -y dnf5 dnf5-plugins git curl wget zsh tar unzip util-linux sudo

# 1. Repository Configuration
echo "Configuring repositories..."
dnf5 install -y --skip-broken \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm

dnf5 install -y --nogpgcheck --repofrompath "terra,https://repos.fyralabs.com/terra$FEDORA_VERSION" terra-release
echo "Repositories configured."

# 2. KDE Group Installs
echo "Installing KDE Environment Groups..."
dnf5 group install --skip-broken -y "kde-desktop" "kde-apps" "kde-media"

# 2.5 Remove firefox for Waterfox later on
dnf5 -y remove firefox

# 3. Comprehensive DNF Package Install
echo "Installing workstation packages..."

DNF_PACKAGES=(
    fish just btop ripgrep fd-find git-delta
    lm_sensors udisks2 udiskie linux-firmware* powertop smartmontools 
    usbutils pciutils fwupd fwupd-plugin-flashrom fwupd-plugin-modem-manager 
    fwupd-plugin-uefi-capsule-data xorg-x11-server-Xwayland switcheroo-control
    mesa-dri-drivers mesa-filesystem mesa-libEGL mesa-libGL mesa-libgbm 
    mesa-va-drivers mesa-vulkan-drivers pipewire pipewire-pulse pipewire-alsa 
    pipewire-gstreamer pipewire-jack-audio-connection-kit 
    pipewire-jack-audio-connection-kit-libs pipewire-libs 
    pipewire-plugin-libcamera pipewire-pulseaudio pipewire-utils 
    wireplumber wireplumber-libs playerctl libvirt-daemon-kvm libvirt-client 
    tailscale nebula nmap iperf3 wireguard-tools gamemode gamemode-devel 
    mangohud goverlay corectrl steam-devices steam exfatprogs ntfs-3g 
    btrfs-progs gimp deja-dup papirus-icon-theme snapd kdenlive kcalc 
    filelight ark okular "materia*"
)

dnf5 upgrade -y --refresh --skip-broken
dnf5 install -y --skip-broken "${DNF_PACKAGES[@]}"

# 4. Enable Services
echo "Enabling system services..."
systemctl enable --now tailscaled
systemctl enable --now libvirtd
systemctl enable --now snapd.socket

# Classic snap support symlink
mkdir -p /var/lib/snapd/snap
ln -s /var/lib/snapd/snap /snap 2>/dev/null || true

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

# ==========================================
# 6. VERIFICATION AND RETRY PHASE
# ==========================================
echo "--- Verifying Installations ---"

# Verify DNF Packages
MISSING_DNF=()
echo "Checking DNF packages..."
for pkg in "${DNF_PACKAGES[@]}"; do
    # Suppress output, we only care if the exit code fails
    if ! dnf5 list installed "$pkg" &>/dev/null; then
        MISSING_DNF+=("$pkg")
    fi
done

if [ ${#MISSING_DNF[@]} -gt 0 ]; then
    echo "Warning: ${#MISSING_DNF[@]} DNF packages failed to install. Retrying..."
    echo "Missing DNF packages: ${MISSING_DNF[*]}"
    dnf5 install -y --skip-broken "${MISSING_DNF[@]}"
else
    echo "All requested DNF packages successfully verified."
fi

# Verify Flatpak Packages
MISSING_FLATPAKS=()
echo "Checking Flatpak packages..."
for fpkg in "${FLATPAKS[@]}"; do
    if ! flatpak info "$fpkg" &>/dev/null; then
        MISSING_FLATPAKS+=("$fpkg")
    fi
done

if [ ${#MISSING_FLATPAKS[@]} -gt 0 ]; then
    echo "Warning: ${#MISSING_FLATPAKS[@]} Flatpak packages failed to install. Retrying..."
    echo "Missing Flatpaks: ${MISSING_FLATPAKS[*]}"
    flatpak install -y flathub "${MISSING_FLATPAKS[@]}"
else
    echo "All requested Flatpak packages successfully verified."
fi
echo "--- Verification Complete ---"
# ==========================================

# 7. User-Specific Zsh Setup
echo "Configuring Zsh for $ACTUAL_USER..."

# Install Oh My Zsh as the user
if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
    sudo -H -u "$ACTUAL_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Install Plugins
ZSH_CUSTOM="$USER_HOME/.oh-my-zsh/custom"
sudo -H -u "$ACTUAL_USER" mkdir -p "$ZSH_CUSTOM/plugins"

for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    if [ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]; then
        sudo -H -u "$ACTUAL_USER" git clone "https://github.com/zsh-users/$plugin" "$ZSH_CUSTOM/plugins/$plugin"
    fi
done

# Generate .zshrc
sudo -H -u "$ACTUAL_USER" tee "$USER_HOME/.zshrc" > /dev/null <<EOF
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME="terminalparty"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source \$ZSH/oh-my-zsh.sh

# Alias
alias update="sudo dnf upgrade -y; sudo flatpak update -y; sudo snap refresh"

export LANG=en_US.UTF-8
export EDITOR="nano"
export VISUAL="nano"
export PATH="\$PATH:\$HOME/.local/bin"

if command -v starship &> /dev/null; then
    eval "\$(starship init zsh)"
fi
EOF

# Ensure proper permissions
chown "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/.zshrc"

# Use usermod to change shell as root
usermod -s /usr/bin/zsh "$ACTUAL_USER"

echo "--- Setup Complete! Please reboot. ---"
