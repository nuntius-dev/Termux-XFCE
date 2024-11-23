#!/bin/bash

# Unofficial Bash Strict Mode
set -euo pipefail
IFS=$'\n\t'

finish() {
  local ret=$?
  if [ ${ret} -ne 0 ] && [ ${ret} -ne 130 ]; then
    echo
    echo "ERROR: Failed to setup XFCE on Termux."
    echo "Please refer to the error message(s) above"
  fi
}

trap finish EXIT

clear

echo ""
echo "This script will install XFCE Desktop in Termux along with a Debian proot"
echo ""

# Define the username automatically as 'ubuntu'
username="ubuntu"

termux-change-repo
pkg update -y -o Dpkg::Options::="--force-confold"
pkg upgrade -y -o Dpkg::Options::="--force-confold"
sed -i '12s/^#//' $HOME/.termux/termux.properties
termux-setup-storage

pkg uninstall dbus -y
pkg install wget ncurses-utils dbus proot-distro x11-repo tur-repo pulseaudio -y

#Create default directories
mkdir -p Desktop
mkdir -p Downloads

setup_proot() {
#Install Debian proot
proot-distro install debian
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 apt update
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 apt upgrade -y
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 apt install sudo wget nala jq flameshot conky-all -y

#Create user
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 groupadd storage
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 groupadd wheel
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 useradd -m -g users -G wheel,audio,video,storage -s /bin/bash "$username"

#Add user to sudoers
chmod u+rw $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/etc/sudoers
echo "$username ALL=(ALL) NOPASSWD:ALL" | tee -a $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/etc/sudoers > /dev/null
chmod u-w  $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/etc/sudoers

#Set proot DISPLAY
echo "export DISPLAY=:1.0" >> $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/home/$username/.bashrc

#Set proot aliases
echo "
alias virgl='GALLIUM_DRIVER=virpipe '
alias ls='eza -lF --icons'
alias cat='bat '
alias apt='sudo nala '
alias install='nala install '
alias uninstall='nala remove '
alias start='echo \"please run from termux, not debian proot.\"'
" >> $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/home/$username/.bashrc

#Set proot timezone
timezone=$(getprop persist.sys.timezone)
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 rm /etc/localtime
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 cp /usr/share/zoneinfo/$timezone /etc/localtime
}

setup_xfce() {
#Install xfce4 desktop and additional packages
pkg install git neofetch virglrenderer-android papirus-icon-theme xfce4 xfce4-goodies eza pavucontrol-qt bat jq nala wmctrl firefox netcat-openbsd termux-x11-nightly eza -y

#Create .bashrc
cp $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/etc/skel/.bashrc $HOME/.bashrc

#Enable Sound
echo "
pulseaudio --start --exit-idle-time=-1
pacmd load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1
" > $HOME/.sound

echo "
source .sound" >> .bashrc

#Set aliases
echo "
alias debian='proot-distro login debian --user $username --shared-tmp'
alias ls='eza -lF --icons'
alias cat='bat '
alias apt='nala $@ '
alias update='nala update'
alias upgrade='nala upgrade'
alias install='nala install $@'
alias uninstall='nala remove $@ '
" >> $HOME/.bashrc

#Put Firefox icon on Desktop
cp $HOME/../usr/share/applications/firefox.desktop $HOME/Desktop 
chmod +x $HOME/Desktop/firefox.desktop

cat <<'EOF' > ../usr/bin/prun
#!/bin/bash
varname=$(basename $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/home/*)
proot-distro login debian --user $varname --shared-tmp -- env DISPLAY=:1.0 $@
EOF
chmod +x ../usr/bin/prun

cat <<'EOF' > ../usr/bin/cp2menu
#!/bin/bash

cd

user_dir="../usr/var/lib/proot-distro/installed-rootfs/debian/home/"

# Get the username from the user directory
username=$(basename "$user_dir"/*)

action=$(zenity --list --title="Choose Action" --text="Select an action:" --radiolist --column="" --column="Action" TRUE "Copy .desktop file" FALSE "Remove .desktop file")

if [[ -z $action ]]; then
  zenity --info --text="No action selected. Quitting..." --title="Operation Cancelled"
  exit 0
fi

if [[ $action == "Copy .desktop file" ]]; then
  selected_file=$(zenity --file-selection --title="Select .desktop File" --file-filter="*.desktop" --filename="../usr/var/lib/proot-distro/installed-rootfs/debian/usr/share/applications")

  if [[ -z $selected_file ]]; then
    zenity --info --text="No file selected. Quitting..." --title="Operation Cancelled"
    exit 0
  fi

  desktop_filename=$(basename "$selected_file")

  cp "$selected_file" "../usr/share/applications/"
  sed -i "s/^Exec=\(.*\)$/Exec=proot-distro login debian --user $username --shared-tmp -- env DISPLAY=:1.0 \1/" "../usr/share/applications/$desktop_filename"

  zenity --info --text="Operation completed successfully!" --title="Success"
elif [[ $action == "Remove .desktop file" ]]; then
  selected_file=$(zenity --file-selection --title="Select .desktop File to Remove" --file-filter="*.desktop" --filename="../usr/share/applications")

  if [[ -z $selected_file ]]; then
    zenity --info --text="No file selected for removal. Quitting..." --title="Operation Cancelled"
    exit 0
  fi

  desktop_filename=$(basename "$selected_file")

  rm "$selected_file"

  zenity --info --text="File '$desktop_filename' has been removed successfully!" --title="Success"
fi

EOF
chmod +x ../usr/bin/cp2menu

echo "[Desktop Entry]
Version=1.0
Type=Application
Name=cp2menu
Comment=
Exec=cp2menu
Icon=edit-move
Categories=System;
Path=
Terminal=false
StartupNotify=false
" > $HOME/Desktop/cp2menu.desktop 
chmod +x $HOME/Desktop/cp2menu.desktop
mv $HOME/Desktop/cp2menu.desktop $HOME/../usr/share/applications

#App Installer Utility
git clone https://github.com/phoenixbyrd/App-Installer.git
mv $HOME/App-Installer $HOME/.App-Installer
chmod +x $HOME/.App-Installer/*

echo "[Desktop Entry]
Version=1.0
Type=Application
Name=App Installer
Comment=
Exec=/data/data/com.termux/files/home/.App-Installer/app-installer
Icon=package-install
Categories=System;
Path=
Terminal=false
StartupNotify=false
" > $HOME/Desktop/App-Installer.desktop
chmod +x $HOME/Desktop/App-Installer.desktop
cp $HOME/Desktop/App-Installer.desktop $HOME/../usr/share/applications

}

setup_termux_x11() {
# Install Termux-X11

wget https://github.com/termux/termux-x11/releases/download/nightly/termux-x11-nightly-1.03.00-0-all.deb
dpkg -i termux-x11-nightly-1.03.00-0-all.deb
rm termux-x11-nightly-1.03.00-0-all.deb
#apt-mark hold termux-x11-nightly

wget https://github.com/termux/termux-x11/releases/download/nightly/app-arm64-v
