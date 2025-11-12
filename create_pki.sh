#!/usr/bin/env bash

source vars.sh

function init_server() {
    docker compose up pki-init --force-recreate
}

function start_server() {
    docker compose up pki -d --force-recreate
}


function main() {
    start_server
    init_server
}

main