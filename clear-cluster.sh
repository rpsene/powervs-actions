#!/usr/bin/env bash

: '
    Copyright (C) 2021 IBM Corporation
    Rafael Sene <rpsene@br.ibm.com> - Initial implementation.
'

# Trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
    echo "Bye!"
    exit 0
}

function check_dependencies() {

    DEPENDENCIES=(ibmcloud curl sh wget jq)
    check_connectivity
    for i in "${DEPENDENCIES[@]}"
    do
        if ! command -v $i &> /dev/null; then
            echo "$i could not be found, exiting!"
            exit
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
        exit 1
    fi
    ibmcloud login --no-region --apikey $APY_KEY
}

function set_powervs() {
    
    local CRN="$1"
    
    if [ -z "$CRN" ]; then
        echo "CRN was not set."
        exit 1
    fi
    ibmcloud pi st "$CRN"
}

function delete_unused_volumes() {

    local JSON=/tmp/volumes-log.json

    > $JSON
    ibmcloud pi volumes --json | jq -r '.Payload.volumes[] | "\(.volumeID),\(.pvmInstanceIDs)"' >> $JSON

    while IFS= read -r line; do
        VOLUME=$(echo "$line" | awk -F ',' '{print $1}')
        VMS_ATTACHED=$(echo "$line" | awk -F ',' '{print $2}' | tr -d "\" \[ \]")
        if [ -z "$VMS_ATTACHED" ]; then
            echo "No VMs attached, deleting ..."
	    ibmcloud pi volume-delete $VOLUME
        fi
    done < "$JSON"
}

function delete_vms(){

    CLUSTER_ID=$1

    if [ -z "$CLUSTER_ID" ]; then
        echo "CLUSTER_ID was not set."
        exit 1
    fi

    ibmcloud pi ins --json | jq -r '.Payload.pvmInstances[] | "\(.pvmInstanceID),\(.serverName)"' | \
    grep $CLUSTER_ID | awk -F ',' '{print $1}' | xargs -n1 ibmcloud pi instance-delete
}

function delete_network() {

    CLUSTER_ID=$1

    if [ -z "$CLUSTER_ID" ]; then
        echo "CLUSTER_ID was not set."
        exit 1
    fi

    ibmcloud pi nets --json | jq -r '.Payload.networks[] | "\(.name),\(.networkID)"' | grep $CLUSTER_ID | \
    awk -F ',' '{print $2}' | xargs -n1 ibmcloud pi network-delete
}

function delete_ssh_key(){

    CLUSTER_ID=$1

    if [ -z "$CLUSTER_ID" ]; then
        echo "CLUSTER_ID was not set."
        exit 1
    fi

    ibmcloud pi keys --json | jq -r '.[].name' | grep $CLUSTER_ID | xargs -n1 ibmcloud pi key-delete

}

function help() {

    echo
    echo "clear-cluster.sh API_KEY POWERVS_CRN CLUSTER_ID"
    echo
    echo  "CLUSTER_ID can be any string associated with your cluster and its resources"
}

function run() {

    API_KEY=$1
    POWERVS=$2
    CLUSTER_ID=$3

    if [ -z "$API_KEY" ]; then
        echo "API_KEY was not set."
        exit 1
    fi
    if [ -z "$POWERVS" ]; then
        echo "POWERVS was not set."
        exit 1
    fi
    if [ -z "$CLUSTER_ID" ]; then
        echo "CLUSTER_ID was not set."
        exit 1
    fi

    check_dependencies
    check_connectivity

    authenticate $API_KEY
    set_powervs $POWERVS

    delete_vms $CLUSTER_ID
    delete_ssh_key $CLUSTER_ID

    #    PowerVS takes some time to remove the VMs
    #    sleep for 1 min to avoid any issue deleting 
    #    volumes andnetwork
    sleep 1m 
    delete_network $CLUSTER_ID
    delete_unused_volumes
}

run "$@"
