#!/bin/bash

: '
    Copyright (C) 2021 IBM Corporation
    Rafael Sene <rpsene@br.ibm.com> - Initial implementation.
'

# Trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
    echo "bye!"
    exit 1
}

SERVER_NAME=""

function check_dependencies() {

    DEPENDENCIES=(ibmcloud jq)
    check_connectivity
    for i in "${DEPENDENCIES[@]}"
    do
        if ! command -v "$i" &> /dev/null; then
            echo "$i could not be found, exiting!"
            exit 1
        fi
    done
}

function check_connectivity() {

    if ! curl --output /dev/null --silent --head --fail http://cloud.ibm.com; then
        echo
        echo "ERROR: please, check your internet connection."
        exit 1
    fi
}

function authenticate() {
    
    local APY_KEY="$1"
    
    if [ -z "$APY_KEY" ]; then
        echo "API KEY was not set."
        exit
    fi
    ibmcloud login --no-region --apikey $APY_KEY
}

function set_powervs() {
    
    local CRN="$1"
    
    if [ -z "$CRN" ]; then
        echo "CRN was not set."
        exit
    fi
    ibmcloud pi st "$CRN"
}

function create_server () {

    local SERVER_ID=$1
    local SERVER_IMAGE=$2
    local PUBLIC_NETWORK=$3
    local SSH_KEY_NAME=$4

    # Default values.
    local SERVER_MEMORY=$5
    local SERVER_PROCESSOR=$6
    local SERVER_SYS_TYPE=$7

    local SSH_USER=$8

    ibmcloud pi instance-create "$SERVER_NAME" --image "$SERVER_IMAGE" --memory "$SERVER_MEMORY" --network "$PUBLIC_NETWORK" --processors "$SERVER_PROCESSOR" --processor-type shared --key-name "$SSH_KEY_NAME" --sys-type "$SERVER_SYS_TYPE" --json >> server.log | tee

    SERVER_ID=$(jq -r ".[].pvmInstanceID" < ./server.log)
    SERVER_NAME=$(jq -r ".[].serverName" < ./server.log)

    echo "  $SERVER_NAME was created with the ID $SERVER_ID"

    echo "SERVER_ID=$SERVER_ID" >> ./server-build.log
    echo "SERVER_NAME=$SERVER_NAME" >> ./server-build.log

    echo "  deploying the server $SERVER_NAME, hold on please."
    STATUS=$(ibmcloud pi in "$SERVER_ID" --json | jq -r ".status")

    printf "%c" "    "
    while [[ "$STATUS" != "ACTIVE" ]]
    do
        sleep 5s
        STATUS=$(ibmcloud pi in "$SERVER_ID" --json | jq -r ".status")
        printf "%c" "."
    done

    if [[ "$STATUS" == "ERROR" ]]; then
        echo "ERROR: a new VM could not be created, destroy the allocated resources..."
        ibmcloud pi instance-delete "$SERVER_ID"
    fi

    if [[ "$STATUS" == "ACTIVE" ]]; then
        echo
        echo "  $SERVER_NAME is now ACTIVE."
        echo "  waiting for the network availability, hold on please."

        EXTERNAL_IP=$(ibmcloud pi in "$SERVER_ID" --json | jq -r '.addresses[0].externalIP')
        printf "%c" "    "
        while [[ -z "$EXTERNAL_IP" ]]; do
            printf "%c" "."
            EXTERNAL_IP=$(ibmcloud pi in "$SERVER_ID" --json | jq -r '.addresses[0].externalIP')
            INTERNAL_IP=$(ibmcloud pi in "$SERVER_ID" --json | jq -r '.addresses[0].ip')
            sleep 3s
        done

        echo "SERVER_EXTERNAL_IP=$EXTERNAL_IP" >> ./server-build.log
        echo "SERVER_INTERNAL_IP=$INTERNAL_IP" >> ./server-build.log
    fi
    printf "%c" "    "
    while ! ping -c 1 "$EXTERNAL_IP" &> /dev/null
    do
        sleep 1
        printf "%c" "."
    done
    until ssh -oStrictHostKeyChecking=no "$SSH_USER"@"$EXTERNAL_IP" 'uname -a; exit'; do
        sleep 1
    done
    echo
    echo "  $SERVER_NAME is ready, access it using ssh at $EXTERNAL_IP."
}

function run (){

    echo "*****************************************************"
    SERVER_ID=$(openssl rand -hex 5)
    SERVER_NAME="rpsene-$SERVER_ID"

    mkdir -p ./servers/"$SERVER_NAME"
    cd ./servers/"$SERVER_NAME" || exit 1

    ### Set this variables accordingly
    SERVER_IMAGE=
    PUBLIC_NETWORK=
    SSH_KEY_NAME=
    SERVER_MEMORY=
    SERVER_PROCESSOR=
    SERVER_SYS_TYPE=
    SSH_USER=
    API_KEY=
    PVS_CRN=
    ####
    
    start=$(date +%s)
    check_dependencies
    check_connectivity
    authenticate "$API_KEY"
    set_powervs "$PVS_CRN"
    create_server "$SERVER_ID" "$SERVER_IMAGE" "$PUBLIC_NETWORK" "$SSH_KEY_NAME" \
    "$SERVER_MEMORY" "$SERVER_PROCESSOR" "$SERVER_SYS_TYPE" "$SSH_USER"
    end=$(date +%s)
    echo "*****************************************************"
    runtime=$((end-start))
    echo "TOTAL TIME: $runtime seconds" 
}

### Main Execution ###
run "$@"
