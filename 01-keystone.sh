#!/bin/bash

set -e
set -x

KEYSTONEPASS="`openssl rand -base64 16`"
ADMINPASS="AnaAre3Mere"

install() {

  cd keystone

  easy_install pip pbr MySQL-python

  python setup.py install

  ( cd /tmp && wget http://packages.nimblex.net/nimblex/rabbitmq-server-3.1.5-x86_64-1.txz && installpkg rabbitmq-server-3.1.5-x86_64-1.txz )

  mkdir -p /etc/keystone/ssl/{private,certs} /var/log/openstack

  CONF="/etc/keystone/keystone.conf"
  cp etc/keystone.conf.sample $CONF
  cp etc/keystone-paste.ini /etc/keystone/
  sed -i "s,#connection=<None>,connection = mysql://keystone:$KEYSTONEPASS@127.0.0.1/keystone," $CONF

  keystone-manage db_sync
  export OS_SERVICE_TOKEN=`openssl rand -hex 10`
  sed -i "s,#admin_token=ADMIN,admin_token=$OS_SERVICE_TOKEN," $CONF

  sed -i "s,#log_dir=<None>,log_dir=/var/log/openstack," $CONF
  sed -i "s,#log_file=<None>,log_file=keystone.log," $CONF

  keystone-all &
  sleep 1

}

setupsql() {

  slapt-get -u
  slapt-get -i mariadb
  sed -i 's,SKIP="--skip-networking",# SKIP="--skip-networking",' /etc/rc.d/rc.mysqld
  mysql_install_db --user=mysql
  sh /etc/rc.d/rc.mysqld restart

  sleep 5
  mysql -e "CREATE DATABASE keystone; GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONEPASS'; GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONEPASS';"

}

configure() {

#	---  Define users, tenants, and roles ---
#	http://docs.openstack.org/icehouse/install-guide/install/apt/content/keystone-users.html

  export OS_SERVICE_ENDPOINT=http://127.0.0.1:35357/v2.0
  export OS_SERVICE_TOKEN=`awk -F '=' '/admin_token=/ {print $2}' /etc/keystone/keystone.conf`

  keystone user-create --name=admin --pass=$ADMINPASS --email=bogdan@nimblex.net
  keystone role-create --name=admin
  keystone tenant-create --name=admin --description="Admin Tenant"
  keystone user-role-add --user=admin --tenant=admin --role=admin
  keystone user-role-add --user=admin --role=_member_ --tenant=admin

  keystone user-create --name=demo --pass=demo
  keystone tenant-create --name=demo --description="Demo Tenant"
  keystone user-role-add --user=demo --role=_member_ --tenant=demo
  keystone tenant-create --name=service --description="Service Tenant"

  keystone service-create --name=keystone --type=identity --description="OpenStack Identity"
  keystone endpoint-create --service-id=$(keystone service-list | awk '/ identity / {print $2}') --publicurl=http://127.0.0.1:5000/v2.0 --internalurl=http://127.0.0.1:5000/v2.0 --adminurl=http://127.0.0.1:35357/v2.0

	# Before we can test we need to set PKI
	# http://docs.openstack.org/developer/keystone/configuration.html#certificates-for-pki

}

validate() {

  keystone --os-username=admin --os-password=$ADMINPASS --os-auth-url=http://127.0.0.1:35357/v2.0 token-get

}

clean() {

  rm -r /etc/keystone/
  sh /etc/rc.d/rc.mysqld stop
  rm -r /var/lib/mysql/*

}

if [[ ! -d /var/lib/mysql/mysql/ ]]; then
  setupsql
fi

if [[ ! -f /etc/keystone/keystone.conf ]]; then
  install
fi

configure

validate

echo -e "\n === The password for admin user is $ADMINPASS ==="
