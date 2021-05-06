#!/bin/bash

: '
Copyright (C) 2020, 2021 IBM Corporation
Licensed under the Apache License, Version 2.0 (the “License”);
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an “AS IS” BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
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
        exit
    fi
    ibmcloud login --no-region --apikey "$APY_KEY"
}

function get_all_services() {

	VAR=("$(ibmcloud pi service-list --json | jq -r '.[] | "\(.CRN)"')")

	for i in "${VAR[@]}"
	do
		echo "$i"
	done
}

functio run() {

    API_KEY=(
        "" \
        "" 
    )

    check_dependencies
    check_connectivity
    for apik in "${API_KEY[@]}"; do
        authenticate "$apik"
        get_all_services
    done
}


run "$@"
