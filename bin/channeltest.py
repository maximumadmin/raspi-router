#!/usr/bin/env python3

import re
import subprocess
import sys
import time
from collections import Counter

# Scan for networks using given interface and return output as string
def scan_networks(interface):
  result = subprocess.run(['iw', 'dev', interface, 'scan'], stdout=subprocess.PIPE)
  return result.stdout.decode()

# Parse the output from the iw command and return the best channel
def parse_output(iw_output, forbidden_channels):
  # Extract channels
  channels = re.findall(r'set\:\schannel\s(\d+)', iw_output, re.M)
  # Count occurrences for each channel
  channel_usage = Counter(channels)

  # Fill missing channels [1, 2, ..., 11]
  for n in range(1, 11 + 1):
    channel = str(n)
    if not channel in channel_usage:
      channel_usage[channel] = 0

  # Less used channel
  best_channel = 0
  best_count = 999

  # Find less used channel
  for chan, count in channel_usage.items():
    channel = int(chan)

    if channel in forbidden_channels:
      continue

    if count < best_count:
      best_channel = channel
      if count == 0:
        break

  return best_channel

# Finds the less used channel given a network interface and a number of scans
def find_best_channel(interface, scan_count, forbidden_channels, delay=0):
  best_channels = []

  for i in range(scan_count):
    output = scan_networks(interface)
    channel = parse_output(output, forbidden_channels)
    best_channels.append(channel)
    if i < scan_count - 1 and delay > 0:
      time.sleep(delay)

  most_common = max(set(best_channels), key=best_channels.count)
  return most_common

if len(sys.argv) < 2:
  print('You must specify a network interface as fist argument')
  sys.exit(1)

# Print best channel
print(find_best_channel(
  sys.argv[1], # interface name
  4,           # number of scans
  [],          # channels to avoid
  2,           # delay between scans in seconds
))
