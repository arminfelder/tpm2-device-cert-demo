#!/usr/bin/env bash

source vars.sh

function start_server() {
    docker compose up mqtt-broker mqtt-init -d --force-recreate
}


function main() {
    start_server
}

main