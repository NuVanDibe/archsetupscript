#! /bin/bash
# Remove before sending
set -e

echo "Press [Enter] to update the date & time from time.nist.gov."
read
date -s "$(bash -c "cat </dev/tcp/time.nist.gov/13" | cut -d " " -f 2-3)" > /dev/null
echo " "
echo "The current date is now:"
echo " "
date
echo " "
echo "If that's wrong, ctrl+c to abort and try setting it manually. Otherwise, press [Enter] to continue."
read
echo "WARNING: PROCEEDING MAY DESTROY DATA!"
echo "No, seriously, there are NO safeties built into this script."
echo "If you're absolutely sure, type Y and press [Enter]."
read areyousure
[[ "$areyousure" =~ [Yy] ]] || exit 1

echo ""
echo ""
lsblk
echo ""
echo "Type the device path (eg: /dev/sda) to wipe and repartition."
#echo "Type the device path (eg: /dev/sda) to wipe and repartition. This will take effect"
#echo "immediately and permanently. Be sure you know what you're doing. There are no second"
#echo "chances."
read insdev

echo "Now set up the partitions. Partition 1 will be EFI, 2 will be OS, 3 will be SWAP."
fdisk $insdev

#todo: this will get the amount of installed ram and output it as "-ramM"
#-$(free -m | awk 'NR == 2 {print $2}')M

mkfs.btrfs ${insdev}2
mkfs.fat -F 32 ${insdev}1
mount ${insdev}2 /mnt
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@opt
btrfs su cr /mnt/@tmp
btrfs su cr /mnt/@.snapshots
btrfs su cr /mnt/@var
mkswap ${insdev}3
swapon ${insdev}3
umount -r /mnt
mkdir /mnt/butter
mount -o noatime,commit=120,compress=zstd,space_cache,clear_cache,subvol=@ ${insdev}2 /mnt/butter/
mkdir /mnt/butter/{home,opt,tmp,var,.snapshots,boot}
mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@home ${insdev}2 /mnt/butter/home
mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@opt ${insdev}2 /mnt/butter/opt
mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@tmp ${insdev}2  /mnt/butter/tmp
mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@.snapshots ${insdev}2 /mnt/butter/.snapshots
mount -o subvol=@var ${insdev}2 /mnt/butter/var
mount ${insdev}1 /mnt/butter/boot

sed -i "s/#ParallelDownloads/ParallelDownloads/g" /etc/pacman.conf

echo "Do you want linux-lts linux-zen or linux? Type it exactly."
read wkern
pacstrap /mnt/butter base $wkern $wkern-headers dkms linux-firmware nano amd-ucode intel-ucode btrfs-progs

genfstab -U /mnt/butter >> /mnt/butter/etc/fstab

cat << EOF > /mnt/butter/root/scrip.sh
#! /bin/bash
set -e

echo "Type your timezone. It is case sensitive. eg: America/Chicago"
read localev

echo "Type the hostname for the system."
while [[ -z \$hname ]]; do read hname; done

echo "Now choose a password for root:"
passwd

echo "Type a non-root username to become a sudoer."
read nameofnonrootuser
useradd -mG wheel \$nameofnonrootuser

echo "Now choose a password for \$nameofnonrootuser:"
passwd \$nameofnonrootuser

echo "Want xorg?"
read wgui
[[ "\$wgui" =~ [Yy] ]] && packidge="\$packidge xorg-server"

echo "Drivers for Nvidia Turing or more recent GPU?"
read wnvidia
[[ "\$wnvidia" =~ [Yy] ]] && packidge="\$packidge nvidia-open-dkms mesa nvidia-utils vulkan-icd-loader lib32-vulkan-icd-loader nvidia-settings"

echo "Drivers for AMD GPU?"
read wamd
[[ "\$wamd" =~ [Yy] ]] && packidge="\$packidge mesa lib32-mesa amdvlk lib32-amdvlk vulkan-icd-loader lib32-vulkan-icd-loader xf86-video-amdgpu libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau"

echo "Drivers for Intel integrated graphics?"
read wamd
[[ "\$wamd" =~ [Yy] ]] && packidge="\$packidge mesa lib32-mesa vulkan-intel xf86-video-intel intel-media-driver"

echo "PulseAudio?"
read wpulse
[[ "\$wpulse" =~ [Yy] ]] && packidge="\$packidge pulseaudio pulseaudio-bluetooth bluez"

echo "KDE Plasma?"
read wkde
[[ "\$wkde" =~ [Yy] ]] && packidge="\$packidge plasma-desktop"

[[ "\$wkde" =~ [Yy] ]] && echo "KDE Meta?"
read wkdemeta
[[ "\$wkdemeta" =~ [Yy] ]] && packidge="\$packidge kde-meta"

[[ "\$wkde" =~ [Yy] ]] && echo "Default KDE Applications?"
read wkdeapps
[[ "\$wkdeapps" =~ [Yy] ]] && packidge="\$packidge kde-applications"

echo "LXDE?"
read wlxde
[[ "\$wlxde" =~ [Yy] ]] && packidge="\$packidge lxde"

echo "Gnome?"
read wgnome
[[ "\$wgnome" =~ [Yy] ]] && packidge="\$packidge gnome"

echo "Type any additional pacman (not yay/aur) packages, if any, separated by spaces, and press enter."
read wpackidge
packidge="\$packidge \$wpackidge"

echo "Type any additional aur packages, if any, separated by spaces, and press enter. Example: "aur/linux-steam-integration aur/brave-bin"
read wyaykidge
yaykidge="\$wyaykidge"

#todo: debug line
echo "packages: "\$packidge

ln -sf /usr/share/zoneinfo/\${localev} /etc/localtime
hwclock --systohc

# set en_US.UTF-8 as default locale. todo: ask prior to this if en_US.UTF-8 should be changed
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf

# enable parallel downloads in pacman
sed -i "s/#ParallelDownloads/ParallelDownloads/g" /etc/pacman.conf
echo "[multilib]" >> /etc/pacman.conf
echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf

# grab some nice default packages
pacman -Sy grub grub-btrfs efibootmgr base-devel linux-headers networkmanager wpa_supplicant dialog os-prober mtools dosfstools reflector git go openssh vim screen --noconfirm

sed -i "s/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD:ALL/g" /etc/sudoers
sed -i "s/MODULES=()/MODULES=\(btrfs\)/g" /etc/mkinitcpio.conf
sed -i "s/#PermitRootLogin without-password/PermitRootLogin yes/g" /etc/ssh/sshd_config
echo "include \"/usr/share/nano/*.nanorc\"" >> /etc/nanorc

mkinitcpio -p $wkern

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id = Arch --removable
grub-mkconfig -o /boot/grub/grub.cfg

# construct yay aur helper as a non-root user:
su - \$nameofnonrootuser -c "git clone https://aur.archlinux.org/yay-git.git"
su - \$nameofnonrootuser -c "cd yay-git && makepkg -i --noconfirm"

# set hostname and hosts file
echo \$hname >> /etc/hostname
cat << eohosts >> /etc/hosts
127.0.0.1	localhost
::1		localhost
127.0.1.1	\${hname}.localdomain	\$hname
eohosts

if [[ -z "\$packidge" ]]; then echo Skipping additional package install; else pacman -S \$packidge --noconfirm; fi

if [[ -z "\$yaykidge" ]]; then echo Skipping additional aur package install; else su - \$nameofnonrootuser -c "yay -S $yaykidge --noconfirm"; fi

# if lxde was chosen, wipe out twm and add lxde to xinitrc
[[ "\$wlxde" =~ [Yy] ]] && sed "\$(grep -n 'twm' /etc/X11/xinit/xinitrc | cut -d ':' -f 1).\$(wc -l /etc/X11/xinit/xinitrc | cut -d ' ' -f 1)d" /etc/X11/xinit/xinitrc
[[ "\$wlxde" =~ [Yy] ]] && echo exec startlxde >> /etc/X11/xinit/xinitrc

# enable services
systemctl enable NetworkManager
[[ "$wpulse" =~ [Yy] ]] && systemctl enable bluez
[[ "$wkdemeta" =~ [Yy] ]] && systemctl enable sddm

echo "You're done! If everything went well, go ahead and reboot the system."
exit
EOF

chmod +x /mnt/butter/root/scrip.sh

echo "If all went well, run /root/scrip.sh"
arch-chroot /mnt/butter
