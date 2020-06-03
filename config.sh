#!/usr/bin/env false

STORAGE_PARTITION=/dev/mmcblk0p3
STORAGE_PATH=/data

HOSTNAME=raspi-router
LOCALE=en_US.UTF-8
KEYBOARD_LAYOUT=us
# print all timezones by running: timedatectl list-timezones
TIMEZONE=

DISABLE_ROOT=yes
USERNAME=router

# ethernet device to share connection via cable
ETHX0_MAC=
# wireless device that will be used for hostapd
WLNX0_MAC=
# wireless device that connects to the internet
WLNX1_MAC=

BRDX0_ADDRESS=10.0.0.1
BRDX0_NETMASK=255.255.255.0

HOSTAPD_SSID=raspi-router
HOSTAPD_PWD=
# scanned automatically if HOSTAPD_CHANNEL is empty and HOSTAPD_FREQ=2GHz
HOSTAPD_CHANNEL=
# 2GHz, 5GHz
HOSTAPD_FREQ=2GHz

# stop hostapd and start it again at a specific time?
HOSTAPD_SLEEP=no
# https://stackoverflow.com/a/35575322
HOSTAPD_STOP_AT="0 2 * * *"
HOSTAPD_START_AT="0 8 * * *"

INSTALL_DOCKER=yes
DOCKER_DATA_PATH=${STORAGE_PATH}/var/lib
# https://docs.docker.com/engine/install/debian/#install-using-the-repository
DOCKER_FINGERPRINT="9DC8 5822 9FC7 DD38 854A  E2D8 8D81 803C 0EBF CD88"

INSTALL_PIHOLE=yes
# one week is hardcoded atm, edit ftl-flush.py to change this behavior
PIHOLE_AUTO_VACUUM=yes
# this is just the time when the vacuum task is gonna start
PIHOLE_VACUUM_AT="10 2 * * *"

# remove installation directory after installation is complete?
REMOVE_AFTER_INSTALL=yes
