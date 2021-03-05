#!/usr/bin/env bash
set -e

SCRIPT_NAME=`basename "$0"`
INITIAL_DIRECTORY=$(pwd)
INSTALLER_DIRECTORY=$(realpath "$(dirname "$0")")
cd "$INSTALLER_DIRECTORY"

. $INSTALLER_DIRECTORY/config.sh
. $INSTALLER_DIRECTORY/functions.sh

ACTION=$1
if [ -z "$ACTION" ]; then
cat << EOF
raspi-router

Usage examples:
  ${SCRIPT_NAME} info
  ${SCRIPT_NAME} prepare
  ${SCRIPT_NAME} install
EOF
  exit 0
fi

if [ "$ACTION" = "info" ]; then
  print_system_information  
  exit 0
fi

# quick validation checks
exit_if_not_root
exit_if_undefined "$STORAGE_PARTITION" STORAGE_PARTITION
exit_if_undefined "$STORAGE_PATH" STORAGE_PATH
exit_if_undefined "$TIMEZONE" TIMEZONE
exit_if_undefined "$ETHX0_MAC" ETHX0_MAC
exit_if_undefined "$WLNX0_MAC" WLNX0_MAC
exit_if_undefined "$WLNX1_MAC" WLNX1_MAC
exit_if_undefined "$HOSTAPD_PWD" HOSTAPD_PWD
exit_if_hostapd_misconfiguration "$HOSTAPD_FREQ" "$HOSTAPD_CHANNEL"
exit_if_no_internet_connection

if [ "$ACTION" = "prepare" ]; then
  echo "Configuring \"root\" account"
  configure_root_account "$DISABLE_ROOT"

  echo "Configuring partitions"
  sed -i '/ext4/s/defaults,noatime/defaults,noatime,commit=30/' /etc/fstab
  configure_partition "$STORAGE_PARTITION" "$STORAGE_PATH" "defaults,noatime,commit=60" 2
  configure_partition "${STORAGE_PATH}/etc/iptables" /etc/iptables "defaults,bind"
  configure_partition "${STORAGE_PATH}/etc/ufw" /etc/ufw "defaults,bind"
  configure_partition "${STORAGE_PATH}/etc/hostapd" /etc/hostapd "defaults,bind"

  echo "Creating \"${USERNAME}\" user"
  add_new_user "$USERNAME" "$STORAGE_PATH"

  echo "Configuring hostname"
  echo "${HOSTNAME}" > /etc/hostname
  sed -i "s/raspberrypi/${HOSTNAME}/" /etc/hosts

  echo "Setting up locale"
  raspi-config nonint do_change_locale "$LOCALE"
  export LANG="$LOCALE"

  echo "Setting keyboard layout"
  raspi-config nonint do_configure_keyboard "$KEYBOARD_LAYOUT"

  echo "Setting timezone"
  ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime

  echo "Configuring fake hardware clock"
  configure_fake_hwclock "${STORAGE_PATH}/etc/fake-hwclock.data"

  echo "Disabling unused modules"
  disable_unused_modules

  echo "Disabling serial console"
  raspi-config nonint do_serial 1

  echo "Disabling swap"
  systemctl disable --now dphys-swapfile.service
  dphys-swapfile swapoff
  dphys-swapfile uninstall

  echo "Setting memory split"
  raspi-config nonint do_memory_split 16

  echo "Disabling services"
  disable_services

  echo "Configuring journald"
  configure_journald

  echo "Configuring packages"
  configure_packages
  override_ufw_service

  echo "Setting up static network names"
  set_network_name "$ETHX0_MAC" ethx0
  set_network_name "$WLNX0_MAC" wlnx0
  set_network_name "$WLNX1_MAC" wlnx1

  echo "Configuring network adapters"
  dhcpcd_ignore_device ethx0
  dhcpcd_ignore_device wlnx0
  add_bridge brdx0 ethx0 wlnx0
  configure_bridge brdx0 "$BRDX0_ADDRESS" "$BRDX0_NETMASK"

  echo -e "Next time login as \"${USERNAME}\" and run \"${SCRIPT_NAME} install\"\n"
  reboot_with_warning
  exit 0
fi

if [ "$ACTION" = "install" ]; then
  if [ "$(get_running_user)" = "pi" ]; then
    echo "Can not install from \"pi\" user, please run \"${SCRIPT_NAME} prepare\" to setup user accounts"
    exit 1
  fi

  if [ "$INSTALL_DOCKER" = "yes" ]; then
    echo "Installing docker"
    DOCKER_KEY=$(add_docker_key)
    exit_if_undefined "$DOCKER_KEY" DOCKER_KEY
    add_docker_repository
    install_docker "$USERNAME" "$STORAGE_PATH"
  fi

  echo "Configuring sshd"
  configure_sshd "$BRDX0_ADDRESS"

  echo "Configuring firewall"
  configure_iptables
  configure_forwarding wlnx1 "$BRDX0_ADDRESS" "$BRDX0_NETMASK"
  configure_ufw brdx0

  echo "Configuring hostapd"
  install_channeltest
  BEST_CHANNEL=$(get_best_channel wlnx0 "${HOSTAPD_CHANNEL}")
  HOSTAPD_COUNTRY_CODE=$(get_country_code)
  configure_hostapd wlnx0 brdx0 "$HOSTAPD_FREQ" "$BEST_CHANNEL" \
    "$HOSTAPD_COUNTRY_CODE" "$HOSTAPD_SSID" "$HOSTAPD_PWD"
  if [ "$HOSTAPD_SLEEP" = "yes" ]; then
    configure_hostapd_sleep "$HOSTAPD_STOP_AT" "$HOSTAPD_START_AT"
  fi

  echo "Installing pihole"
  if [ "$INSTALL_DOCKER" = "yes" ] && [ "$INSTALL_PIHOLE" = "yes" ]; then
    install_pihole "$USERNAME" "$TIMEZONE" "$BRDX0_ADDRESS" brdx0 \
      "$PIHOLE_MAXDBDAYS" "$PIHOLE_VOLATILE_FTL_DB"
    wait_for_pihole
    if [ "$PIHOLE_ENABLE_DHCP" = "yes" ]; then
      enable_dhcp "$BRDX0_ADDRESS" "$BRDX0_NETMASK" "$PIHOLE_DHCP_DOMAIN"
    fi
  fi

  echo "Configuring boot partition"
  install_fsmodesync
  install_bootmodesync_service
  systemctl enable bootmodesync

  echo "Configuring overlayfs"
  configure_overlayfs enable

  cd "$INITIAL_DIRECTORY"

  echo "Removing default user"
  remove_default_user

  if [ "$REMOVE_AFTER_INSTALL" = "yes" ]; then
    # extra safety check to remove the files only if running in a raspberry pi
    if [ ! -z "$(get_raspberry_pi_model)" ]; then
      rm -rf "$INSTALLER_DIRECTORY"
    fi
  fi

  reboot_with_warning
fi
