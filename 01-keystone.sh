#!/bin/bash

set -e
#set -x

. 00-configs

KEYSTONEPASS="`openssl rand -base64 16`"

setupsql() {

  slapt-get -u
  slapt-get -i mariadb
  sed -i 's,SKIP="--skip-networking",# SKIP="--skip-networking",' /etc/rc.d/rc.mysqld
  echo "[mysqld]

  default-storage-engine = innodb
  collation-server = utf8_general_ci
  init-connect = 'SET NAMES utf8'
  character-set-server = utf8
  " > /etc/my.cnf.d/utf8.cnf
  mysql_install_db --user=mysql
  sh /etc/rc.d/rc.mysqld restart

  sleep 5
  mysql -e "CREATE DATABASE keystone; GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONEPASS'; GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONEPASS';"

}

setuprabbit() {

  ( cd /tmp && wget http://packages.nimblex.net/nimblex/rabbitmq-server-3.1.5-x86_64-1.txz && wget http://packages.nimblex.net/nimblex/erlang-otp-16B03-x86_64-1.txz )
  installpkg /tmp/rabbitmq-server-*-x86_64-1.txz
  installpkg /tmp/erlang-otp-*-x86_64-1.txz
  useradd -d /var/lib/rabbitmq/ rabbitmq
  chown rabbitmq /var/{lib,log}/rabbitmq/
  sed -i 's/127.0.0.1/0.0.0.0/' /etc/rabbitmq/rabbitmq-env.conf
  sed -i 's/example/openstack/' /etc/rabbitmq/rabbitmq-env.conf
  chmod +x /etc/rc.d/rc.rabbitmq
  /etc/rc.d/rc.rabbitmq start

}

install() {

  easy_install pip pbr MySQL-python

  cd keystone

  useradd -s /bin/false -d /var/lib/keystone -m keystone

  python setup.py install

  mkdir -p /etc/keystone/ssl/{private,certs} /var/log/openstack
  touch /var/log/openstack/keystone.log
  cp ../openssl.conf /etc/keystone/ssl/certs/
  chown -R keystone /etc/keystone/ /var/log/openstack/keystone.log

  CONF="/etc/keystone/keystone.conf"
  cp etc/keystone.conf.sample $CONF
  cp etc/keystone-paste.ini etc/policy.json /etc/keystone/
  sed -i "s,#connection=<None>,connection = mysql://keystone:$KEYSTONEPASS@127.0.0.1/keystone," $CONF
  unset KEYSTONEPASS

  keystone-manage db_sync
  export OS_SERVICE_TOKEN=`openssl rand -hex 10`
  sed -i "s,#admin_token=ADMIN,admin_token=$OS_SERVICE_TOKEN," $CONF

  sed -i "s,#log_dir=<None>,log_dir=/var/log/openstack," $CONF
  sed -i "s,#log_file=<None>,log_file=keystone.log," $CONF

  su -s /bin/sh -c 'exec keystone-manage pki_setup' keystone

  keystone-all &
  sleep 3

}

configure() {

#	---  Define users, tenants, and roles ---
#	http://docs.openstack.org/icehouse/install-guide/install/apt/content/keystone-users.html

  export OS_SERVICE_ENDPOINT=http://$CONTROLLER_IP:35357/v2.0
  export OS_SERVICE_TOKEN=`awk -F '=' '/admin_token=/ {print $2}' /etc/keystone/keystone.conf`

  keystone user-create --name=admin --pass=$ADMINPASS --email=bogdan@nimblex.net
  keystone role-create --name=admin
  keystone tenant-create --name=admin --description="Admin Tenant"
  sleep 3

  keystone user-role-add --user=admin --tenant=admin --role=admin
  keystone user-role-add --user=admin --role=_member_ --tenant=admin

  keystone user-create --name=demo --pass=demo
  keystone tenant-create --name=demo --description="Demo Tenant"
  keystone user-role-add --user=demo --role=_member_ --tenant=demo
  keystone tenant-create --name=service --description="Service Tenant"

  keystone service-create --name=keystone --type=identity --description="OpenStack Identity"
  keystone endpoint-create --service-id=$(keystone service-list | awk '/ identity / {print $2}') --publicurl=http://$CONTROLLER_IP:5000/v2.0 --internalurl=http://$CONTROLLER_IP:5000/v2.0 --adminurl=http://$CONTROLLER_IP:35357/v2.0

}

validate() {

  keystone --os-username=admin --os-password=$ADMINPASS --os-auth-url=http://$CONTROLLER_IP:35357/v2.0 token-get

}

clean() {

  mysql -e "DROP DATABASE keystone;"
  rm -r /etc/keystone/
  userdel -r keystone

}

if [[ ! -d /var/lib/mysql/mysql/ ]]; then
  setupsql
fi

if [[ ! -f /usr/bin/rabbitmq-server ]]; then
  setuprabbit
fi

if [[ ! -f /etc/keystone/keystone.conf ]]; then
  install
fi

# This should make it sufficient to run the script again after installing to see if all went fine.
if ! validate; then
  configure
fi

echo -e "\n === The password for admin user is $ADMINPASS === \n"
