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

setup-nova() {

  mkdir -p $PKGCTL/etc/{nova,sudoers.d} $PKGCTL/var/log/openstack $PKGCTL/var/lib/nova/instances
  touch $PKGCTL/var/log/openstack/nova.log

  NOVACONF=$PKGCTL/etc/nova/nova.conf
  KEYSTONEPASS="`openssl rand -hex 16`"
  CONTROLLER_IP=127.0.0.1	#FIXME

  cp nova/etc/nova/nova.conf.sample $NOVACONF
  cp nova/etc/nova/*.json $PKGCTL/etc/nova/
  cp nova/etc/nova/api-paste.ini $PKGCTL/etc/nova/

  grep -wq nova /etc/passwd || useradd -r nova
  chown -R nova $PKGCTL/etc/nova $PKGCTL/var/log/openstack/nova.log $PKGCTL/var/lib/nova/instances

  # This should be owned and only writable by root
  cp -a nova/etc/nova/{rootwrap.d,rootwrap.conf} $PKGCTL/etc/nova
  echo 'nova ALL = (root) NOPASSWD: /usr/bin/nova-rootwrap /etc/nova/rootwrap.conf *' > $PKGCTL/etc/sudoers.d/openstack

  sed -i "s,#connection=<None>,connection = mysql://nova:`openssl rand -base64 16`@$CONTROLLER_IP/nova," $NOVACONF

  sed -i "s,#rabbit_host=nova,rabbit_host = $CONTROLLER_IP," $NOVACONF
  sed -i "s,#my_ip=10.0.0.1,my_ip = $CONTROLLER_IP," $NOVACONF	#FIXME: This is stupid but works for testing on one machine :)
  sed -i "s,#vncserver_listen=127.0.0.1,vncserver_listen = $CONTROLLER_IP," $NOVACONF
  sed -i "s,#vncserver_proxyclient_address=127.0.0.1,vncserver_proxyclient_address = $CONTROLLER_IP," $NOVACONF	#FIXME: Same as my_ip

  sed -i "s,#log_file=<None>,log_file = /var/log/openstack/nova.log," $NOVACONF
  sed -i "s,#lock_path=<None>,lock_path = /var/lib/nova/," $NOVACONF

  sed -i "s,#auth_strategy=noauth,auth_strategy = keystone," $NOVACONF
  sed -i "s,#auth_uri=<None>,auth_uri = http://$CONTROLLER_IP:5000," $NOVACONF
  sed -i "s,#identity_uri=<None>,identity_uri = http://$CONTROLLER_IP:35357," $NOVACONF

  sed -i "s,#admin_user=<None>,admin_user = nova," $NOVACONF
  sed -i "s,#admin_password=<None>,admin_password = $KEYSTONEPASS," $NOVACONF
  sed -i "s,#admin_tenant_name=admin,admin_tenant_name = service," $NOVACONF

  # We'll stick to nova-network for now
  sed -i "s,#network_api_class=nova.network.api.API,network_api_class = nova.network.api.API," $NOVACONF
  sed -i "s,#security_group_api=nova,security_group_api = nova," $NOVACONF

  # These are only needed for compute nodes
  sed -i "s,#glance_host=\$my_ip,glance_host = $CONTROLLER_IP," $NOVACONF
  sed -i "s,#novncproxy_base_url=http://127.0.0.1:6080/vnc_auto.html,novncproxy_base_url = http://$CONTROLLER_IP:6080/vnc_auto.html," $NOVACONF
  sed -i "s,#compute_driver=<None>,compute_driver = libvirt.LibvirtDriver," $NOVACONF
  sed -i "s,#state_path=\$pybasedir,state_path = /var/lib/nova," $NOVACONF
  # mkdir -p /var/lib/nova/instances # Kept here just as a reference that it's needed for compute nodes.
  sed -i "s,#firewall_driver=<None>,firewall_driver = nova.virt.libvirt.firewall.IptablesFirewallDriver," $NOVACONF
  sed -i "s,#network_manager=nova.network.manager.VlanManager,network_manager = nova.network.manager.FlatDHCPManager," $NOVACONF
  sed -i "s,#network_size=256,network_size = 254," $NOVACONF
  sed -i "s,#allow_same_net_traffic=true,allow_same_net_traffic = False," $NOVACONF
  sed -i "s,#multi_host=false,multi_host = True," $NOVACONF
  sed -i "s,#send_arp_for_ha=false,send_arp_for_ha = True," $NOVACONF
  sed -i "s,#share_dhcp_address=false,share_dhcp_address = True," $NOVACONF
  sed -i "s,#force_dhcp_release=true,force_dhcp_release = True," $NOVACONF
  sed -i "s,#flat_network_bridge=<None>,flat_network_bridge = br100," $NOVACONF
  sed -i "s,#flat_interface=<None>,flat_interface = $FLAT_IFACE," $NOVACONF
  sed -i "s,#public_interface=eth0,public_interface = $PUB_IFACE," $NOVACONF
  sed -i "s,#bindir=/usr/local/bin,bindir=/usr/bin," $NOVACONF
  sed -i "s,#dhcpbridge_flagfile=/etc/nova/nova-dhcpbridge.conf,dhcpbridge_flagfile = /etc/nova/nova.conf," $NOVACONF

  cp openstack-files/systemd/openstack-nova-*.service $PKGCTL/lib/systemd/system/
  ln -s /lib/systemd/system/openstack-nova-api.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/openstack-nova-cert.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/openstack-nova-consoleauth.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/openstack-nova-scheduler.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/openstack-nova-conductor.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/openstack-nova-network.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  cp openstack-files/nova-systemd-start $PKGCTL/usr/bin/
}

setup-horizon() {
  
  WWW=/var/www
  mkdir -p $PKGCTL/{etc/httpd,$WWW,usr/bin}
  cp -a horizon/openstack_dashboard $PKGCTL$WWW
  cp -a openstack-files/horizon/static/* $PKGCTL$WWW/openstack_dashboard/static/dashboard/
  cp -a openstack-files/horizon/openstack.conf $PKGCTL/etc/httpd/extra/
  ln -s $WWW/openstack_dashboard/static $PKGCTL$WWW/static
  sed "s/#ALLOWED_HOSTS = \['horizon.example.com', \]/ALLOWED_HOSTS = \['*'\]/" $PKGCTL$WWW/openstack_dashboard/local/local_settings.py.example > $PKGCTL$WWW/openstack_dashboard/local/local_settings.py

  cp openstack-files/systemd/httpd.service $PKGCTL/lib/systemd/system/
  cp openstack-files/horizon-systemd-start $PKGCTL/usr/bin/

}

setup-controller() {

  rm -rf $PKGCTL
  mkdir -p $PKGCTL/root/.ssh /tmp/$PKGCTL

  wget -nv -NP /tmp/$PKGCTL http://packages.nimblex.net/nimblex/mariadb-5.5.37-x86_64-1.txz
  wget -nv -NP /tmp/$PKGCTL http://packages.nimblex.net/nimblex/erlang-otp-16B03-x86_64-1.txz
  wget -nv -NP /tmp/$PKGCTL http://packages.nimblex.net/nimblex/rabbitmq-server-3.3.1-x86_64-1.txz
  wget -nv -NP /tmp/$PKGCTL http://packages.nimblex.net/nimblex/mod_wsgi-3.4-x86_64-1.txz
  wget -nv -NP /tmp/$PKGCTL http://packages.nimblex.net/slackware64/slackware64/n/ntp-4.2.6p5-x86_64-5.txz

  installpkg -root $PKGCTL /tmp/$PKGCTL/*.txz

  # Clean up a little
  find $PKGCTL -type d -name examples -o -name src -o -name include | xargs rm -rf

  # We enable connections for containers or others
  sed "s,#pts/0,pts/0," /etc/securetty > $PKGCTL/etc/securetty

  # cp openstack-files/datadir.cnf $PKGCTL/etc/my.cnf.d/
  cp openstack-files/utf8.cnf $PKGCTL/etc/my.cnf.d/
  cp openstack-files/rabbitmq-env.conf $PKGCTL/etc/rabbitmq/
  cp openstack-files/openstack-test $PKGCTL/usr/bin
  cp 00-configs $PKGCTL/etc/openstack-cfg

  # We start services by defautl if this package is loaded.
  mkdir -p $PKGCTL/etc/systemd/system/{multi-user,network-target}.target.wants/
  cp openstack-files/systemd/openstack-users.service $PKGCTL/lib/systemd/system/
  cp openstack-files/systemd/libvirtd.service $PKGCTL/lib/systemd/system/
  ln -s /lib/systemd/system/openstack-users.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/multi-user.target $PKGCTL/etc/systemd/system/default.target
  ln -s /lib/systemd/system/mysqld.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/rabbitmq.service $PKGCTL/etc/systemd/system/multi-user.target.wants/
  ln -s /lib/systemd/system/ntp-client.service $PKGCTL/etc/systemd/system/network-target.target.wants/

  ln -s /lib/systemd/system/sshd.service $PKGCTL/etc/systemd/system/multi-user.target.wants/sshd.service
  #FIXME: The keys generated here should be stored in a persistant location
  ln -s /lib/systemd/system/sshdgenkeys.service $PKGCTL/etc/systemd/system/multi-user.target.wants/sshdgenkeys.service
  cp /root/.ssh/id_rsa.pub $PKGCTL/root/.ssh/authorized_keys

  # Unless we have lots of RAM on the controller or we are testing this should not be enabled
  ln -s /lib/systemd/system/libvirtd.service $PKGCTL/etc/systemd/system/multi-user.target.wants/

  setup-keystone
  setup-glance
  setup-nova
  setup-horizon

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
  cp openstack-files/systemd/libvirtd.service $PKGCTL/lib/systemd/system/
  ln -s /lib/systemd/system/ntp-client.service $PKGCTL/etc/systemd/system/network-target.target.wants/
  ln -s /lib/systemd/system/libvirtd.service $PKGCTL/etc/systemd/system/multi-user.target.wants/

  setup-nova
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
  grep -q ebtables /proc/modules || modprobe ebtables
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
