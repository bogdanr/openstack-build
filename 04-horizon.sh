#!/bin/bash

# Playground to help me figure out how to package horizon

AUFS=aufs-temp
PKGCTL=openstack-etc

PKGHO=/tmp/openstack-horizon

test_horizon-setup() {

mkdir -p $PKGHO/etc/systemd/system/multi-user.target.wants/ $PKGHO/{etc/slapt-get/,var,root}

cd horizon
#pip install --root=$PKGHO test-requirements.txt
python setup.py install --root $PKGHO
cd ..

mv $PKGHO/usr/lib64/python2.7/site-packages/openstack_dashboard/ $PKGHO/var/www
ln -s /lib/systemd/system/httpd.service $PKGHO/etc/systemd/system/multi-user.target.wants/

cp /etc/slapt-get/slapt-getrc $PKGHO/etc/slapt-get/
cp -a /var/slapt-get $PKGHO/var
rm -r horizon/build
cp -a horizon $PKGHO/root

}


boot-test() {

  mkdir -p $AUFS /tmp/openstack-mem $PKGCTL/etc/wicd/scripts/preconnect
  mount -t tmpfs -o size=200m tmpfs /tmp/openstack-mem/
  mount -t aufs -o xino=/mnt/live/memory/aufs.xino,br:/tmp/openstack-mem none $AUFS
  mount -t aufs -o remount,append:$PKGHO=ro none $AUFS
  mount -t aufs -o remount,append:$PKGCTL=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/virtualization-backend.lzm=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/openstack-python.lzm=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/vim-7.4.lzm=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/07-Devel64.lzm=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/02-Xorg64.lzm=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/01-Core64.lzm=ro none $AUFS

  echo 'echo 0 > /var/tmp/promote_secondaries
  mount -o bind /var/tmp/promote_secondaries /proc/sys/net/ipv4/conf/host0/promote_secondaries' > $PKGCTL/etc/wicd/scripts/preconnect/dhcpcd-lxc
  chmod +x $PKGCTL/etc/wicd/scripts/preconnect/dhcpcd-lxc

  # If we have tmux we split it to have another window were we can play
  pgrep tmux >/dev/null && (sleep 5 && tmux split-window -hd "machinectl login aufs-temp")&
  # This should work very nicely if we have libvirtd
  grep -q ebtables /proc/modules || modprobe ebtables
  if ip addr show dev virbr0 >/dev/null; then
    systemd-nspawn --network-bridge=virbr0 -bD $AUFS
  else
    systemd-nspawn --network-veth -bD $AUFS
  fi

}

echo "...PREPARING"
mountpoint -q $AUFS && umount $AUFS
mountpoint -q /tmp/openstack-mem && umount /tmp/openstack-mem
[[ -d $PKGHO ]] && rm -r $PKGHO
test_horizon-setup
echo "...TESTING"
boot-test
