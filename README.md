# Debian Installer with Btrfs Snapshots

An interactive bash script that installs Debian 13 with Btrfs for a resilient Linux system with rollback capabilities.

## Features

- **UEFI-only** installation with modern GPT partitioning
- **Btrfs filesystem** with optimized subvolume layout
- **Timeshift integration** for automatic system snapshots and rollback
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
   wget https://raw.githubusercontent.com/r41nm4k3r/Btrfs-installer/refs/heads/main/debian13-btrfs-installer.sh
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

### GRUB Integration
- Boot directly into any snapshot from GRUB menu
- Safe rollback without bootable media
- Automatic GRUB menu updates when snapshots created

## Post-Installation

### Timeshift Snapshot Management

The installer includes Timeshift for system snapshots and rollback capabilities:

#### Automatic Snapshots
- **Boot snapshots**: Created automatically at system boot
- **Scheduled snapshots**: Hourly, daily, weekly, and monthly snapshots
- **Cleanup**: Automatic removal of old snapshots based on retention policies

#### Manual Snapshots
```bash
# Create a snapshot
timeshift --create --comments "Before system update"

# IMPORTANT: Update GRUB to include the new snapshot
sudo update-grub

# List snapshots
timeshift --list

# Restore a snapshot
timeshift --restore --snapshot '<snapshot_id>'

# Delete a snapshot
timeshift --delete --snapshot '<snapshot_id>'
```

**Note**: After creating any snapshot with Timeshift, you must run `sudo update-grub` manually to make the snapshot available in the GRUB boot menu.

#### Timeshift Configuration
- Configuration file: `/etc/timeshift.json`
- Snapshots location: `/timeshift-btrfs/snapshots`
- GUI available: `timeshift-gtk` (install separately if needed)

#### Verify Snapshot System
```bash
# Check Timeshift status
timeshift --list

# Verify GRUB integration
sudo grep -i snapshot /boot/grub/grub.cfg

# Check snapshot service status
systemctl status grub-btrfsd.service
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
- Installation log: `./debian13-btrfs-installer.log` (in script directory)
- Chroot script: `/mnt/root/chroot-setup.sh` (in live environment)

### Recovery
If system fails to boot:
1. Boot from live ISO in UEFI mode
2. Mount Btrfs subvolumes manually
3. Use Timeshift to restore: `timeshift --restore --snapshot '<snapshot_id>'`
4. Or use GRUB menu to boot into a previous snapshot

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
