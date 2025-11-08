#!/usr/bin/env bash

./check_dependencies.sh
./create_pki_certs.sh
./create_pki.sh
./create_broker_certs.sh
./create_broker.sh
./create_vm.sh