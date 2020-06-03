#!/usr/bin/env false

# $1: message to show
function pause() {
  local DEFAULT_MESSAGE="Press any key to continue..."
  read -n 1 -s -r -p "${1:-${DEFAULT_MESSAGE}}"
  echo
}

function reboot_with_warning() {
  pause "A restart is required, press any key to restart the system..."
  reboot
}

function exit_if_not_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
  fi
}

# $1: variable value, $2: variable name
function exit_if_undefined() {
  if [ -z "$1" ]; then
    echo "Error: \"$2\" is not defined"
    exit 1
  fi
}

function print_system_information() {
  echo -e "\nNETWORK\n"
  find /sys/class/net \
    -mindepth 1 -maxdepth 1 ! -name lo \
    -printf "%P: " -execdir cat {}/address \;
  echo -e "\nBLOCK DEVICES\n"
  lsblk -f
}

# $1: disable root?
function configure_root_account() {
  if [ "${1}" = "yes" ]; then
    passwd root -l
  fi
  cp ./defaults/.vimrc /root/.vimrc
  chown root:root /root/.vimrc
}

# $1: username
function change_password() {
  if [ -z "$1" ]; then
    echo "A username must be passed as the first argument"
    return 1
  fi
  while [ "$(USERNAME=$1 sh -i -c '{ passwd $USERNAME && echo OK; } || true')" != "OK" ]; do
    pause "Press any key to try again or Ctrl+C to cancel"
  done
  return 0
}

# $1: username, $2: storage path
function add_new_user() {
  mkdir -p "${2}/home"
  local HOME_DIR="${2}/home/${1}"
  useradd -m -G sudo,users -d "$HOME_DIR" -s /bin/bash $1
  change_password ${1}
  mkdir -p "${HOME_DIR}/.config/htop"
  cp ./defaults/htoprc "${HOME_DIR}/.config/htop/htoprc"
  cp ./defaults/.vimrc "${HOME_DIR}/.vimrc"
  sed "s|{STORAGE_PATH}|${2}|" ./defaults/.bashrc >> "${HOME_DIR}/.bashrc"
  chown -R "${1}:${1}" "$HOME_DIR"
}

function remove_default_user() {
  killall -9 -u pi -w | true
  userdel pi
  rm -rf /home/pi
}

# https://wiki.archlinux.org/index.php/Fstab#Usage
# $1: partition or path, $2: mount point, $3: flags,  $4: fsck
function configure_partition() {
  local TYPE=auto
  # if $1 is not a block device
  if [ ! -b "${1}" ]; then
    TYPE=none
    mkdir -p "${1}"
  fi
  mkdir -p "$2"
  mount -o "$3" "$1" "$2"
  echo "${1} ${2} ${TYPE} ${3} 0 ${4:-0}" >> /etc/fstab
  chmod 755 "$2"
}

function configure_packages() {
  # remove unnecessary packages
  apt-get autoremove --purge -y vim-tiny nano triggerhappy dphys-swapfile \
    unattended-upgrades
  # upgrade the system and install utilities
  apt-get update
  apt-get dist-upgrade -y
  apt-get install -y vim htop tmux bc stress bridge-utils ufw iperf3 wavemon \
    speedtest-cli hostapd git apt-transport-https ca-certificates curl \
    gnupg-agent software-properties-common
  apt-get clean
}

function configure_journald() {
  sed -i \
    "s/#Storage=auto/Storage=volatile/; s/#RuntimeMaxUse=/RuntimeMaxUse=64M/" \
    /etc/systemd/journald.conf
  systemctl restart systemd-journald.service
}

# add gpg key and make sure it's valid
function add_docker_key() {
  curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
  apt-key fingerprint 0EBFCD88 2>/dev/null | grep "$DOCKER_FINGERPRINT"
}

function add_docker_repository() {
  # use official raspbian repository (armhf debian is not recommended)
  echo "deb [arch=armhf] https://download.docker.com/linux/raspbian \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list
}

# $1: docker user, $2: storage path
function install_docker() {
  apt-get update
  # do not install aufs-tools which causes problems and is deprecated anyway
  apt-get install -y --no-install-recommends docker-ce
  apt-get install -y docker-compose
  apt-get clean
  usermod -aG docker $1
  # move docker directories to persistent storage
  systemctl stop docker
  systemctl stop containerd
  # if no storage path defined, /dev/null will cause script to throw and error
  local PERSISTENT_VAR_LIB="${2:-/dev/null}/var/lib"
  mkdir -p "$PERSISTENT_VAR_LIB"
  mv /var/lib/docker "${PERSISTENT_VAR_LIB}/docker"
  mv /var/lib/containerd "${PERSISTENT_VAR_LIB}/containerd"
  # create bind mounts
  configure_partition "${PERSISTENT_VAR_LIB}/docker" /var/lib/docker "defaults,relatime,bind"
  configure_partition "${PERSISTENT_VAR_LIB}/containerd" /var/lib/containerd "defaults,relatime,bind"
  systemctl start docker
}

function disable_unused_modules() {
  cat <<EOT >> /etc/modprobe.d/blacklist.conf
# bluetooth
blacklist btbcm
blacklist hci_uart
# sound
install snd /bin/true
EOT
  systemctl disable --now hciuart.service
}

function disable_services() {
  systemctl disable --now apt-daily.timer
  systemctl mask apt-daily.timer
  systemctl disable --now apt-daily-upgrade.timer
  systemctl disable --now apt-daily.service
  systemctl mask apt-daily.service
  systemctl disable --now apt-daily-upgrade.service
  systemctl mask apt-daily-upgrade.service
  systemctl disable --now man-db.timer
  systemctl mask man-db.timer
  systemctl disable --now man-db.service
}

# prints 0 if internet connection is ok
# $1: test url
function check_connectivity() {
  sh -c "wget -q --timeout=10 --spider '${1}'; echo \$?"
}

function exit_if_no_internet_connection() {
  local TEST_URL="http://google.com"
  if [ "$(check_connectivity "${TEST_URL}")" -ne 0 ]; then
    echo "Error: an internet connection is required"
    exit 1
  fi
}

function get_raspberry_pi_model() {
  local MODEL_FILE=/proc/device-tree/model
  if [ -z "$MODEL_FILE" ]; then
    return
  fi
  # https://stackoverflow.com/a/46163991
  tr -d '\0' </proc/device-tree/model
}

# used to detect if current script is running under the factory user i.e. "pi"
function get_running_user() {
  # pid of the parent process, this will be the pid of sudo if sudo was used
  local SUDO_PID=$(ps -o ppid= -p $PPID)
  # print the username of the grand parent of the current process
  ps -o user= -p $SUDO_PID
}

# $1: new file path
function configure_fake_hwclock() {
  local TARGET_DIRECTORY=$(dirname "$1")
  mkdir -p "$TARGET_DIRECTORY"
  echo "FILE=${1}" >> /etc/default/fake-hwclock
  systemctl restart fake-hwclock.service
  rm -f /etc/fake-hwclock.data
}

# enabling predictable network names on raspi-config is not reliable as some
# names can be reused if an adapter is connected to a different usb port, so
# set static names by creating link files instead
# https://wiki.debian.org/NetworkInterfaceNames#CUSTOM_SCHEMES_USING_.LINK_FILES
# $1: mac address, $2: network name
function set_network_name() {
  # disable 99-default.link so it does not interfere with other rules
  ln -sf /dev/null /etc/systemd/network/99-default.link
  echo -e "[Match]\nMACAddress=${1}\n[Link]\nName=${2}" > "/etc/systemd/network/99-${2}.link"
}

# if given interface name is not a wireless adapter, result will be empty
# $1: interface name
function is_wireless_adapter() {
  if [ ! -z "${1}" ]; then
    iwconfig 2>/dev/null | grep -E "^${1}\s+"
  fi
}

# setup dhcp to ignore selected device, so it does not get an ip address
# automatically and does not connect to a wireless network (if applicable)
function dhcpcd_ignore_device() {
  if [ "$(is_wireless_adapter "${1}")" ]; then
cat <<EOT >> /etc/dhcpcd.conf
denyinterfaces ${1}
interface ${1}
  nohook wpa_supplicant
EOT
  else
cat <<EOT >> /etc/dhcpcd.conf
denyinterfaces ${1}
EOT
  fi
}

# get mask bits from a netmask address e.g. 255.255.255.0 -> 24
# https://gist.github.com/Akendo/6cf70aa01f92ab2f03ae6c27480f713e
# $1: netmask address
function netmask_to_cidr() {
  python3 -c "print(sum([ bin(int(bits)).count('1') for bits in '${1}'.split('.') ]))"
}

# get broadcast address from a given an ip address and a netmask
# e.g. get_broadcast_address 10.0.0.1 255.255.255.0 -> 10.0.0.255
# $1: ip address, $2: netmask
function get_broadcast_address() {
  python3 -c "import ipaddress; print(ipaddress.IPv4Network('${1}/${2}', False).broadcast_address)"
}

# get subnet address, see also https://stackoverflow.com/a/47318117
# e.g. get_subnet_address 10.0.0.1 255.255.255.0 -> 10.0.0.0
# $1: ip address, $2: netmask
function get_subnet_address() {
  python3 -c "import ipaddress; print(ipaddress.IPv4Address(int(ipaddress.IPv4Address('${1}')) & int(ipaddress.IPv4Network('${1}/${2}', False).netmask)))"
}

# the bridge-utils package is required for this command to work
# $1: bridge name, $2: first interface, $3: second interface
function add_bridge() {
  echo -e "auto ${1}\niface ${1} inet manual\nbridge_ports ${2} ${3}" >> /etc/network/interfaces
}

# add command to setup the ip address of the bridge on each boot, sed will add
# this command before the last line of rc.local which usually is an exit command
# $1: name,  $2: ip address, $3: netmask
function configure_bridge() {
  local BORADCAST_ADDRESS=$(get_broadcast_address "${2}" "${3}")
  sed -i -e "\$i ifconfig ${1} ${2} netmask ${3} broadcast ${BORADCAST_ADDRESS}\n" /etc/rc.local
}

# script to clear all iptables rules
function install_iptables_flush() {
  install -m 755 ./bin/iptables-flush.sh /usr/local/bin/iptables-flush
}

# create systemd unit to load iptables rules at boot
function install_iptables_service() {
cat <<EOT > /etc/systemd/system/iptables.service
[Unit]
Description=Packet Filtering Framework
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/iptables-restore /etc/iptables/iptables.rules
ExecReload=/usr/sbin/iptables-restore /etc/iptables/iptables.rules
ExecStop=/usr/local/bin/iptables-flush
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOT
  systemctl daemon-reload
}

# sed explanation at https://unix.stackexchange.com/a/26639
# $1: listen address
function configure_sshd() {
  sed -i -r \
    -e 's/^ListenAddress.*//' \
    -e "\$a ListenAddress ${1}" \
    /etc/ssh/sshd_config
}

# $1: frequency, $2: channel
function exit_if_hostapd_misconfiguration() {
  if [ "${1}" != "2GHz" ] && [ "${1}" != "5GHz" ]; then
   echo "Error: \"HOSTAPD_FREQ\" must be either 2GHz or 5GHz (case sensitive)"
   exit 1
  fi
  if [ -z "${2}" ] && [ "${1}" != "2GHz" ]; then
    echo "Error: \"HOSTAPD_CHANNEL\" can be empty only if \"HOSTAPD_FREQ\" is 2GHz"
    exit 1
  fi
}

function install_channeltest() {
  install -m 755 ./bin/channeltest.py /usr/local/bin/channeltest
}

# $1: wireless interface, $2: predefined channel
function get_best_channel() {
  if [ ! -z "${2}" ]; then
    echo "${2}"
    return
  fi
  ip link set "${1}" up
  channeltest "${1}"
}

function get_country_code() {
  # https://stackoverflow.com/a/1665662
  sed -r 's/^country=([A-Z]+$)/\1/;t;d' /etc/wpa_supplicant/wpa_supplicant.conf
}

# $1: host interface, $2: bridge interface, $3: frequency, $4: channel
# $5: country code, $6: ssid, $7: passphrase
function configure_hostapd() {
  local CONFIG_FILE=./defaults/hostapd.conf
  if [ "HOSTAPD_FREQ" = "5GHz" ]; then
    CONFIG_FILE=./defaults/hostapd5.conf
  fi
  local CONFIG_NAME=default
  local SSID=$(echo "${6}" | sed -e 's/\\/\\\\/g; s/\//\\\//g; s/&/\\\&/g')
  local PWD=$(echo "${7}" | sed -e 's/\\/\\\\/g; s/\//\\\//g; s/&/\\\&/g')
  sed \
    -e "s/{HOST_INTERFACE}/${1}/" \
    -e "s/{BRIDGE_INTERFACE}/${2}/" \
    -e "s/{CHANNEL}/${4}/" \
    -e "s/{COUNTRY_CODE}/${5}/" \
    -e "s/{SSID}/${SSID}/" \
    -e "s/{PWD}/${PWD}/" \
    "$CONFIG_FILE" > "/etc/hostapd/${CONFIG_NAME}.conf"
  systemctl enable "hostapd@${CONFIG_NAME}"
}

function configure_iptables() {
  update-alternatives --set iptables /usr/sbin/iptables-legacy
  install_iptables_flush
  touch /etc/iptables/iptables.rules
  install_iptables_service
  systemctl enable iptables.service
}

# keep in mind that calling iptables will not work if the kernel was just
# upgraded and a reboot was not performed
# $1: interface with internet access, $2: bridge address, $3: bridge netmask
function configure_forwarding() {
  echo "net.ipv4.ip_forward = 1" > /etc/sysctl.conf
  local SUBNET_ADDRESS=$(get_subnet_address "${2}" "${3}")
  local NETMASK_BITS=$(netmask_to_cidr "${3}")
  iptables -t nat -A POSTROUTING -s "${SUBNET_ADDRESS}/${NETMASK_BITS}" -o "${1}" -j MASQUERADE
  iptables-save > /etc/iptables/iptables.rules
  sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
}

# because /etc/ufw is not mounted before ufw.service starts, we need to override
# the configuration to make it to start after mounts are ready
function override_ufw_service() {
  mkdir -p /etc/systemd/system/ufw.service.d
  echo -e "[Unit]\nBefore=\nAfter=local-fs.target" \
    > /etc/systemd/system/ufw.service.d/override.conf
  systemctl daemon-reload
}

# $1: bridge interface
function configure_ufw() {
  # 0.0.0.0/0 will force ipv4 only
  ufw allow in on ${1} to 0.0.0.0/0 port 22 proto tcp comment ssh
  # ports 80 and 443 will be used for web admin and also for empty responses
  ufw allow in on ${1} to any port 80,443 proto tcp comment pihole-lighttpd 
  ufw allow in on ${1} to any port 4711 proto tcp comment pihole-ftl
  ufw allow in on ${1} to any port 53 comment pihole-dns
  ufw allow in on ${1} to 0.0.0.0/0 port 67 proto udp comment pihole-dhcp
  ufw allow in on ${1} to ::/0 port 547 proto udp comment pihole-dhcp
  ufw --force enable
}

# $1: stop at, $2: start at
function configure_hostapd_sleep() {
  local SERVICE_NAME=hostapd@default
  echo -e "${1} /bin/systemctl stop ${SERVICE_NAME}\n${2} /bin/systemctl start ${SERVICE_NAME}\n" >> /etc/crontab
}

# $1: username, $2: timezone, $3: server ip, $4: bridge interface
function install_pihole() {
  local USER_HOME=$(eval echo ~${1})
  local TARGET_DIRECTORY="${USER_HOME}/pihole"
  local WEB_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
  local TIMEZONE=$(echo "${2}" | sed -e 's/\\/\\\\/g; s/\//\\\//g; s/&/\\\&/g')
  local SERVER_IP=$(echo "${3}" | sed -e 's/\./\\\./g')
  mkdir "${TARGET_DIRECTORY}"
  cp ./pihole/{Makefile,ftl-flush.py} "${TARGET_DIRECTORY}/"
  sed \
    -e "s/{TIMEZONE}/${TIMEZONE}/" \
    -e "s/{WEB_PASSWORD}/${WEB_PASSWORD}/" \
    -e "s/{SERVER_IP}/${SERVER_IP}/" \
    -e "s/{INTERFACE}/${4}/" \
    ./pihole/docker-compose.yml > "${TARGET_DIRECTORY}/docker-compose.yml"
  chown -R "${1}:${1}" "${TARGET_DIRECTORY}"
  su ${1} -c "cd '${TARGET_DIRECTORY}' && make"
}

# $1: start at
function configure_pihole_auto_vacuum() {
  echo -e "${1} /usr/bin/docker exec pihole sh -c 'ftl-flush && restartdns'\n" >> /etc/crontab
}

# enabling overlayfs (non-interactively) using this command will also make the
# boot partition to be mounted as ro
# $1: enable|disable
function configure_overlayfs() {
  local FLAG=$(echo ${1} | sed -e 's/\<enable\>/0/' -e 's/\<disable\>/1/')
  raspi-config nonint do_overlayfs "${FLAG}"
}

function install_fsmodesync() {
  install -m 755 ./bin/fsmodesync.sh /usr/local/bin/fsmodesync
}

function install_bootmodesync_service() {
cat <<EOT > /etc/systemd/system/bootmodesync.service
[Unit]
Description=Sync boot partition mount mode with root
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/fsmodesync / /boot rwonly
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOT
  systemctl daemon-reload
}
