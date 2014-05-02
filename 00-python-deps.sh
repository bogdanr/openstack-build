#!/bin/bash
set -e

PKG="/tmp/python-openstack"

cat {keystone,glance,nova,horizon}/requirements.txt | grep -vE "^#" | sort | uniq > requirements-all.txt

rm -rf $PKG
mkdir $PKG

pip install --root=$PKG -r requirements-all.txt
pip install --root=$PKG libvirt-python

dir2lzm $PKG

