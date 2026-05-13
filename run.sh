#!/bin/bash

# ==========================================
# FEDORA POST-INSTALLER
# ==========================================
# A comprehensive Fedora Linux post-installation script
# with improved error handling, safety, and maintainability.
#
# Usage: sudo ./run.sh [OPTIONS]
# Options:
#   -v, --version VERSION    Specify Fedora version (default: auto-detect)
#   --remove                 Purge all installed components
#   -h, --help               Show this help message
# ==========================================

set -o pipefail  # Fail on pipe errors

# ==========================================
# LOGGING SETUP
# ==========================================
readonly LOG_FILE="/var/log/fedora-post-install.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

trap 'echo "ERROR: Script failed on line $LINENO"; exit 1' ERR

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_section() {
    echo ""
    echo "=========================================================="
    echo "$1"
    echo "=========================================================="
}

log_step() {
    echo "→ $1"
}

# ==========================================
# GLOBAL CONFIGURATION
# ==========================================
readonly FEDORA_VERSION="${FEDORA_VERSION:-$(rpm -E %fedora)}"
readonly TOLARIA_VER="2026.4.29"
readonly TOLARIA_RELEASE_URL="https://github.com/refactoringhq/tolaria/releases/download/stable-v${TOLARIA_VER}"
readonly TOLARIA_UPDATER_URL="https://raw.githubusercontent.com/soltros/fedora-post-installer/main/helpers/tolaria-update"
readonly RPMFUSION_FREE_URL="https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm"
readonly RPMFUSION_NONFREE_URL="https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
readonly TERRA_REPO_URL="https://repos.fyralabs.com/terra${FEDORA_VERSION}"
readonly FLATHUB_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
readonly SSH_REMOTE_PATH="${SSH_REMOTE_PATH:-derrik@ubuntu-server:/mnt/hdd4/files/ssh-keys.tar.gpg}"

PURGE_MODE=false

# ==========================================
# PACKAGE LISTS - Separated by category
# ==========================================

# System & Utilities
DNF_SYSTEM=(
    dnf5 dnf5-plugins git curl wget zsh tar unzip util-linux sudo
    fish rsync jq just btop ripgrep fd-find git-delta alien
    lm_sensors udisks2 udiskie powertop smartmontools
)

# Hardware & Firmware
DNF_HARDWARE=(
    linux-firmware* usbutils pciutils fwupd fwupd-plugin-flashrom
    fwupd-plugin-modem-manager fwupd-plugin-uefi-capsule-data
    xorg-x11-server-Xwayland switcheroo-control
)

# Graphics & Display
DNF_GRAPHICS=(
    mesa-dri-drivers mesa-filesystem mesa-libEGL mesa-libGL mesa-libgbm
    mesa-va-drivers mesa-vulkan-drivers
)

# Audio
DNF_AUDIO=(
    pipewire pipewire-alsa pipewire-gstreamer
    pipewire-jack-audio-connection-kit pipewire-jack-audio-connection-kit-libs
    pipewire-libs pipewire-plugin-libcamera pipewire-pulseaudio pipewire-utils
    wireplumber wireplumber-libs playerctl
)

# Virtualization & Networking
DNF_NETWORK=(
    libvirt-daemon-kvm libvirt-client tailscale nebula nmap iperf3 wireguard-tools
)

# Gaming
DNF_GAMING=(
    gamemode gamemode-devel mangohud goverlay corectrl steam-devices steam
)

# Storage & Filesystem
DNF_STORAGE=(
    exfatprogs ntfs-3g btrfs-progs
)

# Multimedia & Productivity
DNF_MULTIMEDIA=(
    gimp deja-dup kdenlive
)

# Desktop & Themes
DNF_DESKTOP=(
    papirus-icon-theme snapd kcalc filelight ark okular webkit2gtk4.1-devel
)

# Development
DNF_DEVEL=(
    openssl-devel curl wget file libappindicator-gtk3-devel librsvg2-devel
)

# Combine all DNF packages
DNF_PACKAGES=(
    "${DNF_SYSTEM[@]}"
    "${DNF_HARDWARE[@]}"
    "${DNF_GRAPHICS[@]}"
    "${DNF_AUDIO[@]}"
    "${DNF_NETWORK[@]}"
    "${DNF_GAMING[@]}"
    "${DNF_STORAGE[@]}"
    "${DNF_MULTIMEDIA[@]}"
    "${DNF_DESKTOP[@]}"
    "${DNF_DEVEL[@]}"
    "materia-gtk-theme"
)

# Flatpak applications
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
# HELPER FUNCTIONS
# ==========================================

show_help() {
    cat << EOF
Fedora Post-Installer Script

USAGE: sudo ./run.sh [OPTIONS]

OPTIONS:
    -v, --version VERSION    Specify Fedora version (default: auto-detect)
    --remove                 Purge all installed components
    -h, --help               Show this help message

EXAMPLES:
    sudo ./run.sh                    # Install with auto-detected Fedora version
    sudo ./run.sh --version 41       # Install for Fedora 41
    sudo ./run.sh --remove           # Remove all installed components

LOGGING:
    Installation logs are saved to: $LOG_FILE

EOF
}

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR: This script must be run with sudo"
        exit 1
    fi
    
    # Check if SUDO_USER is set
    if [ -z "${SUDO_USER:-}" ]; then
        log "ERROR: Could not detect the original user. Use: sudo ./run.sh"
        exit 1
    fi
    
    # Verify required commands exist
    local required_cmds=(rpm dnf5 curl wget)
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log "ERROR: Required command '$cmd' not found"
            exit 1
        fi
    done
    
    log "✓ Prerequisites met (Fedora $FEDORA_VERSION)"
}

get_user_info() {
    ACTUAL_USER="$SUDO_USER"
    USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
    
    # Verify user exists
    if ! id "$ACTUAL_USER" &>/dev/null; then
        log "ERROR: User '$ACTUAL_USER' not found"
        exit 1
    fi
    
    if [ -z "$USER_HOME" ]; then
        log "ERROR: Could not determine home directory for '$ACTUAL_USER'"
        exit 1
    fi
}

run_as_user() {
    local cmd="$1"
    sudo -H -u "$ACTUAL_USER" bash -c "$cmd"
}

confirm_action() {
    local prompt="$1"
    local response
    
    read -p "$prompt [y/N] " response
    [[ "$response" =~ ^[Yy]$ ]] && return 0 || return 1
}

install_package() {
    local package="$1"
    if ! dnf5 list installed "$package" &>/dev/null; then
        log_step "Installing: $package"
        dnf5 install -y --skip-broken "$package" || log "WARNING: Failed to install $package"
    fi
}

# ==========================================
# PURGE / REMOVE LOGIC
# ==========================================

purge_installation() {
    log_section "SYSTEM PURGE MODE"
    
    cat << EOF
⚠️  WARNING: DESTRUCTIVE OPERATION
This will remove:
  • Flatpaks
  • Nix package manager
  • DNF packages
  • Zsh configuration
  • All related helpers and utilities

This action cannot be easily undone!
EOF
    
    if ! confirm_action "Are you absolutely sure you want to proceed?"; then
        log "Purge canceled by user"
        exit 0
    fi
    
    log_step "1/6: Reverting shell to bash..."
    usermod -s /bin/bash "$ACTUAL_USER" || log "WARNING: Could not change shell"
    rm -rf "$USER_HOME/.oh-my-zsh" "$USER_HOME/.zshrc"
    
    log_step "2/6: Uninstalling Determinate Nix..."
    if [ -f "/nix/nix-installer" ]; then
        /nix/nix-installer uninstall --no-confirm || log "WARNING: Nix uninstall had issues"
    fi
    rm -f /usr/local/bin/nixmanager
    rm -rf "$USER_HOME/.config/nixpkgs_fedora"
    
    log_step "3/6: Disabling services..."
    systemctl disable --now tailscaled libvirtd snapd.socket 2>/dev/null || true
    rm -f /snap 2>/dev/null || true
    
    log_step "4/6: Removing Flatpaks..."
    flatpak uninstall -y "${FLATPAKS[@]}" 2>/dev/null || log "WARNING: Some flatpaks may not have uninstalled"
    flatpak uninstall --unused -y 2>/dev/null || true
    
    log_step "5/6: Removing DNF packages..."
    dnf5 remove -y "${DNF_PACKAGES[@]}" 2>/dev/null || log "WARNING: Some packages may not have uninstalled"
    
    log_step "6/6: Removing repositories..."
    dnf5 remove -y terra-release rpmfusion-free-release rpmfusion-nonfree-release 2>/dev/null || true
    rm -f /usr/local/bin/tolaria-update
    rm -rf /usr/share/tolaria
    
    log_section "PURGE COMPLETE"
    log "System reboot is recommended. Run: sudo reboot"
    exit 0
}

# ==========================================
# INSTALLATION PHASE: BOOTSTRAP
# ==========================================

bootstrap_core_dependencies() {
    log_section "PHASE 1: Bootstrap Core Dependencies"
    
    log_step "Installing core utilities and dnf5..."
    dnf install -y \
        dnf5 dnf5-plugins git curl wget zsh tar unzip util-linux sudo || {
        log "ERROR: Failed to bootstrap core utilities"
        exit 1
    }
}

# ==========================================
# INSTALLATION PHASE: REPOSITORIES
# ==========================================

configure_repositories() {
    log_section "PHASE 2: Configure Repositories"
    
    log_step "Installing RPMFusion repositories..."
    dnf5 install -y --skip-broken \
        "$RPMFUSION_FREE_URL" \
        "$RPMFUSION_NONFREE_URL" || {
        log "ERROR: Failed to install RPMFusion repositories"
        exit 1
    }
    
    log_step "Installing Terra repository (Fyra Labs)..."
    dnf5 install -y --nogpgcheck --repofrompath "terra,$TERRA_REPO_URL" terra-release || {
        log "ERROR: Failed to install Terra repository"
        exit 1
    }
}

# ==========================================
# INSTALLATION PHASE: KDE DESKTOP
# ==========================================

install_kde_environment() {
    log_section "PHASE 3: Install KDE Desktop Environment"
    
    log_step "Installing KDE groups..."
    dnf5 group install --skip-broken -y "kde-desktop" "kde-apps" "kde-media" || {
        log "ERROR: Failed to install KDE groups"
        exit 1
    }
    
    log_step "Removing Firefox (KDE ships with alternatives)..."
    dnf5 remove -y firefox 2>/dev/null || true
}

# ==========================================
# INSTALLATION PHASE: DNF PACKAGES
# ==========================================

install_dnf_packages() {
    log_section "PHASE 4: Install DNF Packages"
    
    log_step "Upgrading system packages..."
    dnf5 upgrade -y --refresh || log "WARNING: System upgrade had issues"
    
    log_step "Installing workstation packages (${#DNF_PACKAGES[@]} packages)..."
    dnf5 install -y --skip-broken "${DNF_PACKAGES[@]}" || {
        log "WARNING: Some packages failed to install, retrying missing packages..."
        
        local missing=()
        for pkg in "${DNF_PACKAGES[@]}"; do
            if ! dnf5 list installed "$pkg" &>/dev/null; then
                missing+=("$pkg")
            fi
        done
        
        if [ ${#missing[@]} -gt 0 ]; then
            log "Retrying ${#missing[@]} missing packages..."
            dnf5 install -y --skip-broken "${missing[@]}" || log "WARNING: Some packages still failed"
        fi
    }
}

# ==========================================
# INSTALLATION PHASE: TOLARIA
# ==========================================

install_tolaria() {
    log_section "PHASE 5: Install Tolaria (Desktop Application Manager)"
    
    local work_dir="/tmp/tolaria_install_$$"
    local deb_url="${TOLARIA_RELEASE_URL}/Tolaria_${TOLARIA_VER}_amd64.deb"
    local tgz_file="tolaria-${TOLARIA_VER}.tgz"
    
    mkdir -p "$work_dir"
    
    {
        cd "$work_dir" || exit 1
        
        log_step "Downloading Tolaria ${TOLARIA_VER}..."
        if ! wget -q "$deb_url" -O "input.deb"; then
            log "ERROR: Failed to download Tolaria"
            exit 1
        fi
        
        log_step "Converting DEB to TGZ using alien..."
        if ! alien -tvc "input.deb" &>/dev/null; then
            log "ERROR: alien conversion failed"
            exit 1
        fi
        
        log_step "Extracting and installing..."
        mkdir -p contents
        if ! tar -xf "$tgz_file" -C contents/ --strip-components=1; then
            log "ERROR: Failed to extract tarball"
            exit 1
        fi
        
        rsync -avz contents/usr/ /usr/ || {
            log "ERROR: Failed to copy files"
            exit 1
        }
        
        # Fix desktop file categories
        local desktop_file="/usr/share/applications/Tolaria.desktop"
        if [ -f "$desktop_file" ]; then
            sed -i 's/^Categories=.*/Categories=Office;Utility;/' "$desktop_file"
            update-desktop-database /usr/share/applications 2>/dev/null || true
        fi
    } || {
        log "ERROR: Tolaria installation failed"
        rm -rf "$work_dir"
        exit 1
    }
    
    log "✓ Tolaria installed successfully"
    rm -rf "$work_dir"
    
    log_step "Downloading tolaria-update helper..."
    if ! curl -sL "$TOLARIA_UPDATER_URL" -o /usr/local/bin/tolaria-update; then
        log "ERROR: Failed to download tolaria-update helper"
        exit 1
    fi
    chmod +x /usr/local/bin/tolaria-update
    
    log_step "Running tolaria-update as user..."
    run_as_user "/usr/local/bin/tolaria-update" || log "WARNING: tolaria-update had issues"
}

# ==========================================
# INSTALLATION PHASE: SERVICES
# ==========================================

enable_services() {
    log_section "PHASE 6: Enable System Services"
    
    log_step "Enabling Tailscale..."
    systemctl enable --now tailscaled || log "WARNING: Failed to enable tailscaled"
    
    log_step "Enabling libvirt (KVM)..."
    systemctl enable --now libvirtd || log "WARNING: Failed to enable libvirtd"
    
    log_step "Enabling snapd..."
    systemctl enable --now snapd.socket || log "WARNING: Failed to enable snapd.socket"
    
    # Create symlink for snap compatibility
    mkdir -p /var/lib/snapd/snap
    ln -s /var/lib/snapd/snap /snap 2>/dev/null || true
}

# ==========================================
# INSTALLATION PHASE: FLATPAK
# ==========================================

setup_flatpak() {
    log_section "PHASE 7: Setup Flatpak"
    
    log_step "Adding Flathub repository..."
    flatpak remote-add --if-not-exists flathub "$FLATHUB_URL" || {
        log "WARNING: Flathub repository may already exist"
    }
    
    log_step "Installing Flatpak applications (${#FLATPAKS[@]} apps)..."
    flatpak install -y flathub "${FLATPAKS[@]}" 2>&1 | grep -E "^(Installing|Error)" || true
    
    # Retry any missing flatpaks
    local missing_flatpaks=()
    for fpkg in "${FLATPAKS[@]}"; do
        if ! flatpak info "$fpkg" &>/dev/null; then
            missing_flatpaks+=("$fpkg")
        fi
    done
    
    if [ ${#missing_flatpaks[@]} -gt 0 ]; then
        log "Retrying ${#missing_flatpaks[@]} missing Flatpaks..."
        flatpak install -y flathub "${missing_flatpaks[@]}" 2>&1 | grep -E "^(Installing|Error)" || true
    fi
}

# ==========================================
# INSTALLATION PHASE: NIX
# ==========================================

setup_nix() {
    log_section "PHASE 8: Setup Determinate Nix & nixpkgs_fedora"
    
    log_step "Installing Determinate Nix..."
    if ! curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm; then
        log "ERROR: Failed to install Nix"
        exit 1
    fi
    
    log_step "Creating nixpkgs_fedora flake configuration..."
    run_as_user "mkdir -p '$USER_HOME/.config/nixpkgs_fedora'"
    
    run_as_user "tee '$USER_HOME/.config/nixpkgs_fedora/flake.nix' > /dev/null" << 'EOF'
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
    
    log_step "Configuring Plasma XDG environment..."
    run_as_user "mkdir -p '$USER_HOME/.config/environment.d'"
    
    run_as_user "tee '$USER_HOME/.config/environment.d/10-nix.conf' > /dev/null" << 'EOF'
XDG_DATA_DIRS=$HOME/.nix-profile/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}
EOF
    
    log_step "Installing nixmanager CLI tool..."
    install_nixmanager
}

install_nixmanager() {
    rm -f /usr/local/bin/nixmanager
    
    cat > /tmp/nixmanager.sh << 'NIXMANAGER_EOF'
#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_NAME=$(basename "$0")

usage() {
    echo -e "${BLUE}Usage: $SCRIPT_NAME <command> [options]${NC}"
    echo ""
    echo "Commands:"
    echo "  install <package>    Install a package from nixpkgs"
    echo "  remove <package>     Remove an installed package"
    echo "  list                 List installed packages"
    echo "  search <query>       Search for packages"
    echo "  upgrade              Upgrade all packages"
}

check_nix() {
    if ! command -v nix &> /dev/null; then
        echo -e "${RED}Error: Nix is not installed${NC}" >&2
        exit 1
    fi
}

update_shortcuts() {
    echo -e "${BLUE}Syncing applications...${NC}"
    local local_apps="$HOME/.local/share/applications"
    mkdir -p "$local_apps"
    find "$local_apps" -name "nixmanager-*.desktop" -delete 2>/dev/null || true
    
    if [ -d "$HOME/.nix-profile/share/applications" ]; then
        for desktop in "$HOME/.nix-profile/share/applications"/*.desktop; do
            [ -e "$desktop" ] || continue
            ln -sf "$(readlink -f "$desktop")" "$local_apps/nixmanager-$(basename "$desktop")"
        done
    fi
    update-desktop-database "$local_apps" 2>/dev/null || true
}

main() {
    check_nix
    case "${1:-help}" in
        install) nix profile add "$HOME/.config/nixpkgs_fedora#$2" && update_shortcuts ;;
        remove) nix profile remove "$2" && update_shortcuts ;;
        list) nix profile list ;;
        search) NIXPKGS_ALLOW_UNFREE=1 nix search nixpkgs "$2" ;;
        upgrade) nix profile upgrade && update_shortcuts ;;
        *) usage ;;
    esac
}
main "$@"
NIXMANAGER_EOF
    
    mv -f /tmp/nixmanager.sh /usr/local/bin/nixmanager
    chmod +x /usr/local/bin/nixmanager
    log "✓ nixmanager installed to /usr/local/bin/nixmanager"
}

# ==========================================
# INSTALLATION PHASE: ZSH SETUP
# ==========================================

setup_zsh() {
    log_section "PHASE 9: Configure Zsh Shell"
    
    log_step "Installing Oh My Zsh..."
    if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
        run_as_user "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended" || {
            log "WARNING: Oh My Zsh installation may have had issues"
        }
    else
        log "✓ Oh My Zsh already installed"
    fi
    
    log_step "Installing Zsh plugins..."
    local zsh_custom="$USER_HOME/.oh-my-zsh/custom"
    
    for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
        if [ ! -d "$zsh_custom/plugins/$plugin" ]; then
            run_as_user "git clone https://github.com/zsh-users/$plugin '$zsh_custom/plugins/$plugin'" || {
                log "WARNING: Failed to install $plugin"
            }
        fi
    done
    
    log_step "Creating .zshrc configuration..."
    run_as_user "tee '$USER_HOME/.zshrc' > /dev/null" << 'ZSH_EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="terminalparty"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

if [ -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
    . "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
fi

# System environment
export LANG=en_US.UTF-8
export EDITOR="nano"
export VISUAL="nano"
export PATH="$PATH:$HOME/.local/bin"

# Comprehensive update alias
alias update="sudo dnf upgrade -y; sudo flatpak update -y; sudo snap refresh"
alias tolaria-update="echo 'updating Tolaria...'; sudo tolaria-update"

# Starship prompt (optional)
if command -v starship &> /dev/null; then
    eval "$(starship init zsh)"
fi
ZSH_EOF
    
    chown "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/.zshrc"
    log_step "Changing default shell to Zsh..."
    usermod -s /usr/bin/zsh "$ACTUAL_USER" || {
        log "WARNING: Failed to change shell"
    }
}

# ==========================================
# INSTALLATION PHASE: SSH HELPER
# ==========================================

create_ssh_helper() {
    log_section "PHASE 10: Generate SSH Restoration Helper"
    
    log_step "Creating restore-ssh.sh helper script..."
    cat > "$USER_HOME/restore-ssh.sh" << SSH_HELPER_EOF
#!/bin/bash
# SSH Key Restoration Helper
# Restores SSH keys from remote encrypted backup via Tailscale

REMOTE_PATH="${SSH_REMOTE_PATH}"
LOCAL_TMP="/tmp/ssh-keys.tar.gpg"

echo "--- SSH Key Restoration via Rsync ---"
echo "This script will restore SSH keys from: \$REMOTE_PATH"
echo "Ensure Tailscale is connected and the server is reachable."
read -p "Continue? [y/N]: " CONFIRM
[[ ! "\$CONFIRM" =~ ^[Yy]\$ ]] && exit 1

# Pull the encrypted file
echo "Pulling encrypted keys from server..."
if ! rsync -avzP "\$REMOTE_PATH" "\$LOCAL_TMP"; then
    echo "⚠️  Failed to pull file. Verify:"
    echo "  1. Tailscale is connected"
    echo "  2. Remote path is correct: \$REMOTE_PATH"
    echo "  3. You have read permissions"
    exit 1
fi

if [ -f "\$LOCAL_TMP" ]; then
    mkdir -p "\$HOME/.ssh"
    chmod 700 "\$HOME/.ssh"

    echo "Decrypting and extracting..."
    if ! gpg --decrypt "\$LOCAL_TMP" | tar -xvf - --strip-components=1 -C "\$HOME/.ssh"; then
        echo "⚠️  Decryption/extraction failed. Verify:"
        echo "  1. GPG is installed and configured"
        echo "  2. Archive is valid"
        exit 1
    fi

    echo "Hardening permissions..."
    # Private keys: files without extensions (excluding known_hosts)
    find "\$HOME/.ssh" -type f ! -name "*.*" ! -name "known_hosts*" -exec chmod 600 {} +
    
    # Public keys
    chmod 644 "\$HOME/.ssh"/*.pub 2>/dev/null || true
    
    # Known hosts
    chmod 600 "\$HOME/.ssh/known_hosts"* 2>/dev/null || true
    
    echo "✓ SSH keys restored successfully"
    rm "\$LOCAL_TMP"
    echo "✓ Temporary file cleaned up"
else
    echo "⚠️  Failed to retrieve file from server"
    exit 1
fi
SSH_HELPER_EOF
    
    chown "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/restore-ssh.sh"
    chmod +x "$USER_HOME/restore-ssh.sh"
    log "✓ restore-ssh.sh created in $USER_HOME/"
}

# ==========================================
# VERIFICATION & AUDIT
# ==========================================

print_check() {
    if [ "$1" -eq 0 ]; then
        echo -e "  [\033[0;32m ✓ \033[0m] $2"
    else
        echo -e "  [\033[0;31m ✗ \033[0m] $2"
    fi
}

verify_installation() {
    log_section "PHASE 11: Verification & Audit"
    
    echo ""
    
    # Check DNF packages
    log_step "Checking DNF packages..."
    if dnf5 list installed "${DNF_PACKAGES[0]}" &>/dev/null; then
        print_check 0 "DNF Packages installed"
    else
        print_check 1 "Some DNF packages missing"
    fi
    
    # Check Tolaria
    if [ -x "/usr/local/bin/tolaria-update" ]; then
        print_check 0 "Tolaria Update Helper"
    else
        print_check 1 "Tolaria Update Helper"
    fi
    
    # Check nixmanager
    if [ -x "/usr/local/bin/nixmanager" ]; then
        print_check 0 "nixmanager CLI tool"
    else
        print_check 1 "nixmanager CLI tool"
    fi
    
    # Check Nix installation
    if [ -d "/nix" ]; then
        print_check 0 "Nix package manager"
    else
        print_check 1 "Nix package manager"
    fi
    
    # Check services
    if systemctl is-active --quiet tailscaled; then
        print_check 0 "Tailscale Service"
    else
        print_check 1 "Tailscale Service"
    fi
    
    if systemctl is-active --quiet snapd.socket; then
        print_check 0 "Snapd Socket"
    else
        print_check 1 "Snapd Socket"
    fi
    
    # Check SSH helper
    if [ -x "$USER_HOME/restore-ssh.sh" ]; then
        print_check 0 "SSH Restoration Script"
    else
        print_check 1 "SSH Restoration Script"
    fi
    
    echo ""
}

# ==========================================
# MAIN EXECUTION
# ==========================================

parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -v|--version)
                if [ -z "${2:-}" ]; then
                    log "ERROR: --version requires an argument"
                    exit 1
                fi
                FEDORA_VERSION="$2"
                shift 2
                ;;
            --remove)
                PURGE_MODE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR: Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    log_section "FEDORA POST-INSTALLER (Refactored)"
    log "Starting at $(date)"
    log "Fedora Version: $FEDORA_VERSION"
    log "Installation Log: $LOG_FILE"
    
    parse_arguments "$@"
    check_prerequisites
    get_user_info
    
    if [ "$PURGE_MODE" = true ]; then
        purge_installation
    fi
    
    # Installation phases
    bootstrap_core_dependencies
    configure_repositories
    install_kde_environment
    install_dnf_packages
    install_tolaria
    enable_services
    setup_flatpak
    setup_nix
    setup_zsh
    create_ssh_helper
    verify_installation
    
    # Final summary
    log_section "INSTALLATION COMPLETE ✓"
    log "Setup completed successfully at $(date)"
    log "Installation log saved to: $LOG_FILE"
    
    cat << EOF

NEXT STEPS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. REBOOT YOUR SYSTEM (Highly Recommended)
   \$ sudo reboot

2. After reboot, connect to Tailscale:
   \$ tailscale up

3. Restore SSH keys from remote backup:
   \$ ~/restore-ssh.sh

4. Verify your setup:
   \$ tolaria-update           # Check Tolaria updates
   \$ nixmanager list          # List installed nix packages
   \$ update                   # Run all system updates

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

For more information, see: $LOG_FILE

EOF
}

# Execute main function with all arguments
main "$@"
