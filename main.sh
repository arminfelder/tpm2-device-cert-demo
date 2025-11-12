#!/usr/bin/env bash

./check_dependencies.sh
echo "create PKI root certs"
./create_pki_certs.sh
echo "create PKI server"
./create_pki.sh
echo "create MQTT broker certs"
./create_broker_certs.sh
echo "create MQTT broker"
./create_broker.sh
echo "create VM"
./create_vm.sh