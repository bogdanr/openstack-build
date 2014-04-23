#!/bin/bash

set -e
set -x

. 00-configs

GLANCEPASS="`openssl rand -base64 16`"
KEYSTONEPASS="`openssl rand -hex 16`"

setupsql() {

  mysql -e "CREATE DATABASE glance; GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCEPASS';"

}

install() {

  cd glance

  python setup.py install

  useradd -s /bin/false -d /var/lib/glance -m glance
  mkdir -p /etc/glance
  touch /var/log/openstack/glance-{api,registry}.log

  cp etc/glance-* etc/*.json /etc/glance/

  chown -R glance /etc/glance /var/log/openstack/glance-*

  REGISTRYCONF=/etc/glance/glance-registry.conf
  APICONF=/etc/glance/glance-api.conf

  sed -i "s,#connection = <None>,connection = mysql://glance:$GLANCEPASS@127.0.0.1/glance," $REGISTRYCONF
  unset GLANCEPASS

  sed -i "s,%SERVICE_TENANT_NAME%,service," $REGISTRYCONF
  sed -i "s,%SERVICE_USER%,glance," $REGISTRYCONF
  sed -i "s,%SERVICE_PASSWORD%,$KEYSTONEPASS," $REGISTRYCONF
  sed -i "s,#flavor=,flavor = keystone," $REGISTRYCONF
  sed -i "s,log_file = /var/log/glance/registry.log,log_file = /var/log/openstack/glance-registry.log," $REGISTRYCONF

  sed -i "s,%SERVICE_TENANT_NAME%,service," $APICONF
  sed -i "s,%SERVICE_USER%,glance," $APICONF
  sed -i "s,%SERVICE_PASSWORD%,$KEYSTONEPASS," $APICONF
  sed -i "s,#flavor=,flavor = keystone," $APICONF
  sed -i "s,log_file = /var/log/glance/api.log,log_file = /var/log/openstack/glance-api.log," $APICONF

  su -s /bin/sh -c "glance-manage db_sync" glance

  export OS_SERVICE_ENDPOINT=http://$CONTROLLER_IP:35357/v2.0
  export OS_SERVICE_TOKEN=`awk -F '=' '/admin_token=/ {print $2}' /etc/keystone/keystone.conf`

  keystone user-create --name=glance --pass=$KEYSTONEPASS --email=glance@example.com
  keystone user-role-add --user=glance --tenant=service --role=admin

  keystone service-create --name=glance --type=image --description="Box Appliances Image Service"
  keystone endpoint-create --service-id=$(keystone service-list | awk '/ image / {print $2}') --publicurl=http://$CONTROLLER_IP:9292 --internalurl=http://$CONTROLLER_IP:9292 --adminurl=http://$CONTROLLER_IP:9292

  glance-control all start
}

validate() {

  . admin-openrc.sh
  pip install python-glanceclient
  glance image-create --name=CirrOS --disk-format=qcow2 --container-format=bare --is-public=true < TEST/cirros-0.3.2-x86_64-disk.img
  glance image-list

}

clean() {

  mysql -e "DROP DATABASE glance;"
  rm -r /etc/glance
  userdel -r glance

}

if [[ ! -d /var/lib/mysql/glance/ ]]; then
  setupsql
fi

if [[ ! -f $REGISTYCONF ]]; then
  install
fi

validate
