# Debian 13 (Trixie) Btrfs Snapshot Installer

An interactive bash script that installs Debian 13 with Btrfs snapshots, Snapper, and GRUB-Btrfs for a resilient Linux system with rollback capabilities.

## Features

- **UEFI-only** installation with modern GPT partitioning
- **Btrfs filesystem** with optimized subvolume layout
- **Automatic snapshots** with Snapper for system rollback
- **GRUB-Btrfs integration** for booting directly into snapshots
- **Hibernation support** with Btrfs swap file
- **Multiple desktop environments**: GNOME, KDE Plasma, XFCE
- **Beautiful TUI** with colored output and progress indicators
- **Dry-run mode** for testing without making changes

## System Requirements

- UEFI-capable system (Secure Boot can be disabled for hibernation)
- Debian 13 (Trixie) Live ISO booted in UEFI mode
- Minimum 8GB RAM (recommended for desktop environments)
- At least 25GB disk space (recommended 50GB+)

## Quick Start

1. Boot from Debian 13 (Trixie) Live ISO in **UEFI mode**
2. Open terminal and run:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/your-repo/debian13-btrfs-installer/main/debian13-btrfs-installer.sh | bash
   ```
   Or download and run:
   ```bash
   wget https://raw.githubusercontent.com/your-repo/debian13-btrfs-installer/main/debian13-btrfs-installer.sh
   chmod +x debian13-btrfs-installer.sh
   sudo bash debian13-btrfs-installer.sh
   ```

## Installation Process

The installer will guide you through:

1. **Disk Selection** - Choose target disk (all data will be erased)
2. **Desktop Environment** - GNOME, KDE Plasma, or XFCE
3. **System Configuration** - Hostname, username, passwords, timezone
4. **Confirmation** - Type confirmation phrase to proceed
5. **Automated Installation** - Partitioning, system setup, and configuration

## Btrfs Subvolume Layout

```
/                    @                    (root filesystem)
/home               @home               (user data)
/opt                @opt                (optional software)
/var/cache          @cache              (cache data)
/var/lib/gdm3       @gdm3/@sddm/@lightdm (display manager)
/var/lib/libvirt    @libvirt            (virtual machines)
/var/log            @log                (system logs)
/var/spool          @spool              (spool data)
/var/tmp            @tmp                (temporary files)
/var/swap           @swap               (swap file location)
/boot/efi           (EFI partition)
```

## Snapshot & Rollback Features

### Automatic Snapshots
- **Boot snapshots**: Created at every system boot
- **Timeline snapshots**: Hourly snapshots for root filesystem
- **Cleanup**: Automatic removal of old snapshots

### Manual Snapshots
```bash
# Create snapshot
sudo snapper create -d "Before system update"

# List snapshots
sudo snapper list

# Rollback to snapshot
sudo snapper rollback <number>
```

### GRUB Integration
- Boot directly into any snapshot from GRUB menu
- Safe rollback without bootable media
- Automatic GRUB menu updates when snapshots created

## Post-Installation

### Verify Snapshot System
```bash
# Check Snapper status
sudo systemctl status snapper-timeline.timer
sudo snapper list-configs

# Create test snapshot
sudo snapper create -d "Test snapshot"

# Verify GRUB integration
sudo grep -i snapshot /boot/grub/grub.cfg
```

### Hibernation
- Requires Secure Boot to be disabled
- Check with: `mokutil --sb-state`
- Use `systemctl suspend` if Secure Boot must remain enabled

## Troubleshooting

### Common Issues

1. **UEFI Mode Required**: Boot the live ISO in UEFI mode, not legacy/BIOS
2. **Missing Tools**: Script installs required packages automatically
3. **Disk Mounted**: Ensure target disk is not mounted before starting
4. **Secure Boot**: Disable for hibernation support

### Log Files
- Installation log: `/tmp/debian13-btrfs-installer.log`
- Chroot script: `/mnt/root/chroot-setup.sh` (in live environment)

### Recovery
If system fails to boot:
1. Boot from live ISO in UEFI mode
2. Mount Btrfs subvolumes manually
3. Use Snapper to rollback: `snapper rollback <number>`

## Script Options

The script supports these environment variables:

- `DRY_RUN=1` - Print commands without executing
- `LOG_FILE` - Custom log file location

Example:
```bash
sudo DRY_RUN=1 bash debian13-btrfs-installer.sh
```

## Security Notes

- Passwords are handled securely with hashed values
- No passwords are stored in plain text
- Root and user passwords are required
- Script must be run as root (sudo)

## Contributing

1. Fork the repository
2. Create feature branch
3. Test thoroughly in virtual machines
4. Submit pull request

## License

MIT License - see LICENSE file for details

## Credits

Based on the guide: [How to Install Debian 13 with Btrfs Snapshots and Rollback](https://sysguides.com/install-debian-13-with-btrfs)

Inspired by Fedora Btrfs installation practices and Arch Linux Snapper documentation.
