#!/usr/bin/env bash

./check_dependencies.sh
./create_pki_certs.sh
./create_pki.sh
./create_keys.sh
./create_vm.sh