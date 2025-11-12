#!/usr/bin/env bash

source vars.sh

function init_server() {
    docker compose up mqtt-init --force-recreate
}

function start_server() {
    docker compose up mqtt-broker -d --force-recreate
}


function main() {
    init_server
    start_server
}

main