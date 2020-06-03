#!/usr/bin/python3

import sqlite3
from datetime import date
from datetime import datetime
from datetime import timedelta

def get_timestamp(date_object):
  return round(date_object.timestamp())

def last_week_timestamp():
  today = datetime.today()
  last_week = today - timedelta(days=7)
  return round(last_week.timestamp())

conn = sqlite3.connect('/etc/pihole/pihole-FTL.db')
c = conn.cursor()
# c.execute('DELETE FROM queries WHERE timestamp < {}'.format(get_timestamp(datetime.today())))
c.execute('DELETE FROM queries WHERE timestamp < {}'.format(last_week_timestamp()))
conn.commit()
