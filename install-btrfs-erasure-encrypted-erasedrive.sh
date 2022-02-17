#!/usr/bin/env bash

# MAKE SURE TO CHANGE /dev/sdX to proper drive


# Exit the shell script if any individual command fails
set -e

# Enforce running as root
if [ "$EUID" != 0 ]; then
  sudo "$0" "$@"
  exit $?
fi

# Erase whatever partition table was on the drive before and enfore GPT
sgdisk --zap-all /dev/sdX

# 4096MiB /boot parition
sgdisk -n 0:0:+4096MiB /dev/sdX
mkfs.ext4 -L boot /dev/sdX1

# UEFI ESP
sgdisk -n 0:0:+512MiB -t 0:ef00 /dev/sdX
mkfs.vfat -F 32 -n UEFI-ESP /dev/sdX2

# Encrypt / (root)
sgdisk -n 0:0:0 /dev/sdX
# must be `pbkdf2` for grub, in the future `argon2id` will be better
cryptsetup luksFormat /dev/sdX3 --pbkdf pbkdf2
cryptsetup luksOpen /dev/sdX3 nixos-root
mkfs.btrfs /dev/mapper/nixos-root

# Create some recommended btrfs subvolumes
mkdir -p /mnt
mount /dev/mapper/nixos-root /mnt
btrfs subvolume create /mnt/root
btrfs subvolume create /mnt/nix
btrfs subvolume create /mnt/log
btrfs subvolume create /mnt/persist
btrfs subvolume create /mnt/home
btrfs subvolume create /mnt/swap
# Create a snapshot now, this will be our blank snapshot that we roll back to in order to support state erasure
btrfs subvolume snapshot -r /mnt/root /mnt/root-blank
umount /mnt

# Create and mount the folders for the subvolumes we made
mount -o subvol=root,compress=zstd,noatime /dev/mapper/nixos-root /mnt
mkdir -p /mnt/{home,nix,persist,var/log}
mount -o subvol=home,compress=zstd /dev/mapper/nixos-root /mnt/home
mount -o subvol=nix,compress=zstd,noatime /dev/mapper/nixos-root /mnt/nix
mount -o subvol=persist,compress=zstd,noatime /dev/mapper/nixos-root /mnt/persist
mount -o subvol=log,compress=zstd,noatime /dev/mapper/nixos-root /mnt/var/log

# Create the ability to make swapfile
mkdir -p /mnt/swap
mount -o subvol=swap,compress=none,noatime /dev/mapper/nixos-root /mnt/swap
truncate -s 0 /mnt/swap/swapfile
chattr +C /mnt/swap/swapfile

# Mount bootloader
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot

# Mount UEFI ESP partition
mkdir -p /mnt/boot/efi
mount /dev/disk/by-label/UEFI-ESP /mnt/boot/efi

# BY HAND
# mkdir -p /mnt/etc/nixos
# cd /mnt/etc/nixos
#
# have a look at the hardware configuration nixos auto-generates, to help you write your own
# write your system flake.nix and hardware-configuration.nix inside /mnt/etc/nixos
# sudo nixos-generate-config --root /mnt --show-hardware-config
#
# after you've written your configuration files
# sudo nixos-install --flake /mnt/etc/nixos#desktop --recreate-lock-file --no-root-password
#
# copy over you system configuration to /persist so we keep it around on next boot
# sudo mkdir -p /persist/etc && sudo cp -r /mnt/etc/nixos /persist/etc/nixos
# reboot
#
# then when you make changes to your system do
# sudo nixos-rebuild switch --flake /mnt/etc/nixos#desktop
