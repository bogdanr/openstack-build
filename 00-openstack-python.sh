#!/bin/bash
set -e

PKG="/tmp/openstack-python"

easy_install pip

workaround() {

sed -i 's/oslo.i18n<1.6.0,>=1.5.0/oslo.i18n<2.6.0,>=2.5.0/' requirements-all.txt
sed -i 's/oslo.serialization<1.5.0,>=1.4.0/oslo.serialization<1.9.0,>=1.8.0/' requirements-all.txt
sed -i 's/python-keystoneclient<1.4.0,>=1.2.0/python-keystoneclient<1.4.0,>=1.3.2/' requirements-all.txt
sed -i 's/python-novaclient>=2.22.0,<2.24.0/python-novaclient>=2.26.0,<2.27.0/' requirements-all.txt
sed -i 's/python-neutronclient<2.5.0,>=2.4.0/python-neutronclient<2.7.0,>=2.6.0/' requirements-all.txt
sed -i 's/python-cinderclient<1.2.0,>=1.1.0/python-cinderclient<1.4.0,>=1.3.1/' requirements-all.txt
sed -i 's/python-glanceclient<0.18.0,>=0.15.0/python-glanceclient<0.19.1,>=0.19.0/' requirements-all.txt
sed -i 's/oslo.config<1.10.0,>=1.9.3/oslo.config<2.4.0,>=2.3.0/' requirements-all.txt
sed -i 's/oslo.utils<1.5.0,>=1.4.0/oslo.utils<2.5.0,>=2.4.0/' requirements-all.txt
sed -i 's/pbr!=0.7,<1.0,>=0.6/pbr!=0.7,<1.7,>=1.4/' requirements-all.txt
sed -i 's/python-keystoneclient<1.4.0,>=1.3.2/python-keystoneclient<1.8.0,>=1.6.0/' requirements-all.txt
sed -i 's/stevedore<1.4.0,>=1.3.0/stevedore<1.8.0,>=1.7.0/' requirements-all.txt

}

build-requirements() {

  cat {keystone,glance,nova,horizon}/requirements.txt | grep -vE "^#" | sort | uniq > requirements-all.txt

  rm -rf $PKG
  mkdir -p $PKG/var/www

  workaround

  pip install --root=$PKG -I MySQL-python	# This requires MySQL or MariaDB to be installed
  pip install --root=$PKG -I ndg-httpsclient
#  pip install --root=$PKG tox==1.6.1
  pip install --root=$PKG -I tox
  pip install --root=$PKG -I -r requirements-all.txt
  pip install --root=$PKG -I libvirt-python
  pip install --root=$PKG -I python-openstackclient

}

build-openstack() {

  for package in keystone glance nova horizon; do
    cd $package
    rm -rf {build,*.egg-info,MANIFEST}
    find -name '*.pyc' -delete
    python setup.py install --root $PKG
    cd ..
  done

#  mv $PKG/usr/lib64/python2.7/site-packages/openstack_dashboard $PKG/var/www

}

build-requirements
build-openstack

dir2lzm $PKG

