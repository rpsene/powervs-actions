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

VOLUME_ID=""
SERVER_NAME=""

function check_dependencies() {

    DEPENDENCIES=(ibmcloud jq)
    check_connectivity
    for i in "${DEPENDENCIES[@]}"
    do
        if ! command -v $i &> /dev/null; then
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

function create_nfs_server () {

    SERVER_ID=$1
    SERVER_IMAGE=$2
    PUBLIC_NETWORK=$3
    PRIVATE_NETWORK=$4
    SSH_KEY_NAME=$5

    # Default values.
    SERVER_MEMORY=$6
    SERVER_PROCESSOR=$7
    SERVER_SYS_TYPE=$8

    ibmcloud pi instance-create $SERVER_NAME --image $SERVER_IMAGE --memory $SERVER_MEMORY --network $PUBLIC_NETWORK --processors $SERVER_PROCESSOR --processor-type shared --key-name $SSH_KEY_NAME --sys-type $SERVER_SYS_TYPE --json >> server.log

    NFS_SERVER_ID=$(cat ./server.log | jq -r ".[].pvmInstanceID")
    NFS_SERVER_NAME=$(cat ./server.log | jq -r ".[].serverName")

    echo "  $NFS_SERVER_NAME was created with the ID $NFS_SERVER_ID"

    echo "NFS_SERVER_ID=$NFS_SERVER_ID" >> ./server-build.log
    echo "NFS_SERVER_NAME=$NFS_SERVER_NAME" >> ./server-build.log

    echo "  deploying the server $NFS_SERVER_NAME, hold on please."
    STATUS=$(ibmcloud pi in $NFS_SERVER_ID --json | jq -r ".status")

    printf "%c" "    "
    while [[ "$STATUS" != "ACTIVE" ]]
    do
        sleep 5s
        STATUS=$(ibmcloud pi in $NFS_SERVER_ID --json | jq -r ".status")
        printf "%c" "."
    done

    if [[ "$STATUS" == "ERROR" ]]; then
        echo "ERROR: a new VM could not be created, destroy the allocated resources..."
        ibmcloud pi instance-delete $NFS_SERVER_ID
        ibmcloud pi volume-delete $VOLUME_ID
    fi

    if [[ "$STATUS" == "ACTIVE" ]]; then
        echo
        echo "  $NFS_SERVER_NAME is now ACTIVE."
        echo "  waiting for the network availability, hold on please."

        EXTERNAL_IP=$(ibmcloud pi in $NFS_SERVER_ID --json | jq -r '.addresses[0].externalIP')
        printf "%c" "    "
        while [[ -z "$EXTERNAL_IP" ]]; do
            printf "%c" "."
            EXTERNAL_IP=$(ibmcloud pi in $NFS_SERVER_ID --json | jq -r '.addresses[0].externalIP')
            INTERNAL_IP=$(ibmcloud pi in $NFS_SERVER_ID --json | jq -r '.addresses[0].ip')
            sleep 3s
        done

        echo "SERVER_EXTERNAL_IP=$EXTERNAL_IP" >> ./server-build.log
        echo "SERVER_INTERNAL_IP=$INTERNAL_IP" >> ./server-build.log
    fi
    printf "%c" "    "
    while ! ping -c 1 $EXTERNAL_IP &> /dev/null
    do
        sleep 3s
        printf "%c" "."
    done
    echo
    echo "  $NFS_SERVER_NAME is ready, access it using ssh root@$EXTERNAL_IP."
}

function run (){

    echo "*****************************************************"
    SERVER_ID=$(openssl rand -hex 5)
    SERVER_NAME="powervs-vm-$SERVER_ID"

    mkdir -p ./servers/"$SERVER_NAME"
    cd ./servers/$SERVER_NAME

    ### Set this variables accordingly
    SERVER_IMAGE=
    PUBLIC_NETWORK=
    PRIVATE_NETWORK=
    SSH_KEY_NAME=
    SERVER_MEMORY=4
    SERVER_PROCESSOR=1
    SERVER_SYS_TYPE=s922
    ####

    check_dependencies
    check_connectivity
    start=`date +%s`
    create_nfs_server $SERVER_ID $SERVER_IMAGE $PUBLIC_NETWORK $PRIVATE_NETWORK $SSH_KEY_NAME $SERVER_MEMORY $SERVER_PROCESSOR $SERVER_SYS_TYPE
    end=`date +%s`
    echo "*****************************************************"
    runtime=$((end-start))
    echo $runtime
}

### Main Execution ###
run "$@"
