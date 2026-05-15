#!/bin/bash

# ==========================================
# GLOBAL CONFIGURATION & PACKAGE LISTS
# ==========================================
FEDORA_VERSION=$(rpm -E %fedora)
PURGE_MODE=false
INSTALL_LLAMA=true

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
    filelight ark okular materia* webkit2gtk4.1-devel openssl-devel curl wget file
    libappindicator-gtk3-devel librsvg2-devel
)

DEV_PKGS=(
    vulkan-devel glslc glslang python-devel @development-tools 
    cmake git-lfs curlpp-devel gcc-c++ spirv-headers-devel spirv-tools-devel
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
        --remove)     PURGE_MODE=true ;;
        --no-llama)   INSTALL_LLAMA=false ;;
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

    echo "6/6 Removing repositories and Tolaria helpers..."
    dnf5 remove -y terra-release rpmfusion-free-release rpmfusion-nonfree-release 2>/dev/null
    rm -f /etc/yum.repos.d/terra.repo
    rm -f /usr/local/bin/tolaria-update
    rm -rf /usr/share/tolaria

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
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"

# Write a proper .repo file for Terra instead of using --repofrompath,
# which causes "Id is present more than once" errors on re-runs or when
# terra-release is already partially installed.
TERRA_REPO_FILE="/etc/yum.repos.d/terra.repo"
if [ ! -f "$TERRA_REPO_FILE" ]; then
    cat > "$TERRA_REPO_FILE" << REPO_EOF
[terra]
name=Terra - Fedora \$releasever
baseurl=https://repos.fyralabs.com/terra${FEDORA_VERSION}/
enabled=1
gpgcheck=1
gpgkey=https://repos.fyralabs.com/terra${FEDORA_VERSION}/key.gpg
REPO_EOF
fi
dnf5 install -y --skip-broken terra-release

# 2. KDE Group Installs
echo "Installing KDE Environment Groups..."
dnf5 group install --skip-broken -y "kde-desktop" "kde-apps" "kde-media"
dnf5 -y remove firefox

# 3. Comprehensive DNF Package Install
echo "Installing workstation packages..."
dnf5 upgrade -y --refresh
dnf5 install -y --skip-broken "${DNF_PACKAGES[@]}"
dnf5 install -y --skip-broken "${DEV_PKGS[@]}"

# ==========================================
# 3.1 Tolaria & Auto-Updater Tool
# ==========================================
echo "Installing Tolaria and Update Helper..."

UPDATER_URL="https://raw.githubusercontent.com/soltros/fedora-post-installer/main/helpers/tolaria-update"
curl -sL "$UPDATER_URL" -o /usr/local/bin/tolaria-update
chmod +x /usr/local/bin/tolaria-update

sudo -H -u "$ACTUAL_USER" /usr/local/bin/tolaria-update

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
# 3.2 LlamaCPP Vulkan compilation
# ==========================================
if [ "$INSTALL_LLAMA" = true ]; then
    echo "--- Building LlamaCPP with Vulkan support ---"
    
    LLAMA_DIR="$USER_HOME/llama.cpp"

    if [ ! -d "$LLAMA_DIR" ]; then
        sudo -H -u "$ACTUAL_USER" git clone https://github.com/ggerganov/llama.cpp "$LLAMA_DIR"
    else
        echo "Llama.cpp directory exists, pulling latest master..."
        # Running git pull as the user in the specific directory
        sudo -H -u "$ACTUAL_USER" bash -c "cd $LLAMA_DIR && git pull origin master"
    fi

    # Navigate to the directory for the build steps
    cd "$LLAMA_DIR" || exit

    echo "Configuring with CMake..."
    sudo -H -u "$ACTUAL_USER" cmake -B build -DGGML_VULKAN=1
    
    echo "Compiling (using all available cores)..."
    sudo -H -u "$ACTUAL_USER" cmake --build build --config Release -j$(nproc)
    
    # Check if build succeeded
    if [ -f "$LLAMA_DIR/build/bin/llama-cli" ]; then
        echo "✓ Llama.cpp built successfully."
    else
        echo "⚠️ Llama.cpp build failed."
    fi
else
    echo "--- Skipping LlamaCPP build (--no-llama detected) ---"
fi

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

sudo -H -u "$ACTUAL_USER" mkdir -p "$USER_HOME/.config/environment.d"
sudo -H -u "$ACTUAL_USER" tee "$USER_HOME/.config/environment.d/10-nix.conf" > /dev/null << 'EOF'
XDG_DATA_DIRS=$HOME/.nix-profile/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}
EOF

rm -f /usr/local/bin/nixmanager

cat << 'EOF' > /tmp/nixmanager.sh
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
EOF

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

sudo -H -u "$ACTUAL_USER" tee "$USER_HOME/.zshrc" > /dev/null << 'ZSH_EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="terminalparty"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

if [ -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
    . "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
fi

alias update="sudo dnf upgrade -y; sudo flatpak update -y; sudo snap refresh"
alias tolaria-update="echo 'updating Tolaria...'; sudo tolaria-update"
export LANG=en_US.UTF-8
export EDITOR="nano"
export VISUAL="nano"
export PATH="$PATH:$HOME/.local/bin"

if command -v starship &> /dev/null; then
    eval "$(starship init zsh)"
fi
ZSH_EOF

chown "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/.zshrc"
usermod -s /usr/bin/zsh "$ACTUAL_USER"

# ==========================================
# GENERATE SSH RESTORATION HELPER
# ==========================================
echo "Generating ~/restore-ssh.sh..."
cat << 'EOF' > "$USER_HOME/restore-ssh.sh"
#!/bin/bash
REMOTE_PATH="derrik@ubuntu-server:/mnt/hdd4/files/ssh-keys.tar.gpg"
LOCAL_TMP="/tmp/ssh-keys.tar.gpg"

echo "--- SSH Key Restoration via Rsync ---"
echo "Ensure Tailscale is connected before proceeding."
read -p "Continue? [y/N]: " CONFIRM
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && exit 1

echo "Pulling encrypted keys from server..."
rsync -avzP "$REMOTE_PATH" "$LOCAL_TMP"

if [ -f "$LOCAL_TMP" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    echo "Decrypting and extracting (strip-components=1)..."
    gpg --decrypt "$LOCAL_TMP" | tar -xvf - --strip-components=1 -C "$HOME/.ssh"

    echo "Hardening permissions..."
    find "$HOME/.ssh" -type f ! -name "*.*" ! -name "known_hosts*" -exec chmod 600 {} +
    chmod 644 "$HOME/.ssh"/*.pub 2>/dev/null || true
    chmod 600 "$HOME/.ssh/known_hosts"* 2>/dev/null || true
    
    echo "✓ SSH keys restored. Cleaning up..."
    rm "$LOCAL_TMP"
else
    echo "⚠️ Failed to pull file. Check your Tailscale connection."
fi
EOF

chown "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/restore-ssh.sh"
chmod +x "$USER_HOME/restore-ssh.sh"

# ==========================================
# 9. FINAL SYSTEM AUDIT CHECKLIST
# ==========================================
echo ""
echo "=========================================================="
echo "                FINAL SYSTEM AUDIT CHECKLIST                "
echo "=========================================================="

print_check() {
    if [ "$1" -eq 0 ]; then
        echo -e "[\033[0;32m ✓ \033[0m] $2"
    else
        echo -e "[\033[0;31m ✗ \033[0m] $2"
    fi
}

dnf5 list installed "${DNF_PACKAGES[@]}" &>/dev/null && print_check 0 "DNF Packages" || print_check 1 "DNF Packages"
[ -x "/usr/local/bin/tolaria-update" ] && print_check 0 "Tolaria Update Helper" || print_check 1 "Tolaria Update Helper"
[ -x "/usr/local/bin/nixmanager" ] && print_check 0 "nixmanager CLI tool" || print_check 1 "nixmanager CLI tool"
systemctl is-active --quiet tailscaled && print_check 0 "Tailscale Service" || print_check 1 "Tailscale Service"
systemctl is-active --quiet snapd.socket && print_check 0 "Snapd Socket" || print_check 1 "Snapd Socket"
[ -x "$USER_HOME/restore-ssh.sh" ] && print_check 0 "SSH Restoration Script Created" || print_check 1 "SSH Restoration Script Missing"

# Conditional Llama Check
if [ "$INSTALL_LLAMA" = true ]; then
    [ -f "$USER_HOME/llama.cpp/build/bin/llama-cli" ] && print_check 0 "LlamaCPP Vulkan Build" || print_check 1 "LlamaCPP Vulkan Build"
fi

echo "=========================================================="
echo -e "\033[0;32mSetup completed! A system reboot is highly recommended.\033[0m"
echo ""
echo "NEXT STEPS:"
echo "1. Reboot and run 'tailscale up'."
echo "2. Run '~/restore-ssh.sh' to pull and install your keys."
echo "=========================================================="
