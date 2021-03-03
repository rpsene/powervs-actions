#!/bin/bash

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
    ibmcloud pi st "$CRN" > /dev/null 2>&1
}

function main() {

# add all CRNs related you all your PowerVS instances
CNRs=(
	"" \
	"" \
	""
)

authenticate "YOUR_IBM_CLOUD_API_KEY_GOES_HERE"

for cnr in "${CNRs[@]}"; do
    echo "--------------------------------------------------"
    echo $cnr | awk '{split($0,var,":"); print var[6]}'
    set_powervs "$cnr"
    ibmcloud pi images --json | jq -r '.Payload.images[] | .name + ", " + .state'
done

}

main "$@"
