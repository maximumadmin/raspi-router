# Raspberry Pi Router

> ⚠️ The new network will be isolated from the original network, thus no connectivity with devices connected to the original network will be possible by default ⚠️

```
                               PiHole on Docker
                                      |               Hostapd
                                      |         .- wlnx0
                                      |         |
                                      |         | ethx0 ---------.
                                      |         |                |
Internet ----- Router ------------ Raspberry --brdx0           Client PC
             192.168.1.1       wlnx1         10.0.0.1         10.0.0.5  
                           192.168.1.20             
```

## Requirements

* Any Raspberry Pi with 2 wireless adapters
* [Raspbian](https://www.raspberrypi.org/downloads/raspbian/#:~:text=Raspberry%20Pi%20OS%20(32-bit)%20Lite) Buster (tested with 2020-05-27 release)

## Partitioning

### Wipe microSD card

```bash
sudo wipefs -a -f /dev/sdX
sudo dd if=/dev/zero of=/dev/sdX bs=4096 status=progress
```

### Transfer Raspbian image

```bash
sudo dd bs=4M if=raspbian.img of=/dev/sdX conv=fsync status=progress
```

Example partition layout for different micro sd card sizes (partition sizes below are just recommendations)

```
      Partition :  sdX1   sdX2      sdX3    unpartitioned
        Purpose :  boot   root   storage   wear levelling
Size ( 8GB mSD) :  256M     4G        2G              ~2G
Size (16GB mSD) :  256M     8G        4G              ~4G
Size (32GB mSD) :  256M    10G        6G             ~16G
```

### Adjust image size so there is space left for writable partition and optionally for wear levelling 

```bash
# run fdisk with the sd card device path as parameter
sudo fdisk /dev/sdX

# print partition table and annotate the start sector from the 2nd partition
p

# delete 2nd partition
d,2

# re-create 2nd partition using same start sector and preserve ext4 signature
n, p, 2, START_SECTOR, DESIRED_SIZE, N

# Print partition table and annotate end sector for 2nd partition
p

# create 3rd partition (storage)
n, p, 3, END_SECTOR+1, STORAGE_DESIRED_SIZE

# print partition table and make sure layout is correct
p

# write changes and exit
w
```

### Resize and format file systems (**no** need to disable journaling since overlay will be used for root and we still want reliability for storage)

> Since the partitions were resized, the Pi will display a warning message mentioning that the partition resizing failed (this is expected since we did the resizing manually)

```bash
# check filesystem for new partition
sudo e2fsck -f /dev/sdX2

# resize filesystem
sudo resize2fs /dev/sdX2

# format storage partition
sudo mkfs.ext4 /dev/sdX3
```

## Setup

### On another computer

* Transfer Raspbian image using `dd`
* Partition manually as mentioned above
* Create `ssh` file

### Inside the Pi

* Optional preliminary steps on `raspi-config`
  * Choose the correct WLAN country
  * Change keyboard layout to avoid issues when typing a new password
  * Change the timezone to avoid `apt-get` sync errors
* Connect to the internet so you can download this repository
* Copy or download this repository into any directory on the Pi
* Edit `config.sh` to suit your needs (you can run `install.sh info` to get some useful information)
* Run `install.sh prepare` and reboot
* Run `install.sh install` and reboot

### At the PiHole Web Interface

* (Optional) Configure DHCP at `/admin/settings.php?tab=piholedhcp`
* (Optional) Visit `/admin/settings.php?tab=dns` and set non-ECS upstream DNS server for better privacy
