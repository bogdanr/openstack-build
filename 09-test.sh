#!/bin/bash

nova keypair-add --pub-key ~/.ssh/id_rsa.pub Bogdan-key

nova boot --flavor m1.tiny --image CirrOS --nic net-id=`nova net-list | awk '/demo-net/ {print $2}'` --security-group default --key-name Bogdan-key demo-instance1

nova list

nova get-vnc-console demo-instance1 novnc

nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
