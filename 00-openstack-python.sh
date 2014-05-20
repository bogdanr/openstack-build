#!/bin/bash
set -e

PKG="/tmp/openstack-python"

easy_install pip

build-requirements() {

  cat {keystone,glance,nova,horizon}/requirements.txt | grep -vE "^#" | sort | uniq > requirements-all.txt

  rm -rf $PKG
  mkdir -p $PKG/var/www

  pip install --root=$PKG MySQL-python	# This requires MySQL or MariaDB to be installed
  pip install --root=$PKG tox==1.6.1
  pip install --root=$PKG -r requirements-all.txt
  pip install --root=$PKG libvirt-python

}

build-openstack() {

  for package in keystone glance nova horizon; do
    cd $package
    rm -rf {build,*.egg-info,MANIFEST}
    find -name '*.pyc' -delete
    python setup.py install --root $PKG
    cd ..
  done

  mv $PKG/usr/lib64/python2.7/site-packages/openstack_dashboard $PKG/var/www

}

build-requirements
build-openstack

dir2lzm $PKG

