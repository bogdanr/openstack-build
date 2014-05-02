#!/bin/bash

set -e
set -x

. 00-configs

. admin-openrc.sh

NOVAPASS="`openssl rand -base64 16`"
KEYSTONEPASS="`openssl rand -hex 16`"

setupsql() {

  mysql -e "CREATE DATABASE nova; GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVAPASS'; FLUSH PRIVILEGES;"

}

install() {


  cd nova

  python setup.py install

  useradd -s /bin/false -d /var/lib/nova -m nova
  mkdir -p /etc/nova
  touch /var/log/openstack/nova.log

  pip install tox==1.6.1

  NOVACONF=/etc/nova/nova.conf

  cp etc/nova/nova.conf.sample $NOVACONF
  cp etc/nova/*.json /etc/nova/
  cp etc/nova/api-paste.ini /etc/nova/

  chown -R nova /etc/nova /var/log/openstack/nova*

  # This should be owned and only writable by root
  cp -a etc/nova/rootwrap.d /etc/nova

  sed -i "s,#connection=<None>,connection = mysql://nova:$NOVAPASS@$CONTROLLER_IP/nova," $NOVACONF
  unset NOVAPASS

  sed -i "s,#rabbit_host=nova,rabbit_host = $CONTROLLER_IP," $NOVACONF
  sed -i "s,#my_ip=10.0.0.1,my_ip = $CONTROLLER_IP," $NOVACONF	#FIXME: This is stupid but works for testing on one machine :)
  sed -i "s,#vncserver_listen=127.0.0.1,vncserver_listen = $CONTROLLER_IP," $NOVACONF
  sed -i "s,#vncserver_proxyclient_address=127.0.0.1,vncserver_proxyclient_address = $CONTROLLER_IP," $NOVACONF	#FIXME: Same as my_ip

  sed -i "s,#log_file=<None>,log_file = /var/log/openstack/nova.log," $NOVACONF
  sed -i "s,#lock_path=<None>,lock_path = /var/lib/nova/," $NOVACONF

  su -s /bin/sh -c "nova-manage db sync" nova

  sed -i "s,#auth_strategy=noauth,auth_strategy = keystone," $NOVACONF
  sed -i "s,#auth_uri=<None>,auth_uri = http://$CONTROLLER_IP:5000," $NOVACONF
  sed -i "s,#identity_uri=<None>,identity_uri = http://$CONTROLLER_IP:35357," $NOVACONF

  sed -i "s,#admin_user=<None>,admin_user = nova," $NOVACONF
  sed -i "s,#admin_password=<None>,admin_password = $KEYSTONEPASS," $NOVACONF
  sed -i "s,#admin_tenant_name=admin,admin_tenant_name = service," $NOVACONF

  # These are only needed for compute nodes
  sed -i "s,#glance_host=\$my_ip,glance_host = $CONTROLLER_IP," $NOVACONF
  sed -i "s,#novncproxy_base_url=http://127.0.0.1:6080/vnc_auto.html,novncproxy_base_url = http://$CONTROLLER_IP:6080/vnc_auto.html," $NOVACONF
  sed -i "s,#compute_driver=<None>,compute_driver = libvirt.LibvirtDriver," $NOVACONF
  sed -i "s,#state_path=\$pybasedir,state_path = /var/lib/nova," $NOVACONF
  mkdir -p /var/lib/nova/instances
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

}

keystone-add() {

  keystone user-create --name=nova --pass=$KEYSTONEPASS --email=nova@example.com
  keystone user-role-add --user=nova --tenant=service --role=admin

  keystone service-create --name=nova --type=compute --description="Box Appliances Compute"
  keystone endpoint-create --service-id=$(keystone service-list | awk '/ compute / {print $2}') --publicurl=http://$CONTROLLER_IP:8774/v2/%\(tenant_id\)s --internalurl=http://$CONTROLLER_IP:8774/v2/%\(tenant_id\)s --adminurl=http://$CONTROLLER_IP:8774/v2/%\(tenant_id\)s

}

legacy-netcfg() {

  sed -i "s,#network_api_class=nova.network.api.API,network_api_class = nova.network.api.API," $NOVACONF
  sed -i "s,#security_group_api=nova,security_group_api = nova," /etc/nova/nova.conf $NOVACONF

}

legacy-netadd() {

#  nova network-create demo-net --bridge br100 --multi-host T --fixed-range-v4 203.0.113.24/29
  nova network-create demo-net --bridge-interface=enp5s0 --bridge br100 --multi-host T --fixed-range-v4 10.0.113.0/24

}

validate() {

  pip install python-novaclient
  nova image-list
  nova net-list

}

clean() {

  mysql -e "DROP DATABASE nova; DROP USER nova@'localhost';"
  rm -r /etc/nova/
  userdel -r nova

}

if [[ $1 = "clean" ]]; then
  clean
fi

if [[ ! -d /var/lib/mysql/nova/ ]]; then
  setupsql
fi

if [[ ! -f /etc/nova/nova.conf ]]; then
  install
  legacy-netcfg
fi

if ! keystone endpoint-list | grep -w 8774; then
  keystone-add
fi

if ! pgrep nova-api >/dev/null ; then
  nova-api &
  # From here on we should be having RabbitMQ running properly
  nova-cert &
  nova-consoleauth &
  nova-scheduler &
  nova-conductor &
  nova-network &
  nova-novncproxy &
  sleep 10
  legacy-netadd
fi

# This should make it sufficient to run the script again after installing to see if all went fine.
if ! validate; then
  echo -e "\n===== Nova was not installed correctly! =====\n"
fi

