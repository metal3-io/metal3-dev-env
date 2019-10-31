#!/usr/bin/python

from ipaddress import IPv4Address
import sys
dhcp_range=unicode(sys.argv[2]).split(',')
if IPv4Address(dhcp_range[0]) <= IPv4Address(unicode(sys.argv[1])) <= IPv4Address(dhcp_range[1]):
  sys.exit(0)
else:
  sys.exit(1)
