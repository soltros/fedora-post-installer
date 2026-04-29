#!/bin/bash

# ==========================================
# GLOBAL CONFIGURATION & PACKAGE LISTS
# ==========================================
FEDORA_VERSION=$(rpm -E %fedora)
PURGE_MODE=false

DNF_PACKAGES=(
    fish rsync just btop ripgrep fd-find git-delta alien
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

# ==========================================
# 3.1 Tolaria DEB-to-System Tool
# ==========================================
TOLARIA_VER="2026.4.29" 

# Logic: Download DEB -> Convert to TGZ -> Strip top folder -> Sync to /usr
(
    set -e
    echo "Processing Tolaria version ${TOLARIA_VER}..."
    
    TOLARIA_URL="https://github.com/refactoringhq/tolaria/releases/download/stable-v${TOLARIA_VER}/Tolaria_${TOLARIA_VER}_amd64.deb"
    TOLARIA_TGZ="tolaria-${TOLARIA_VER}.tgz"
    WORK_DIR="/tmp/tolaria_install"

    mkdir -p "$WORK_DIR"
    pushd "$WORK_DIR" > /dev/null

    # 1. Download
    echo "Downloading Tolaria..."
    wget -q "$TOLARIA_URL" -O "input.deb"

    # 2. Convert (Uses alien from your DNF_PACKAGES list)
    echo "Converting DEB to TGZ..."
    sudo alien -tvc "input.deb"

    # 3. Extract and Install
    echo "Extracting and syncing files..."
    mkdir -p contents
    tar -xvf "$TOLARIA_TGZ" -C contents/ --strip-components=1
    
    echo "Syncing Tolaria files to system..."
    sudo rsync -avz contents/usr/ /usr/

    # 4. Fix Plasma Menu Placement
    echo "Fixing desktop menu category..."
    DESKTOP_FILE="/usr/share/applications/Tolaria.desktop"

    if [ -f "$DESKTOP_FILE" ]; then
        # Set category to Office and Utility so it shows up in Plasma's menus
        sudo sed -i 's/^Categories=.*/Categories=Office;Utility;/' "$DESKTOP_FILE"
        
        # Force Plasma to refresh the application menu
        update-desktop-database /usr/share/applications 2>/dev/null
        echo "✓ Desktop entry updated."
    fi

    # 5. Cleanup
    popd > /dev/null
    rm -rf "$WORK_DIR"
    echo "✓ Tolaria installation and menu fix complete."
)

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

# Enhanced Nix Package Manager
# A contextual, sub-command based script for managing Nix packages

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_NAME=$(basename "$0")

usage() {
    echo -e "${BLUE}Usage: $SCRIPT_NAME <command> [options]${NC}"
    echo ""
    echo "Commands:"
    echo "  install <package>    Install a package from nixpkgs"
    echo "  remove <package>     Remove an installed package (by name or index)"
    echo "  list                 List installed packages"
    echo "  search <query>       Search for packages in nixpkgs"
    echo "  upgrade              Upgrade all packages"
    echo "  help                 Show this help message"
}

check_nix() {
    if ! command -v nix &> /dev/null; then
        echo -e "${RED}Error: Nix is not installed or not in PATH${NC}" >&2
        exit 1
    fi
}

update_shortcuts() {
    echo -e "${BLUE}Syncing applications to desktop menu...${NC}"
    local nix_apps="$HOME/.nix-profile/share/applications"
    local local_apps="$HOME/.local/share/applications"
    local nix_icons="$HOME/.nix-profile/share/icons"
    local local_icons="$HOME/.local/share/icons"
    
    mkdir -p "$local_apps" "$local_icons"
    
    # Clean old nixmanager symlinks
    find "$local_apps" -name "nixmanager-*.desktop" -delete 2>/dev/null
    
    # Symlink current .desktop files to DE folder
    if [ -d "$nix_apps" ]; then
        for desktop in "$nix_apps"/*.desktop; do
            [ -e "$desktop" ] || continue
            local base=$(basename "$desktop")
            # Link to the absolute path in the Nix store
            ln -sf "$(readlink -f "$desktop")" "$local_apps/nixmanager-$base"
        done
    fi
    
    # Recursively symlink icons for immediate rendering
    if [ -d "$nix_icons" ]; then
        cp -rsf "$nix_icons/"* "$local_icons/" 2>/dev/null || true
    fi
    
    # Cleanup any dead icon symlinks
    find "$local_icons" -xtype l -delete 2>/dev/null || true
    
    # Force KDE/GNOME to refresh
    if command -v update-desktop-database &> /dev/null; then
        update-desktop-database "$local_apps" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache &> /dev/null; then
        gtk-update-icon-cache -f -t "$local_icons/hicolor" 2>/dev/null || true
    fi
    if [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]] || [[ "$DESKTOP_SESSION" == *"plasma"* ]]; then
        if command -v kbuildsycoca6 &> /dev/null; then
            kbuildsycoca6 --noincremental 2>/dev/null || true
        fi
        if command -v qdbus &> /dev/null; then
            qdbus org.kde.KLauncher /KLauncher reparseConfiguration 2>/dev/null || true
        fi
    fi
    if command -v xdg-desktop-menu &> /dev/null; then
        xdg-desktop-menu forceupdate 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ Desktop shortcuts updated for Nix profile${NC}"
}

install_package() {
    local package="$1"
    if [[ -z "$package" ]]; then
        echo -e "${RED}Error: Package name is required${NC}" >&2
        exit 1
    fi
    
    echo -e "${BLUE}Installing package: $package${NC}"
    if nix profile add "$HOME/.config/nixpkgs_fedora#$package"; then
        echo -e "${GREEN}✓ Successfully installed: $package${NC}"
        update_shortcuts
    else
        echo -e "${RED}✗ Failed to install: $package${NC}" >&2
        exit 1
    fi
}

remove_package() {
    local package="$1"
    if [[ -z "$package" ]]; then
        echo -e "${RED}Error: Package name or index is required${NC}" >&2
        exit 1
    fi

    echo -e "${BLUE}Removing package: $package${NC}"
    if nix profile remove "$package"; then
        echo -e "${GREEN}✓ Successfully removed: $package${NC}"
        update_shortcuts
    else
        echo -e "${RED}✗ Failed to remove: $package${NC}" >&2
        exit 1
    fi
}

list_packages() {
    echo -e "${BLUE}Installed packages:${NC}"
    nix profile list
}

search_packages() {
    local query="$1"
    if [[ -z "$query" ]]; then
        echo -e "${RED}Error: Search query is required${NC}" >&2
        exit 1
    fi
    echo -e "${BLUE}Searching for packages matching: $query${NC}"
    NIXPKGS_ALLOW_UNFREE=1 nix search nixpkgs "$query"
}

upgrade_packages() {
    echo -e "${BLUE}Upgrading all packages...${NC}"
    if nix profile upgrade; then
        echo -e "${GREEN}✓ All packages upgraded successfully${NC}"
    else
        echo -e "${RED}✗ Failed to upgrade packages${NC}" >&2
        exit 1
    fi
}

main() {
    check_nix
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi
    
    local command="$1"
    case "$command" in
        install) shift; install_package "$1" ;;
        remove) shift; remove_package "$1" ;;
        list) list_packages ;;
        search) shift; search_packages "$1" ;;
        upgrade) upgrade_packages ;;
        help|--help|-h) usage ;;
        *) echo -e "${RED}Error: Unknown command '$command'${NC}" >&2; usage; exit 1 ;;
    esac
}

main "$@"
EOF

# Force overwrite the destination file
mv -f /tmp/nixmanager.sh /usr/local/bin/nixmanager
chmod +x /usr/local/bin/nixmanager

# ==========================================
# 7. VERIFICATION AND RETRY PHASE
# ==========================================
echo "--- Initial Verification and Retries ---"
MISSING_DNF=()
for pkg in "${DNF_PACKAGES[@]}"; do
    if ! dnf5 list installed "$pkg" &>/dev/null; then MISSING_DNF+=("$pkg"); fi
done
if [ ${#MISSING_DNF[@]} -gt 0 ]; then dnf5 install -y --skip-broken "${MISSING_DNF[@]}"; fi

MISSING_FLATPAKS=()
for fpkg in "${FLATPAKS[@]}"; do
    if ! flatpak info "$fpkg" &>/dev/null; then MISSING_FLATPAKS+=("$fpkg"); fi
done
if [ ${#MISSING_FLATPAKS[@]} -gt 0 ]; then flatpak install -y flathub "${MISSING_FLATPAKS[@]}"; fi

# ==========================================
# 8. USER-SPECIFIC ZSH SETUP
# ==========================================
echo "Configuring Zsh for $ACTUAL_USER..."
if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
    sudo -H -u "$ACTUAL_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM="$USER_HOME/.oh-my-zsh/custom"
sudo -H -u "$ACTUAL_USER" mkdir -p "$ZSH_CUSTOM/plugins"
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    if [ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]; then
        sudo -H -u "$ACTUAL_USER" git clone "https://github.com/zsh-users/$plugin" "$ZSH_CUSTOM/plugins/$plugin"
    fi
done

sudo -H -u "$ACTUAL_USER" tee "$USER_HOME/.zshrc" > /dev/null <<EOF
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME="terminalparty"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source \$ZSH/oh-my-zsh.sh

if [ -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
    . "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
fi

alias update="sudo dnf upgrade -y; sudo flatpak update -y; sudo snap refresh"
export LANG=en_US.UTF-8
export EDITOR="nano"
export VISUAL="nano"
export PATH="\$PATH:\$HOME/.local/bin"

if command -v starship &> /dev/null; then
    eval "\$(starship init zsh)"
fi
EOF

chown "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/.zshrc"
usermod -s /usr/bin/zsh "$ACTUAL_USER"

# ==========================================
# 9. FINAL SYSTEM AUDIT CHECKLIST
# ==========================================
echo ""
echo "=========================================================="
echo "               FINAL SYSTEM AUDIT CHECKLIST               "
echo "=========================================================="

# Helper function for printing checklist items
print_check() {
    if [ "$1" -eq 0 ]; then
        echo -e "[\033[0;32m ✓ \033[0m] $2"
    else
        echo -e "[\033[0;31m ✗ \033[0m] $2"
    fi
}

# 1. DNF Packages
FAILED_DNF=()
for pkg in "${DNF_PACKAGES[@]}"; do
    if ! dnf5 list installed "$pkg" &>/dev/null; then FAILED_DNF+=("$pkg"); fi
done
if [ ${#FAILED_DNF[@]} -eq 0 ]; then
    print_check 0 "DNF Packages (${#DNF_PACKAGES[@]} installed)"
else
    print_check 1 "DNF Packages (${#FAILED_DNF[@]} missing: ${FAILED_DNF[*]})"
fi

# 2. Flatpaks
FAILED_FLATPAKS=()
for fpkg in "${FLATPAKS[@]}"; do
    if ! flatpak info "$fpkg" &>/dev/null; then FAILED_FLATPAKS+=("$fpkg"); fi
done
if [ ${#FAILED_FLATPAKS[@]} -eq 0 ]; then
    print_check 0 "Flatpak Applications (${#FLATPAKS[@]} installed)"
else
    print_check 1 "Flatpak Applications (${#FAILED_FLATPAKS[@]} missing: ${FAILED_FLATPAKS[*]})"
fi

# 3. Nix & nixmanager
if [ -d "/nix/var/nix" ] || command -v nix &>/dev/null; then print_check 0 "Nix Package Manager"; else print_check 1 "Nix Package Manager"; fi
if [ -x "/usr/local/bin/nixmanager" ]; then print_check 0 "nixmanager CLI tool"; else print_check 1 "nixmanager CLI tool"; fi
if [ -f "$USER_HOME/.config/nixpkgs_fedora/flake.nix" ]; then print_check 0 "nixpkgs_fedora Flake Config"; else print_check 1 "nixpkgs_fedora Flake Config"; fi

# 4. Zsh Environment
if [ -d "$USER_HOME/.oh-my-zsh" ]; then print_check 0 "Oh My Zsh Framework"; else print_check 1 "Oh My Zsh Framework"; fi
USER_SHELL=$(getent passwd "$ACTUAL_USER" | cut -d: -f7)
if [ "$USER_SHELL" = "/usr/bin/zsh" ]; then print_check 0 "Zsh set as default shell"; else print_check 1 "Zsh set as default shell (Currently: $USER_SHELL)"; fi

# 5. System Services
systemctl is-active --quiet tailscaled && print_check 0 "Tailscale Service" || print_check 1 "Tailscale Service"
systemctl is-active --quiet libvirtd && print_check 0 "Libvirt Service" || print_check 1 "Libvirt Service"
systemctl is-active --quiet snapd.socket && print_check 0 "Snapd Socket" || print_check 1 "Snapd Socket"

echo "=========================================================="
if [ ${#FAILED_DNF[@]} -eq 0 ] && [ ${#FAILED_FLATPAKS[@]} -eq 0 ]; then
    echo -e "\033[0;32mAll systems go! A system reboot is highly recommended.\033[0m"
else
    echo -e "\033[0;33mSetup completed with warnings. Please review the missing items. A reboot is recommended.\033[0m"
fi
echo "=========================================================="
