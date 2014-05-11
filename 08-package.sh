#!/bin/bash

set -e
set -x

AUFS="aufs-temp"
PKGCTL=openstack-controller
PKGCOM=openstack-compute

# This will be used for testing faster
PKGCTL=openstack-etc

setup-keystone() {

  mkdir -p $PKGCTL/etc/keystone/ssl/{private,certs} $PKGCTL/var/log/openstack
  touch $PKGCTL/var/log/openstack/keystone.log
  cp openstack-files/openssl.conf $PKGCTL/etc/keystone/ssl/certs/
  grep -wq keystone /etc/passwd || useradd -r keystone
  chown -R keystone $PKGCTL/etc/keystone/ $PKGCTL/var/log/openstack/keystone.log

  KCONF="$PKGCTL/etc/keystone/keystone.conf"
  cp keystone/etc/keystone.conf.sample $KCONF
  cp keystone/etc/keystone-paste.ini keystone/etc/policy.json $PKGCTL/etc/keystone/
  sed -i "s,#connection=<None>,connection = mysql://keystone:`openssl rand -base64 16`@127.0.0.1/keystone," $KCONF

  sed -i "s,#admin_token=ADMIN,admin_token=`openssl rand -hex 10`," $KCONF

  sed -i "s,#log_dir=<None>,log_dir=/var/log/openstack," $KCONF
  sed -i "s,#log_file=<None>,log_file=keystone.log," $KCONF
  # In the future this will probably be removed but for now works OK
  sed -i "s,#onready=<None>,onready = keystone.common.systemd," $KCONF

  cp openstack-files/systemd/openstack-keystone.service $PKGCTL/lib/systemd/system/
  ln -s /lib/systemd/system/openstack-keystone.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  cp openstack-files/keystone-systemd-start $PKGCTL/usr/bin/

}

setup-glance() {

  mkdir -p $PKGCTL/etc/glance $PKGCTL/var/log/openstack
  touch $PKGCTL/var/log/openstack/glance-{api,registry,scrubber}.log

  cp glance/etc/glance-* glance/etc/*.json $PKGCTL/etc/glance/

  grep -wq glance /etc/passwd || useradd -r glance
  chown -R glance $PKGCTL/etc/glance $PKGCTL/var/log/openstack/glance-*.log

  GREGISTRYCONF=$PKGCTL/etc/glance/glance-registry.conf
  GAPICONF=$PKGCTL/etc/glance/glance-api.conf
  GSCCONF=$PKGCTL/etc/glance/glance-scrubber.conf
  KEYSTONEPASS="`openssl rand -hex 16`"

  sed -i "s,#connection = <None>,connection = mysql://glance:`openssl rand -base64 16`@127.0.0.1/glance," $GREGISTRYCONF

  sed -i "s,%SERVICE_TENANT_NAME%,service," $GREGISTRYCONF
  sed -i "s,%SERVICE_USER%,glance," $GREGISTRYCONF
  sed -i "s,%SERVICE_PASSWORD%,$KEYSTONEPASS," $GREGISTRYCONF
  sed -i "s,#flavor=,flavor = keystone," $GREGISTRYCONF
  sed -i "s,log_file = /var/log/glance/registry.log,log_file = /var/log/openstack/glance-registry.log," $GREGISTRYCONF

  sed -i "s,%SERVICE_TENANT_NAME%,service," $GAPICONF
  sed -i "s,%SERVICE_USER%,glance," $GAPICONF
  sed -i "s,%SERVICE_PASSWORD%,$KEYSTONEPASS," $GAPICONF
  sed -i "s,#flavor=,flavor = keystone," $GAPICONF
  sed -i "s,log_file = /var/log/glance/api.log,log_file = /var/log/openstack/glance-api.log," $GAPICONF

  sed -i "s,log_file = /var/log/glance/scrubber.log,log_file = /var/log/openstack/glance-scrubber.log," $GSCCONF

  cp openstack-files/systemd/openstack-glance-*.service $PKGCTL/lib/systemd/system/
  ln -s /lib/systemd/system/openstack-glance-registry.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/openstack-glance-api.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  # We'll enable the scrubber at a later point when we'll think it helps us. For now we're not using delayed_delete
  # ln -s /lib/systemd/system/openstack-glance-scrubber.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  cp openstack-files/glance-systemd-start $PKGCTL/usr/bin/
}

setup-controller() {

  rm -rf $PKGCTL
  mkdir -p $PKGCTL/root /tmp/$PKGCTL

  wget -nv -NP /tmp/$PKGCTL http://packages.nimblex.net/nimblex/mariadb-5.5.37-x86_64-1.txz
  wget -nv -NP /tmp/$PKGCTL http://packages.nimblex.net/nimblex/erlang-otp-16B03-x86_64-1.txz
  wget -nv -NP /tmp/$PKGCTL http://packages.nimblex.net/nimblex/rabbitmq-server-3.3.1-x86_64-1.txz
  wget -nv -NP /tmp/$PKGCTL http://packages.nimblex.net/slackware64/slackware64/n/ntp-4.2.6p5-x86_64-5.txz

  installpkg -root $PKGCTL /tmp/$PKGCTL/*.txz

  # Clean up a little
  find $PKGCTL -type d -name examples -o -name src -o -name include | xargs rm -rf

  # We enable connections for containers or others
  sed "s,#pts/0,pts/0," /etc/securetty > $PKGCTL/etc/securetty

  # Config for the persistant MySQL datadir
  # cp openstack-files/datadir.cnf $PKGCTL/etc/my.cnf.d/
  cp openstack-files/utf8.cnf $PKGCTL/etc/my.cnf.d/
  cp openstack-files/rabbitmq-env.conf $PKGCTL/etc/rabbitmq/
  cp 00-configs $PKGCTL/etc/openstack-cfg

  # We start services by defautl if this package is loaded.
  mkdir -p $PKGCTL/etc/systemd/system/{multi-user,network-target}.target.wants/
  cp openstack-files/systemd/openstack-users.service $PKGCTL/lib/systemd/system/
  ln -s /lib/systemd/system/openstack-users.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/multi-user.target $PKGCTL/etc/systemd/system/default.target
  ln -s /lib/systemd/system/mysqld.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/rabbitmq.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/ntp-client.service $PKGCTL/etc/systemd/system/network-target.target.wants/

  setup-keystone
  setup-glance

}


setup-compute() {

  rm -rf $PKGCOM
  mkdir -p $PKGCOM

  wget -NP /tmp/$PKGCTL http://packages.nimblex.net/slackware64/slackware64/n/ntp-4.2.6p5-x86_64-5.txz

  installpkg -root $PKGCTL /tmp/$PKGCTL/*.txz
  
  # We enable connections for containers or others
  sed "s,#pts/0,pts/0," /etc/securetty > $PKGCTL/etc/securetty

  # We start services by defautl if this package is loaded.
  mkdir -p $PKGCTL/etc/systemd/system/{multi-user,network-target}.target.wants/
  ln -s /lib/systemd/system/ntp-client.service $PKGCTL/etc/systemd/system/network-target.target.wants/

}

boot-test() {

  mkdir -p $AUFS /tmp/openstack-mem $PKGCTL/etc/wicd/scripts/preconnect
  mount -t tmpfs -o size=200m tmpfs /tmp/openstack-mem/
  mount -t aufs -o xino=/mnt/live/memory/aufs.xino,br:/tmp/openstack-mem none $AUFS
  mount -t aufs -o remount,append:$PKGCTL=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/virtualization-backend.lzm=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/openstack-python.lzm=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/vim-7.4.lzm=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/02-Xorg64.lzm=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/01-Core64.lzm=ro none $AUFS

  echo 'echo 0 > /var/tmp/promote_secondaries
  mount -o bind /var/tmp/promote_secondaries /proc/sys/net/ipv4/conf/host0/promote_secondaries' > $PKGCTL/etc/wicd/scripts/preconnect/dhcpcd-lxc
  chmod +x $PKGCTL/etc/wicd/scripts/preconnect/dhcpcd-lxc

  # If we have tmux we split it to have another window were we can play
  pgrep tmux >/dev/null && (sleep 5 && tmux split-window -hd "machinectl login aufs-temp")&
  # This should work very nicely if we have libvirtd
  if ip addr show dev virbr0 >/dev/null; then
    systemd-nspawn --network-bridge=virbr0 -bD $AUFS
  else
    systemd-nspawn --network-veth -bD $AUFS
  fi

}


if [[ -z $1 ]]; then
        echo "Tell me what to do"
        echo "You options are: package and test"
else
        case $1 in
         "package" )
          echo "...INSTALLING"
	  [[ -d $PKGCTL ]] && rm -r $PKGCTL
          setup-controller
	  dir2lzm $PKGCTL
         ;;
         "test" )
          echo "...PREPARING"
          mountpoint -q $AUFS && umount $AUFS
          mountpoint -q /tmp/openstack-mem && umount /tmp/openstack-mem
	  [[ -d $PKGCTL ]] && rm -r $PKGCTL
          setup-controller
          echo "...TESTING"
          boot-test
         ;;
        esac
        echo -e "\n $0 \033[7m DONE \033[0m \n"
fi
