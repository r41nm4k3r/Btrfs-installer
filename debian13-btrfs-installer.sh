#!/usr/bin/env bash
set -Eeuo pipefail

# Debian 13 + Btrfs interactive installer
# Inspired by: https://sysguides.com/install-debian-13-with-btrfs

SCRIPT_VERSION="1.0.0"
LOG_FILE="./debian13-btrfs-installer.log"
DRY_RUN=0
DEBUG=0

# ---------- UI ----------
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; BOLD=''; NC=''
fi

trap 'echo -e "${RED}\n[ERROR] Installer failed at line $LINENO. See: $LOG_FILE${NC}" >&2' ERR

log() { echo "[$(date +'%F %T')] $*" >> "$LOG_FILE"; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; log "INFO: $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; log "OK: $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; log "WARN: $*"; }
err() { echo -e "${RED}[ERR]${NC} $*"; log "ERR: $*"; }

banner() {
  clear || true
  cat <<'BANNER'
╔════════════════════════════════════════════════════════════════════╗
║       Debian 13 (Trixie) + Btrfs Snapshot Installer Wizard        ║
║         UEFI • Subvolumes • Snapper • GRUB-Btrfs • Swap           ║
╚════════════════════════════════════════════════════════════════════╝
BANNER
  echo -e "${MAGENTA}Version:${NC} ${SCRIPT_VERSION}"
  echo
}

pause() { read -r -p "Press Enter to continue..." _; }

ask() {
  local prompt="$1" default="${2:-}" var
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " var
    printf '%s' "${var:-$default}"
  else
    read -r -p "$prompt: " var
    printf '%s' "$var"
  fi
}

ask_secret() {
  local prompt="$1" v1 v2
  while true; do
    read -r -s -p "$prompt: " v1; echo
    read -r -s -p "Confirm $prompt: " v2; echo
    [[ "$v1" == "$v2" ]] && { printf '%s' "$v1"; return; }
    warn "Values did not match. Try again."
  done
}

run_cmd() {
  local cmd="$*"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo -e "${YELLOW}[DRY]${NC} $cmd"
    log "DRY: $cmd"
  else
    echo -e "${BLUE}[RUN]${NC} $cmd"
    log "RUN: $cmd"
    if [[ "$DEBUG" -eq 1 ]]; then
      eval "$cmd" 2>&1 | tee -a "$LOG_FILE"
    else
      eval "$cmd" >> "$LOG_FILE" 2>&1
    fi
  fi
}

confirm() {
  local q="$1" ans
  read -r -p "$q [y/N]: " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Run as root (e.g., sudo bash $0)"
    exit 1
  fi
}

require_uefi() {
  [[ -d /sys/firmware/efi ]] || {
    err "UEFI mode required. Boot the live ISO in UEFI mode."
    exit 1
  }
}

check_tools() {
  local required=(lsblk blkid sed awk grep chroot mount umount btrfs openssl)
  for t in "${required[@]}"; do
    command -v "$t" >/dev/null || { err "Missing required tool: $t"; exit 1; }
  done
}

select_disk() {
  echo -e "${BOLD}Detected block devices:${NC}"
  lsblk -d -e7 -o NAME,SIZE,MODEL,TRAN,TYPE | sed '1!{/rom/d}'
  echo
  while true; do
    DISK=$(ask "Enter target disk path (example: /dev/sda or /dev/nvme0n1)")
    [[ -b "$DISK" ]] || { warn "Not a valid block device."; continue; }
    if mount | grep -q "^$DISK"; then
      warn "$DISK appears mounted. Unmount first and retry."
      continue
    fi
    break
  done

  if [[ "$DISK" =~ nvme|mmcblk ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
  else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
  fi
}

choose_desktop() {
  echo "Choose desktop profile:"
  echo "  1) GNOME (gdm3)"
  echo "  2) KDE Plasma (sddm)"
  echo "  3) XFCE (lightdm)"
  while true; do
    case "$(ask 'Selection' '1')" in
      1) DM_SUBVOL='@gdm3'; DM_PATH='/var/lib/gdm3'; DESKTOP_PKG='task-gnome-desktop'; break ;;
      2) DM_SUBVOL='@sddm'; DM_PATH='/var/lib/sddm'; DESKTOP_PKG='task-kde-desktop'; break ;;
      3) DM_SUBVOL='@lightdm'; DM_PATH='/var/lib/lightdm'; DESKTOP_PKG='task-xfce-desktop'; break ;;
      *) warn "Choose 1, 2, or 3" ;;
    esac
  done
}

collect_inputs() {
  HOSTNAME=$(ask "Hostname" "debian")
  USERNAME=$(ask "New username" "user")
  FULLNAME=$(ask "Full name" "$USERNAME")
  TIMEZONE=$(ask "Timezone" "Europe/Athens")
  LOCALE=$(ask "Locale" "en_US.UTF-8")
  SWAP_GB=$(ask "Swap size in GiB" "8")
  BTRFS_LABEL=$(ask "Btrfs label" "DEBIAN")

  ROOT_PASSWORD=$(ask_secret "Set ROOT password")
  USER_PASSWORD=$(ask_secret "Set USER password for ${USERNAME}")

  if confirm "Enable DRY-RUN mode (print commands, no changes)?"; then
    DRY_RUN=1
  fi

  if confirm "Enable DEBUG mode (show command output)?"; then
    DEBUG=1
  fi
}

final_confirmation() {
  echo
  echo -e "${RED}${BOLD}DESTRUCTIVE ACTION WARNING${NC}"
  echo "Disk : $DISK"
  echo "Will : wipe disk, repartition, format, install Debian"
  echo
  local phrase="ERASE ${DISK}"
  local typed
  read -r -p "Type '${phrase}' to continue: " typed
  [[ "$typed" == "$phrase" ]] || { err "Confirmation phrase mismatch. Aborted."; exit 1; }
}

prep_packages() {
  info "Installing live-environment prerequisites..."
  run_cmd "apt update"
  run_cmd "apt install -y gdisk debootstrap btrfs-progs dosfstools efibootmgr git make curl locales"
}

partition_disk() {
  info "Partitioning and formatting target disk..."
  run_cmd "sgdisk -Z '$DISK'"
  run_cmd "sgdisk -og '$DISK'"
  run_cmd "sgdisk -n 1::+1G -t 1:ef00 -c 1:'ESP' '$DISK'"
  run_cmd "sgdisk -n 2:: -t 2:8300 -c 2:'LINUX' '$DISK'"
  run_cmd "mkfs.fat -F32 -n EFI '$EFI_PART'"
  run_cmd "mkfs.btrfs -f -L '$BTRFS_LABEL' '$ROOT_PART'"
  run_cmd "lsblk -po name,size,fstype,label,uuid '$DISK'"
}

create_subvolumes() {
  info "Creating Btrfs subvolumes..."
  run_cmd "mount '$ROOT_PART' /mnt"
  run_cmd "btrfs subvolume create /mnt/@"
  run_cmd "btrfs subvolume create /mnt/@home"
  run_cmd "btrfs subvolume create /mnt/@opt"
  run_cmd "btrfs subvolume create /mnt/@cache"
  run_cmd "btrfs subvolume create /mnt/$DM_SUBVOL"
  run_cmd "btrfs subvolume create /mnt/@libvirt"
  run_cmd "btrfs subvolume create /mnt/@log"
  run_cmd "btrfs subvolume create /mnt/@spool"
  run_cmd "btrfs subvolume create /mnt/@tmp"
  run_cmd "btrfs subvolume create /mnt/@swap"
  run_cmd "umount /mnt"
}

mount_layout() {
  info "Mounting Btrfs layout to /mnt..."
  BTRFS_OPTS='defaults,noatime,space_cache=v2,compress=zstd:1'
  run_cmd "mount -o ${BTRFS_OPTS},subvol=@ '$ROOT_PART' /mnt"
  run_cmd "mkdir -p /mnt/home /mnt/opt /mnt/boot/efi /mnt/var/cache '$DM_PATH' /mnt/var/lib/libvirt /mnt/var/log /mnt/var/spool /mnt/var/tmp /mnt/var/swap"
  run_cmd "mount -o ${BTRFS_OPTS},subvol=@home '$ROOT_PART' /mnt/home"
  run_cmd "mount -o ${BTRFS_OPTS},subvol=@opt '$ROOT_PART' /mnt/opt"
  run_cmd "mount -o ${BTRFS_OPTS},subvol=@cache '$ROOT_PART' /mnt/var/cache"
  run_cmd "mount -o ${BTRFS_OPTS},subvol=${DM_SUBVOL} '$ROOT_PART' '$DM_PATH'"
  run_cmd "mount -o ${BTRFS_OPTS},subvol=@libvirt '$ROOT_PART' /mnt/var/lib/libvirt"
  run_cmd "mount -o ${BTRFS_OPTS},subvol=@log '$ROOT_PART' /mnt/var/log"
  run_cmd "mount -o ${BTRFS_OPTS},subvol=@spool '$ROOT_PART' /mnt/var/spool"
  run_cmd "mount -o ${BTRFS_OPTS},subvol=@tmp '$ROOT_PART' /mnt/var/tmp"
  run_cmd "mount -o defaults,noatime,subvol=@swap '$ROOT_PART' /mnt/var/swap"
  run_cmd "mount '$EFI_PART' /mnt/boot/efi"
  run_cmd "lsblk -po name,size,fstype,uuid,mountpoints '$DISK'"
}

generate_fstab() {
  info "Generating /etc/fstab..."
  local btrfs_uuid efi_uuid
  btrfs_uuid=$(blkid -s UUID -o value "$ROOT_PART")
  efi_uuid=$(blkid -s UUID -o value "$EFI_PART")

  cat > /mnt/etc/fstab <<FSTAB
UUID=$btrfs_uuid /                btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@ 0 0
UUID=$btrfs_uuid /home            btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@home 0 0
UUID=$btrfs_uuid /opt             btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@opt 0 0
UUID=$btrfs_uuid /var/cache       btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@cache 0 0
UUID=$btrfs_uuid $DM_PATH         btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=$DM_SUBVOL 0 0
UUID=$btrfs_uuid /var/lib/libvirt btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@libvirt 0 0
UUID=$btrfs_uuid /var/log         btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@log 0 0
UUID=$btrfs_uuid /var/spool       btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@spool 0 0
UUID=$btrfs_uuid /var/tmp         btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@tmp 0 0
UUID=$btrfs_uuid /var/swap        btrfs defaults,noatime,subvol=@swap 0 0
UUID=$efi_uuid   /boot/efi        vfat  defaults,noatime 0 2
FSTAB

  cat /mnt/etc/fstab >> "$LOG_FILE"
  ok "fstab written."
}

bootstrap_and_chroot() {
  info "Bootstrapping Debian 13 (trixie)..."
  run_cmd "debootstrap --arch=amd64 trixie /mnt http://deb.debian.org/debian"

  info "Binding virtual filesystems..."
  for d in dev proc sys run; do
    run_cmd "mount --rbind /$d /mnt/$d"
    run_cmd "mount --make-rslave /mnt/$d"
  done
  run_cmd "mkdir -p /mnt/sys/firmware/efi/efivars"
  run_cmd "mount -t efivarfs efivarfs /mnt/sys/firmware/efi/efivars"
}

write_chroot_script() {
  info "Generating in-chroot configuration script..."

  local root_hash user_hash
  root_hash=$(openssl passwd -6 "$ROOT_PASSWORD")
  user_hash=$(openssl passwd -6 "$USER_PASSWORD")

  cat > /mnt/root/chroot-setup.sh <<CHROOT
#!/usr/bin/env bash
set -Eeuo pipefail

DISK="$DISK"
ROOT_PART="$ROOT_PART"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
FULLNAME="$FULLNAME"
TIMEZONE="$TIMEZONE"
LOCALE="$LOCALE"
SWAP_GB="$SWAP_GB"
DM_PATH="$DM_PATH"
DM_SUBVOL="$DM_SUBVOL"
DESKTOP_PKG="$DESKTOP_PKG"
ROOT_HASH='$root_hash'
USER_HASH='$user_hash'
ROOT_PASSWORD='$ROOT_PASSWORD'
USER_PASSWORD='$USER_PASSWORD'

export DEBIAN_FRONTEND=noninteractive

echo "[CHROOT] Starting setup with hostname: \$HOSTNAME, user: \$USERNAME"

echo "[CHROOT] Hostname and hosts..."
echo "\$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<'EOF'
127.0.0.1 localhost
127.0.1.1 \$HOSTNAME
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

echo "[CHROOT] Setting timezone..."
ln -sf "/usr/share/zoneinfo/\$TIMEZONE" /etc/localtime

echo "[CHROOT] Configuring APT sources..."
cat > /etc/apt/sources.list <<'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
EOF

echo "[CHROOT] Updating package lists..."
apt update

echo "[CHROOT] Installing kernel and base packages..."
apt install -y locales linux-image-amd64 linux-headers-amd64 \\
  firmware-linux firmware-linux-nonfree \\
  grub-efi-amd64 efibootmgr network-manager \\
  btrfs-progs sudo vim bash-completion \\
  openssl cryptsetup initramfs-tools

echo "[CHROOT] Configuring locales..."
sed -i "s/# \$LOCALE UTF-8/\$LOCALE UTF-8/" /etc/locale.gen
locale-gen
echo "LANG=\$LOCALE" > /etc/default/locale
dpkg-reconfigure -f noninteractive locales

echo "[CHROOT] Creating swap file..."
SWAP_SIZE_MB=\$((SWAP_GB * 1024))
truncate -s 0 /var/swap/swapfile
chattr +C /var/swap/swapfile
btrfs property set /var/swap compression none
dd if=/dev/zero of=/var/swap/swapfile bs=1M count="\$SWAP_SIZE_MB" status=progress
chmod 600 /var/swap/swapfile
mkswap -L SWAP /var/swap/swapfile
echo "/var/swap/swapfile none swap defaults 0 0" >> /etc/fstab
swapon /var/swap/swapfile

echo "[CHROOT] Configuring hibernation..."
SWAP_OFFSET=\$(btrfs inspect-internal map-swapfile -r /var/swap/swapfile)
BTRFS_UUID=\$(blkid -s UUID -o value "\$ROOT_PART")
GRUB_CMD="quiet resume=UUID=\$BTRFS_UUID resume_offset=\$SWAP_OFFSET"
sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"\$GRUB_CMD\"|" /etc/default/grub

cat > /etc/initramfs-tools/conf.d/resume <<EOF
RESUME=/var/swap/swapfile
RESUME_OFFSET=\$SWAP_OFFSET
EOF

echo "[CHROOT] Creating user..."
useradd -m -G sudo,adm -s /bin/bash -c "\$FULLNAME" "\$USERNAME"

echo "[CHROOT] Setting passwords..."
echo "DEBUG: ROOT_HASH=\$ROOT_HASH"
echo "DEBUG: USER_HASH=\$USER_HASH"

# Set passwords using chpasswd with explicit encoding
echo "root:\$ROOT_HASH" | chpasswd -e
echo "\$USERNAME:\$USER_HASH" | chpasswd -e

# Alternative method if chpasswd fails
if ! echo "root:\$ROOT_HASH" | chpasswd -e 2>/dev/null; then
  echo "[CHROOT] Using alternative password method for root..."
  printf "root\n\$ROOT_PASSWORD\n\$ROOT_PASSWORD\n" | passwd root
fi

if ! echo "\$USERNAME:\$USER_HASH" | chpasswd -e 2>/dev/null; then
  echo "[CHROOT] Using alternative password method for user..."
  printf "\$USERNAME\n\$USER_PASSWORD\n\$USER_PASSWORD\n" | passwd "\$USERNAME"
fi

# Verify password files
echo "[CHROOT] Verifying password setup..."
grep '^root:' /etc/shadow
grep "^\$USERNAME:" /etc/shadow

echo "[CHROOT] Installing GRUB..."
grub-install \\
  --target=x86_64-efi \\
  --efi-directory=/boot/efi \\
  --bootloader-id=debian \\
  --recheck
update-grub
update-initramfs -u -k all

echo "[CHROOT] Installing desktop environment..."
apt install -y "\$DESKTOP_PKG"

echo "[CHROOT] Enabling services..."
case "\$DESKTOP_PKG" in
  *gnome*) systemctl enable gdm3 ;;
  *kde*) systemctl enable sddm ;;
  *xfce*) systemctl enable lightdm ;;
esac
systemctl enable NetworkManager
systemctl enable ssh

echo "[CHROOT] Creating .mozilla subvolume..."
mkdir -p "/home/\$USERNAME"
btrfs subvolume create "/home/\$USERNAME/.mozilla"
chown "\$USERNAME:\$USERNAME" "/home/\$USERNAME/.mozilla"

echo "[CHROOT] Installing Snapper and GRUB-Btrfs..."
apt install -y snapper btrfs-assistant inotify-tools git make

echo "[CHROOT] Configuring Snapper..."
snapper -c root create-config /
snapper -c home create-config /home
snapper -c root set-config ALLOW_USERS="\$USERNAME" SYNC_ACL=yes
snapper -c home set-config ALLOW_USERS="\$USERNAME" SYNC_ACL=yes
snapper -c home set-config TIMELINE_CREATE=no

echo "[CHROOT] Installing GRUB-Btrfs..."
cd /tmp
git clone https://github.com/Antynea/grub-btrfs.git
cd grub-btrfs
sed -i.bkp \\
  '/^#GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS=/a \\
GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="rd.live.overlay.overlayfs=1"' \\
  config
make install
systemctl enable --now grub-btrfsd.service
cd /
rm -rf /tmp/grub-btrfs

echo "[CHROOT] Final cleanup..."
apt autoremove -y
apt autoclean

echo "[CHROOT] Setup complete!"
CHROOT

  chmod +x /mnt/root/chroot-setup.sh
  ok "Chroot script generated."
}

execute_chroot() {
  info "Entering chroot and running setup..."
  
  # Make sure chroot script exists and is executable
  if [[ ! -x "/mnt/root/chroot-setup.sh" ]]; then
    err "Chroot script not found or not executable"
    return 1
  fi
  
  # Copy the script to a more accessible location and run with explicit error handling
  run_cmd "cp /mnt/root/chroot-setup.sh /mnt/tmp/chroot-setup.sh"
  run_cmd "chmod +x /mnt/tmp/chroot-setup.sh"
  
  # Run chroot with explicit error checking
  if ! chroot /mnt /tmp/chroot-setup.sh; then
    err "Chroot script failed with exit code $?"
    return 1
  fi
  
  # Verify key components were installed
  if [[ ! -f "/mnt/boot/grub/grub.cfg" ]]; then
    warn "GRUB configuration not found - installation may be incomplete"
  fi
  
  ok "System configuration completed."
}

cleanup_and_reboot() {
  info "Cleaning up and preparing for reboot..."
  
  # Unmount all filesystems
  run_cmd "umount -vR /mnt"
  
  # Verify unmount
  if mount | grep -q "/mnt"; then
    warn "Some mounts still active. Force unmounting..."
    run_cmd "umount -vlf /mnt"
  fi
  
  ok "Installation complete! System will reboot."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "DRY-RUN: Would reboot now."
  else
    echo -e "${GREEN}${BOLD}Installation finished successfully!${NC}"
    echo "The system will reboot into your new Debian 13 installation."
    pause
    run_cmd "reboot"
  fi
}

main() {
  banner
  
  # System checks
  require_root
  require_uefi
  check_tools
  
  # User interaction
  select_disk
  choose_desktop
  collect_inputs
  final_confirmation
  
  # Installation phases
  prep_packages
  partition_disk
  create_subvolumes
  mount_layout
  bootstrap_and_chroot
  generate_fstab
  write_chroot_script
  execute_chroot
  cleanup_and_reboot
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
