#!/bin/bash

: '
    Copyright (C) 2021 IBM Corporation
    Rafael Sene <rpsene@br.ibm.com> - Initial implementation.
'

function check_dependencies() {

    DEPENDENCIES=(ibmcloud curl sh wget jq)
    check_connectivity
    for i in "${DEPENDENCIES[@]}"
    do
        if ! command -v "$i" &> /dev/null; then
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
        exit
    fi
    ibmcloud login --no-region --apikey "$APY_KEY"
}

function get_all_crn(){
	rm -f /tmp/crns
	ibmcloud pi service-list --json | jq -r '.[] | "\(.CRN),\(.Name)"' >> /tmp/crns
}

function set_powervs() {

    local CRN="$1"

    if [ -z "$CRN" ]; then
        echo "CRN was not set."
        exit
    fi
    ibmcloud pi st "$CRN" > /dev/null 2>&1
}

function vm_age() {

    rm -f /tmp/vms

    ibmcloud pi ins --json | jq -r '.Payload.pvmInstances[] | "\(.pvmInstanceID),\(.serverName),\(.networks[].ip),\(.status),\(.sysType),\(.creationDate)"' > /tmp/vms

    while read -r line; do 
        VM_ID=$(echo "$line" | awk -F ',' '{print $1}')
        VM_ID=$(echo "$line" | awk -F ',' '{print $2}')
        VM_CREATION_DATE=$(echo "$line" | awk -F ',' '{print $6}')
        
        Y=$(echo "$VM_CREATION_DATE" | awk -F '-' '{print $1}')
        M=$(echo "$VM_CREATION_DATE" | awk -F '-' '{print $2}' | sed 's/^0*//')
        D=$(echo "$VM_CREATION_DATE" | awk -F '-' '{print $3}' | awk -F 'T' '{print $1}' | sed 's/^0*//')
        DIFF=$(python -c "from datetime import date as d; print(d.today() - d($Y, $M, $D))" | awk -F ',' '{print $1}')
        echo "$VM_ID,$VM_ID,$VM_CREATION_DATE,$DIFF"

    done < /tmp/vms
}

function get_vms_per_crn(){
	while read -r line; do
        CRN=$(echo "$line" | awk -F ',' '{print $1}')
        NAME=$(echo "$line" | awk -F ',' '{print $2}')
        echo "****************************************"
        echo "$NAME"
		    set_powervs "$CRN"
        vm_age	
	done < /tmp/crns
}

function run (){

	if [ -z "$1" ]; then
	    echo
		  echo "ERROR: please, set your IBM Cloud API Key."
		  echo "		 e.g ./vms-age.sh API_KEY"
		  echo
		  exit 1
	else
		  API_KEY=$1
		  check_dependencies
      check_connectivity
      authenticate $API_KEY
	    get_all_crn
	    get_vms_per_crn
	fi
}

run "$@"
