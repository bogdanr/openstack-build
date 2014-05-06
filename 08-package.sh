#!/bin/bash

set -e
set -x

PKGCTL=openstack-controller
PKGCOM=openstack-compute

# This will be used for testing faster
PKGCTL=openstack-etc

setup-keystone() {

  mkdir -p $PKGCTL/etc/keystone/ssl/{private,certs} $PKGCTL/var/log/openstack
  touch $PKGCTL/var/log/openstack/keystone.log
  cp openstack-files/openssl.conf $PKGCTL/etc/keystone/ssl/certs/
  chown -R keystone $PKGCTL/etc/keystone/ $PKGCTL/var/log/openstack/keystone.log

  KCONF="$PKGCTL/etc/keystone/keystone.conf"
  cp keystone/etc/keystone.conf.sample $KCONF
  cp keystone/etc/keystone-paste.ini keystone/etc/policy.json $PKGCTL/etc/keystone/
  sed -i "s,#connection=<None>,connection = mysql://keystone:`openssl rand -base64 16`@127.0.0.1/keystone," $KCONF

  sed -i "s,#admin_token=ADMIN,admin_token=`openssl rand -hex 10`," $KCONF

  sed -i "s,#log_dir=<None>,log_dir=/var/log/openstack," $KCONF
  sed -i "s,#log_file=<None>,log_file=keystone.log," $KCONF

  # This must happen at first boot or factory reset
  # keystone-manage db_sync
  # su -s /bin/sh -c 'exec keystone-manage pki_setup' keystone

}

setup-glance() {

  mkdir -p $PKGCTL/etc/glance $PKGCTL/var/log/openstack
  touch $PKGCTL/var/log/openstack/glance-{api,registry}.log

  cp glance/etc/glance-* glance/etc/*.json $PKGCTL/etc/glance/

  chown -R glance $PKGCTL/etc/glance $PKGCTL/var/log/openstack/glance-*

  GREGISTRYCONF=$PKGCTL/etc/glance/glance-registry.conf
  GAPICONF=$PKGCTL/etc/glance/glance-api.conf

  sed -i "s,#connection = <None>,connection = mysql://glance:`openssl rand -base64 16`@127.0.0.1/glance," $GREGISTRYCONF

  sed -i "s,%SERVICE_TENANT_NAME%,service," $GREGISTRYCONF
  sed -i "s,%SERVICE_USER%,glance," $GREGISTRYCONF
  sed -i "s,%SERVICE_PASSWORD%,$KEYSTONEPASS," $GREGISTRYCONF
  sed -i "s,#flavor=,flavor = keystone," $GREGISTRYCONF
  sed -i "s,log_file = /var/log/glance/registry.log,log_file = /var/log/openstack/glance-registry.log," $GREGISTRYCONF

  sed -i "s,%SERVICE_TENANT_NAME%,service," $GAPICONF
  sed -i "s,%SERVICE_USER%,glance," $GAPICONF
  sed -i "s,%SERVICE_PASSWORD%,`openssl rand -hex 16`," $GAPICONF
  sed -i "s,#flavor=,flavor = keystone," $GAPICONF
  sed -i "s,log_file = /var/log/glance/api.log,log_file = /var/log/openstack/glance-api.log," $GAPICONF

}

setup-controller() {

  rm -rf $PKGCTL /tmp/$PKGCTL
  mkdir -p $PKGCTL /tmp/$PKGCTL

  wget -P /tmp/$PKGCTL http://packages.nimblex.net/nimblex/mariadb-5.5.37-x86_64-1.txz
  wget -P /tmp/$PKGCTL http://packages.nimblex.net/nimblex/erlang-otp-16B03-x86_64-1.txz
  wget -P /tmp/$PKGCTL http://packages.nimblex.net/nimblex/rabbitmq-server-3.3.1-x86_64-1.txz
  wget -P /tmp/$PKGCTL http://packages.nimblex.net/slackware64/slackware64/n/ntp-4.2.6p5-x86_64-5.txz

  installpkg -root $PKGCTL /tmp/$PKGCTL/*.txz

  # Clean up a little
  find $PKGCTL -type d -name examples -o -name src -o -name include | xargs rm -rf

  # Config for the persistant MySQL datadir
  # cp openstack-files/datadir.cnf $PKGCTL/etc/my.cnf.d/
  cp openstack-files/utf8.cnf $PKGCTL/etc/my.cnf.d/
  cp openstack-files/rabbitmq-env.conf $PKGCTL/etc/rabbitmq/

  # We start services by defautl if this package is loaded.
  mkdir -p $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/mysqld.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/rabbitmq.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/ntp-client.service $PKGCTL/etc/systemd/system/multi-user.target.wants/

  setup-keystone
  setup-glance

}


setup-compute() {

  rm -rf $PKGCOM
  mkdir -p $PKGCOM

  wget -P /tmp/$PKGCTL http://packages.nimblex.net/slackware64/slackware64/n/ntp-4.2.6p5-x86_64-5.txz

  # We start services by defautl if this package is loaded.
  mkdir -p $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/ntp-client.service $PKGCTL/etc/systemd/system/multi-user.target.wants/

}

boot-test() {

  AUFS="aufs-temp"
  mkdir -p $AUFS /tmp/openstack-mem
  umount $AUFS
  umount /tmp/openstack-mem
  mount -t tmpfs -o size=200m tmpfs /tmp/openstack-mem/
  mount -t aufs -o xino=/mnt/live/memory/aufs.xino,br:/tmp/openstack-mem none $AUFS
  mount -t aufs -o remount,append:$PKGCTL=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/virtualization-backend.lzm=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/openstack-python.lzm=ro none $AUFS
  mount -t aufs -o remount,append:/mnt/live/memory/bundles/01-Core64.lzm=ro none $AUFS

  systemd-nspawn -bD $AUFS

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
	  [[ -d $PKGCTL ]] && rm -r $PKGCTL
          setup-keystone
	  setup-glance
          echo "...TESTING"
          boot-test
         ;;
        esac
        echo -e "\n $0 \033[7m DONE \033[0m \n"
fi
