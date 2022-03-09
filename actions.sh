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

function install_ibmcloud() {

    if command -v "ibmcloud" &> /dev/null; then
        echo "ibmcloud is already installed!"
        exit 0
    fi

    local OS="$(uname -s)"

    case "${OS}" in
        Linux*)     distro=Linux;;
        Darwin*)    distro=Mac;;
        Catalina*)  distro=Mac;;
        *)          distro="UNKNOWN:${OS}"
    esac

    if [ $distro == "Linux" ]; then
        echo "Installing ibmcloud CLI on Linux..."
        curl -fsSL https://clis.cloud.ibm.com/install/linux | sh
        ibmcloud plugin install --all -f
    fi

    if [ $distro == "Mac" ]; then
        echo "Installing ibmcloud CLI on Mac..."
        curl -fsSL https://clis.cloud.ibm.com/install/osx | sh
	ibmcloud plugin install --all -f
    fi
}

function get_all_services() {

	VAR=($(ibmcloud pi service-list --json | jq -r '.[] | "\(.CRN),\(.Name)"'))

	echo
	echo "--------------------------"
	for i in "${VAR[@]}"
	do
		NAME=$(echo $i | awk -F ',' '{print $2}')
		CRN=$(echo $i | awk -F ',' '{print $1}')
		GUID=$(echo $CRN | awk -F ':' '{print $8}')

		echo "PowerVS:"
		echo "	Name: $NAME"
		echo "	GUID: $GUID"
		echo "	CRN : $CRN"
		echo "----------"
	done
}

function get_all_services_crn() {

	VAR=($(ibmcloud pi service-list --json | jq -r '.[] | "\(.CRN),\(.Name)"'))
	rm -f "$(pwd)"/crns
	for i in "${VAR[@]}"; do
		CRN=$(echo "$i" | awk -F ',' '{print $1}')
		echo "$CRN" >> /tmp/all-crn
	done
	mv /tmp/all-crn "$(pwd)"/crns
}

function get_all_vms_ips() {

	get_all_services_crn
	IFS=$'\n' read -d '' -r -a crn < "$(pwd)"/crns
	for i in "${crn[@]}"; do
		CRN=$(echo $i | awk -F ',' '{print $1}')
		set_powervs "$CRN"
		get_instances_ips
	done
}

function get_all_images() {
	ibm cloud pi images
}

function get_images_age(){

	IMAGES=($(ibmcloud pi images --json | jq -r ".[] | .images" | jq -r '.[] | "\(.name),\(.imageID),\(.creationDate),\(.specifications.operatingSystem),\(.storageType)"'))

	for line in "${IMAGES[@]}"; do

		IMAGE_NAME=$(echo "$line" | awk -F ',' '{print $1}')
		IMAGE_ID=$(echo "$line" | awk -F ',' '{print $2}')
		OS=$(echo "$line" | awk -F ',' '{print $4}')
		STORAGE_TYPE=$(echo "$line" | awk -F ',' '{print $5}')
        	VM_CREATION_DATE=$(echo "$line" | awk -F ',' '{print $3}')

        	Y=$(echo "$VM_CREATION_DATE" | awk -F '-' '{print $1}')
        	M=$(echo "$VM_CREATION_DATE" | awk -F '-' '{print $2}' | sed 's/^0*//')
        	D=$(echo "$VM_CREATION_DATE" | awk -F '-' '{print $3}' | awk -F 'T' '{print $1}' | sed 's/^0*//')
        	AGE=$(python3 -c "from datetime import date as d; print(d.today() - d($Y, $M, $D))" | awk -F ',' '{print $1}')

		echo "$IMAGE_NAME,$IMAGE_ID,$OS,$STORAGE_TYPE,$AGE"
	done
}

function get_all_volumes() {
	ibm cloud pi volumes
}

function authenticate() {

    local APY_KEY="$1"
    if [ -z "$APY_KEY" ]; then
        echo "API KEY was not set."
        exit 1
    fi
    ibmcloud login --no-region --apikey "$APY_KEY"
}

function set_powervs() {

    local CRN="$1"
    if [ -z "$CRN" ]; then
        echo "CRN was not set."
        exit 1
    fi
    ibmcloud pi st "$CRN"
}

function get_all_powervs_instances_details() {

	> /tmp/powervs-instances
	ibmcloud pi service-list --json | jq '.[] | "\(.CRN),\(.Name)"' >> /tmp/powervs-instances

	while read line; do

		local POWERVS_NAME=$(echo "$line" | awk -F ',' '{print $2}')
		local POWERVS_ZONE=$(echo "$line" | awk -F ':' '{print $6}')
		local POWERVS_INSTANCE_ID=$(echo "$line" | awk -F ':' '{print $8}')
		local SREG=""

		if [[ $POWERVS_ZONE == *"lon"* ]]; then
			SREG="lon"
		elif [[ $POWERVS_ZONE == *"de"* ]]; then
			SREG="eu-de"
		elif [[ $POWERVS_ZONE == *"tor"* ]]; then
			SREG="tor"
		elif [[ $POWERVS_ZONE == *"syd"* ]]; then
			SREG="syd"
		elif [[ $POWERVS_ZONE == *"tok"* ]]; then
			SREG="tok"
		elif [[ $POWERVS_ZONE == *"dal"* ]]; then
			SREG="dal"
		elif [[ $POWERVS_ZONE == *"sao"* ]]; then
			SREG="sao"
		elif [[ $POWERVS_ZONE == *"us-east"* ]]; then
			SREG="us-east"
		else
			SREG="unknown"
		fi
		echo "*********************************"
		echo "PowerVS Name: $POWERVS_NAME" | tr -d "\""
		echo "PowerVS ID: $POWERVS_INSTANCE_ID"
		echo "PowerVS Region: $SREG"
		echo "PowerVS Zone: $POWERVS_ZONE"
	done < /tmp/powervs-instances
}

function get_users() {
	ibmcloud account users
}

function get_networks() {
	ibmcloud pi networks
}

function get_private_networks(){

	> /tmp/powervs-private-network
	ibmcloud pi networks --long --json | \
	jq '.[] | "\(.type),\(.name),\(.networkID)"' | tr -d "\"" \
	>> /tmp/powervs-private-network

	while read line; do
		local TYPE=$(echo "$line" | awk -F ',' '{print $1}')
		local NAME=$(echo "$line" | awk -F ',' '{print $2}')
		local ID=$(echo "$line" | awk -F ',' '{print $3}')

		if [ $TYPE = "vlan" ]; then
			echo "---"
			echo "Private Network Name: $NAME"
			echo "Private Network ID: $ID"
		fi
	done < /tmp/powervs-private-network
}

function get_instances() {
	ibmcloud pi instances
}

function get_instances_ips() {

    local JSON=/tmp/powervs-instances.json
    local FPARSED=/tmp/powervs-id-name.log

    > $JSON
    > $FPARSED

    ibmcloud pi instances --json >> $JSON

    cat $JSON | jq -r '.Payload.pvmInstances[] | "\(.pvmInstanceID),\(.serverName),\(.networks[].ip),\(.status),\(.sysType)"' >> $FPARSED
    while IFS= read -r line; do
            VMID=$(echo "$line" | awk -F ',' '{print $1}')
            VMNAME=$(echo "$line" | awk -F ',' '{print $2}')
            VMPRIP=$(echo "$line" | awk -F ',' '{print $3}')
            VMEXIP=$(ibmcloud pi in $VMID --json | jq -r ".networks[].externalIP")
            VMSTATUS=$(echo "$line" | awk -F ',' '{print $4}')
            VMSYSTYPE=$(echo "$line" | awk -F ',' '{print $5}')
            echo "$VMSTATUS,$VMSYSTYPE,$VMID,$VMNAME,$VMPRIP,$VMEXIP"
    done < "$FPARSED"
}

function get_all_instances_console_url() {

    local JSON=/tmp/powervs-instances.json
    local FPARSED=/tmp/powervs-id-name.log

    > $JSON
    > $FPARSED

    ibmcloud pi instances --json >> $JSON

    cat $JSON | jq -r '.Payload.pvmInstances[] | "\(.pvmInstanceID),\(.serverName),\(.networks[].ip),\(.status),\(.sysType)"' >> $FPARSED
    while IFS= read -r line; do
        VM_ID=$(echo "$line" | awk -F ',' '{print $1}')
        if [ -z "$VM_ID" ]; then
            echo "VM_ID was not set."
            echo "VM_ID: the unique identifier or name of the VM."
            exit 1
        fi
        ibmcloud pi instance-get-console --json $VM_ID | jq -r '.consoleURL'
    done < "$FPARSED"
}

function open_all_instances_console_url() {

    local JSON=/tmp/powervs-instances.json
    local FPARSED=/tmp/powervs-id-name.log
    local URL_LOG=/tmp/console-url.log

    > $JSON
    > $FPARSED
    > $URL_LOG

    ibmcloud pi instances --json >> $JSON

    cat $JSON | jq -r '.Payload.pvmInstances[] | "\(.pvmInstanceID),\(.serverName),\(.networks[].ip),\(.status),\(.sysType)"' >> $FPARSED
    while IFS= read -r line; do
        VM_ID=$(echo "$line" | awk -F ',' '{print $1}')
        if [ -z "$VM_ID" ]; then
            echo "VM_ID was not set."
            echo "VM_ID: the unique identifier or name of the VM."
            exit 1
        fi
        ibmcloud pi instance-get-console --json $VM_ID | jq -r '.consoleURL' >> $URL_LOG
    done < "$FPARSED"
    while IFS= read -r line; do
        /Applications/Firefox.app/Contents/MacOS/firefox -new-tab -url $line
    done < "$URL_LOG"
    rm -f $URL_LOG
}

function delete_all_instances() {

    local JSON=/tmp/powervs-instances.json
    local FPARSED=/tmp/powervs-id-name.log

    > $JSON
    > $FPARSED

    ibmcloud pi instances --json >> $JSON

    cat $JSON | jq -r '.Payload.pvmInstances[] | "\(.pvmInstanceID),\(.serverName),\(.networks[].ip),\(.status),\(.sysType)"' >> $FPARSED
    while IFS= read -r line; do
        VM_ID=$(echo "$line" | awk -F ',' '{print $1}')
        if [ -z "$VM_ID" ]; then
            echo "VM_ID was not set."
            echo "VM_ID: the unique identifier or name of the VM."
            exit 1
        fi
        ibmcloud pi instance-delete "$VM_ID"
    done < "$FPARSED"
}

function reboot_all_instances() {

    local JSON=/tmp/powervs-instances.json
    local FPARSED=/tmp/powervs-id-name.log

    > $JSON
    > $FPARSED

    ibmcloud pi instances --json >> $JSON

    cat $JSON | jq -r '.Payload.pvmInstances[] | "\(.pvmInstanceID),\(.serverName),\(.networks[].ip),\(.status),\(.sysType)"' >> $FPARSED
    while IFS= read -r line; do
        VM_ID=$(echo "$line" | awk -F ',' '{print $1}')
        if [ -z "$VM_ID" ]; then
            echo "VM_ID was not set."
            echo "VM_ID: the unique identifier or name of the VM."
            exit 1
        fi
        ibmcloud pi instance-soft-reboot "$VM_ID"
    done < "$FPARSED"
}

function get_keys() {
	ibmcloud pi keys
}

function add_ssh_key() {

    local KEY_NAME="$1"
    local KEY="$2"

    if [ -z "$KEY_NAME" ]; then
        echo "KEY_NAME was not set."
        exit 1
    fi
    if [ -z "$KEY" ]; then
        echo "KEY was not set."
        exit 1
    fi
    ibmcloud pi key-create "$KEY_NAME" --key "$KEY"
}

function rm_ssh_key() {

    local KEY_NAME="$1"

    if [ -z "$KEY_NAME" ]; then
        echo "KEY_NAME was not set."
        exit 1
    fi
    ibmcloud pi key-delete "$KEY_NAME"
}

function get_volumes() {
	ibmcloud pi volumes
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
	    ibmcloud pi volume-delete "$VOLUME"
        fi
    done < "$JSON"
}

function get_images() {
	ibmcloud pi images
}

function delete_image() {

    local IMAGE_ID="$1"

    if [ -z "$IMAGE_ID" ]; then
        echo "IMAGE_ID was not set."
        echo "IMAGE_ID: the unique identifier or name of the image."
        exit 1
    fi
    ibmcloud pi image-delete "$IMAGE_ID"
}

function delete_vm() {

    local VM_ID="$1"

    if [ -z "$VM_ID" ]; then
        echo "VM_ID was not set."
        echo "VM_ID: the unique identifier or name of the VM."
        exit 1
    fi
    ibmcloud pi instance-delete "$VM_ID"
}

function inspect_vm() {

    local VM_ID="$1"

    if [ -z "$VM_ID" ]; then
        echo "VM_ID was not set."
        echo "VM_ID: the unique identifier or name of the VM."
        exit 1
    fi
    ibmcloud pi in "$VM_ID"
}

function get_storage_types() {
	ibmcloud pi storage-types
	echo "tier1 is nvme, and tier3 is ssd."
}

function create_public_network() {

    local NETWORK_NAME=$1
    local DNS="1.1.1.1 9.9.9.9 8.8.8.8"

    if [ -z "$NETWORK_NAME" ]; then
        echo "NETWORK_NAME was not set."
        exit 1
    fi
    ibmcloud pi netcpu --dns-servers "$DNS" "$NETWORK_NAME"
}

function create_private_network() {

    local NETWORK_NAME=$1
    local DNS="1.1.1.1 9.9.9.9 8.8.8.8"
    local CIDR="192.168.0.0/24"
    local IP_RANGE="192.168.0.2-192.168.0.253"

    if [ -z "$NETWORK_NAME" ]; then
        echo "NETWORK_NAME was not set."
        exit 1
    fi
    ibmcloud pi netcpr --dns-servers "$DNS" --cidr-block "$CIDR" --ip-range "$IP_RANGE" "$NETWORK_NAME"
}


function create_custom_private_network() {

    local NETWORK_NAME="$1"
    local DNS="1.1.1.1 9.9.9.9 8.8.8.8"
    local CIDR="$2"
    local IP_RANGE="$3"

    if [ -z "$NETWORK_NAME" ]; then
        echo "NETWORK_NAME was not set."
        exit 1
    fi
    ibmcloud pi netcpr --dns-servers "$DNS" --cidr-block "$CIDR" --ip-range "$IP_RANGE" "$NETWORK_NAME"
}

function delete_network() {

    local NETWORK_ID="$1"

    if [ -z "$NETWORK_ID" ]; then
        echo "NETWORK_ID was not set."
        echo "NETWORK_ID: the unique identifier or name of the network."
        exit 1
    fi
    ibmcloud pi network-delete "$NETWORK_ID"
}

function network_info() {

    local NETWORK_ID="$1"

    if [ -z "$NETWORK_ID" ]; then
        echo "NETWORK_ID was not set."
        echo "NETWORK_ID: the unique identifier or name of the network."
        exit 1
    fi
    ibmcloud pi network "$NETWORK_ID"
}

function create_storage() {

    VOLUME_NAME="$1"
    VOLUME_SIZE="$2"
    VOLUME_TIER="$3"

    if [ -z "$VOLUME_NAME" ]; then
        echo "VOLUME_NAME was not set."
        exit 1
    fi

    if [ -z "$VOLUME_SIZE" ]; then
        echo "VOLUME_SIZE was not set."
        exit 1
    fi

    if [ -z "$VOLUME_TIER" ]; then
        echo "VOLUME_TIER was not set."
        echo "set 1 for nvme or 3 for ssd".
        exit 1
    fi

    ibmcloud pi volume-create "$VOLUME_NAME" --type "$VOLUME_TIER" --size "$VOLUME_SIZE"
}

function create_multiple_storage() {

    VOLUME_NAME="$1"
    VOLUME_SIZE="$2"
    VOLUME_TIER="$3"
    VOLUME_AMOUNT="$4"

    if [ -z "$VOLUME_NAME" ]; then
        echo "VOLUME_NAME was not set."
        exit 1
    fi

    if [ -z "$VOLUME_SIZE" ]; then
        echo "VOLUME_SIZE was not set."
        exit 1
    fi

    if [ -z "$VOLUME_TIER" ]; then
        echo "VOLUME_TIER was not set."
        echo "set 1 for nvme or 3 for ssd".
        exit 1
    fi

    for i in $(seq 1 $VOLUME_AMOUNT); do
        SUFIX=$(openssl rand -hex 5)
        ibmcloud pi volume-create "$VOLUME_NAME""-""$SUFIX" --type "$VOLUME_TIER" --size "$VOLUME_SIZE"
    done
}


function create_multiple_storage_with_affinity() {

    VOLUME_NAME="$1"
    VOLUME_SIZE="$2"
    VOLUME_TIER="$3"
    VOLUME_AMOUNT="$4"
    VOLUME_AFFINITY_ID="$5"

    if [ -z "$VOLUME_NAME" ]; then
        echo "VOLUME_NAME was not set."
        exit 1
    fi

    if [ -z "$VOLUME_SIZE" ]; then
        echo "VOLUME_SIZE was not set."
        exit 1
    fi

    if [ -z "$VOLUME_TIER" ]; then
        echo "VOLUME_TIER was not set."
        echo "set tier1 for nvme or tier3 for ssd."
        exit 1
    fi

    if [ -z "$VOLUME_AFFINITY_ID" ]; then
        echo "VOLUME_AFFINITY_ID was not set."
        echo "The ID of the storage for affinity was not set."
        exit 1
    fi

    for i in $(seq 1 $VOLUME_AMOUNT); do
        SUFIX=$(openssl rand -hex 5)
	    ibmcloud pi volume-create "$VOLUME_NAME""-""$SUFIX" --size "$VOLUME_SIZE" --affinity-policy affinity --affinity-volume "$VOLUME_AFFINITY_ID"
    done
}

function allocate_volumes_to_vm() {

    TARGET_VM_ID="$1"

    if [ -z "$TARGET_VM_ID" ]; then
        echo "TARGET_VM_ID was not set."
        echo "The ID of the VM to attach the volumes was not set."
        exit 1
    fi

    IFS=' ' read -r -a VOLUMES <<< "$2"
    if [ ${#VOLUMES[@]} -eq 0 ]; then
        echo "The list of volumes to attach to a VM is empty."
        exit 1
    fi

    for V in "${VOLUMES[@]}"; do
        ibmcloud pi volume-attach "$V" --instance "$TARGET_VM_ID"
    done
}

function delete_storage() {

    local VOLUME_ID="$1"

    if [ -z "$VOLUME_ID" ]; then
        echo "VOLUME_ID was not set."
        echo "VOLUME_ID: the unique identifier or name of the volume."
        exit 1
    fi
    ibmcloud pi volume-delete "$VOLUME_ID"
}

function storage_info() {

    local VOLUME_ID="$1"

    if [ -z "$VOLUME_ID" ]; then
        echo "VOLUME_ID was not set."
        echo "VOLUME_ID: the unique identifier or name of the volume."
        exit 1
    fi
    ibmcloud pi volume "$VOLUME_ID"
}

function create_boot_image() {

    local IMAGE_NAME="$1"
    local IMAGE_COB_LOC="$2"
    local IMAGE_COB_BUCKET_NAME="$3"
    local IMAGE_COB_OBJECT_NAME="$4"
    local ACCESS_KEY="$5"
    local SECRET_KEY="$6"

    if [ -z "$IMAGE_NAME" ]; then
        echo "IMAGE_NAME was not set."
        echo "IMAGE_NAME: the unique identifier or name of the new boot image."
        exit 1
    fi
    if [ -z "$IMAGE_COB_LOC" ]; then
        echo "IMAGE_COB_LOC was not set."
        echo "IMAGE_COB_LOC: the location of the object storage where the object data is located, for instance us-south."
        exit 1
    fi
    if [ -z "$IMAGE_COB_BUCKET_NAME" ]; then
        echo "IMAGE_COB_BUCKET_NAME was not set."
        echo "IMAGE_COB_BUCKET_NAME: the name of the bucket where the object is stored."
        exit 1
    fi
    if [ -z "$IMAGE_COB_OBJECT_NAME" ]; then
        echo "IMAGE_COB_OBJECT_NAME was not set."
        echo "IMAGE_COB_OBJECT_NAME: the name of the object within the given object storage."
        exit 1
    fi
    if [ -z "$ACCESS_KEY" ]; then
        echo "ACCESS_KEY was not set."
        echo "ACCESS_KEY: the cloud object storage HMAC access key."
        exit 1
    fi
    if [ -z "$SECRET_KEY" ]; then
        echo "SECRET_KEY was not set."
        echo "SECRET_KEY: the cloud object storage HMAC secret key."
        exit 1
    fi

    ibmcloud pi image-import "$IMAGE_NAME" \
    --image-path "s3.private.$IMAGE_COB_LOC.cloud-object-storage.appdomain.cloud/$IMAGE_COB_BUCKET_NAME/$IMAGE_COB_OBJECT_NAME" \
    --access-key $ACCESS_KEY --secret-key $SECRET_KEY
}

function create_vm() {

    VM_NAME="$1"
    VM_IMAGE="$2"
    VM_MEM="$3"
    VM_PROC="$4"
    VM_SYS_TYPE="$5"
    VM_SSH_KEY_NAME="$6"
    VM_NETWORK_NAME="$7"
    VM_ADITIONAL_VOLUMES="$8"
    VM_PROC_TYPE="shared"
    VM_REPLICANTS="1"
    VM_REPLICANT_SCHEME="suffix"
    VM_REPLICANT_AFFINITY_POLICY="affinity"

    if [ -z "$VM_NAME" ]; then
        echo "VM_NAME was not set."
        echo "Give your VM a friendly name."
        exit 1
    fi
    if [ -z "$VM_IMAGE" ]; then
        echo "VM_IMAGE was not set."
        echo "Operating system image identifier or name."
        exit 1
    fi
    if [ -z "$VM_MEM" ]; then
        echo "VM_MEM was not set."
        echo "Amount of memory (in GB) to allocate to the instance."
        exit 1
    fi
    if [ -z "$VM_PROC" ]; then
        echo "VM_PROC was not set."
        echo "Amount of processors to allocate to the instance."
        exit 1
    fi
    if [ -z "$VM_PROC_TYPE" ]; then
        echo "VM_PROC_TYPE was not set."
        echo "Type of processors: shared (\$) or capped (\$\$) or dedicated (\$\$\$)".
        exit 1
    fi
    if [ -z "$VM_NETWORK_NAME" ]; then
        echo "VM_NETWORK_NAME was not set."
        echo "Space separated identifier/name of the network and optional IP address to associate with the instance."
        exit 1
    fi
    if [ -z "$VM_SSH_KEY_NAME" ]; then
        echo "VM_SSH_KEY_NAME was not set."
        echo "Name of SSH key."
        exit 1
    fi
    if [ -z "$VM_SYS_TYPE" ]; then
        echo "VM_SYS_TYPE was not set."
        echo "Name of System Type (s922, e880, e980)."
        exit 1
    fi

    systems=(s922 e880 e980)
    #Validate the system type
    if [[ ! " ${systems[@]} " =~ " ${VM_SYS_TYPE} " ]]; then
        echo "Available systems type: s922 or e880 or e980."
        exit 1
    fi

    CMD="ibmcloud pi instance-create $VM_NAME --image $VM_IMAGE --memory $VM_MEM --processors $VM_PROC --processor-type $VM_PROC_TYPE --network $VM_NETWORK_NAME --key-name $VM_SSH_KEY_NAME --sys-type $VM_SYS_TYPE --replicants $VM_REPLICANTS --replicant-scheme $VM_REPLICANT_SCHEME --replicant-affinity-policy $VM_REPLICANT_AFFINITY_POLICY"

    if [ ! -z "$VM_ADITIONAL_VOLUMES" ]; then
        > /tmp/volumes.log
        ibmcloud pi volumes --json | jq -rc '.[].volumes[].volumeID' >> /tmp/volumes.log
        IFS=$'\n' read -d '' -r -a VOLUMES < /tmp/volumes.log
        IFS=' ' read -r -a USER_SET_VOLUMES <<< "$VM_ADITIONAL_VOLUMES"
        for volume in "${USER_SET_VOLUMES[@]}"; do
            if [[ ! " ${VOLUMES[@]} " =~ " $volume " ]]; then
                echo "Looks like the volume $volume does not exist."
                exit 1
            fi
        done
        CMD="$CMD --volumes $VM_ADITIONAL_VOLUMES"
    fi

    eval "$CMD"
}

function identify_os() {

    local OS="$(uname -s)"

    case "${OS}" in
        Linux*)     DISTRO=linux;;
        Darwin*)    DISTRO=darwin;;
        Catalina*)  DISTRO=darwin;;
        *)          DISTRO="UNKNOWN:${OS}"
    esac

    ARCH=$(uname -m)

    if [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ]; then
        ARCH=amd64
    fi

    export $ARCH
    export $DISTRO
}

function install_pvsadmin() {

    curl -s "https://api.github.com/repos/ppc64le-cloud/pvsadm/releases" >> /tmp/pvsadmin.json

    TAGS=($(cat /tmp/pvsadmin.json | jq -r '.[].tag_name'))

    PVSADM_VERSION=$TAGS

    rm -f /tmp/pvsadmin.json

    if command -v "pvsadm" &> /dev/null; then
        echo "pvsadm is already installed!"
        exit 0
    fi

    wget -q -O /usr/local/bin/pvsadm "https://github.com/ppc64le-cloud/pvsadm/releases/download/$PVSADM_VERSION/pvsadm-$DISTRO-$ARCH"
    chmod +x /usr/local/bin/pvsadm
    pvsadm version
}

function install_pvsadm_dependencies() {

    if [ $DISTRO == "linux" ]; then

        echo "Installing dependencies on Linux..."
        OS=$(cat /etc/os-release | grep -w "ID" | awk -F "=" '{print $2}' | tr -d "\"")

        if [ $OS == "ubuntu" ]; then
            apt-get install -y jq curl wget python3 python3-pip qemu-utils cloud-utils cloud-guest-utils
            pip3 install -U jinja2 boto3 PyYAML
        fi
        if [ $OS == "centos" ]; then
            dnf install -y jq curl wget python38 python38-pip qemu-img cloud-utils-growpart
            pip3 install -U jinja2 boto3 PyYAML
        fi
        if [ $OS == "rhel" ]; then
            RH_REGISTRATION=$(subscription-manager identity 2> /tmp/rhsubs.out; cat /tmp/rhsubs.out; rm -f /tmp/rhsubs.out)
            if [[ "$RH_REGISTRATION" == *"not yet registered"* ]]; then
                echo "Please, ensure your system is subscribed to RedHat."
                exit 1
            else
                dnf install -y jq curl wget python38 python38-pip qemu-img cloud-utils-growpart
                pip3 install -U jinja2 boto3 PyYAML
            fi
        fi
    fi

    # We do not install the .ova image creation requirements on MacOS.
    if [ $DISTRO == "darwin" ]; then
        echo "Installing ibmcloud CLI on Mac..."
        if ! command -v "brew" &> /dev/null; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
        fi
        brew install -U python@3.9
        brew install -U jq
        pip3 install -U jinja2 boto3 PyYAML
    fi
}

function run() {
    PS3='Please enter your choice: '
    options=( "Check Script Dependencies" "Install IBM Cloud CLI" "Connect to IBM Cloud" "Get all CRNs" "Get PowerVS Services CRN and GUID" "Get PowerVS Instances Details" "Set Active PowerVS" "Get Instances" "Inspect Instance" "Delete Instance" "Delete All Instances" "Reboot All Instances" "Get All Instances Console URL" "Open All Instances Console URL" "Get Images" "Get Images Age" "Delete Image" "Create Boot Image" "Get SSH Keys" "Add New SSH Key" "Remove SSH Key" "Get Networks" "Get Private Networks" "Get VMs IPs" "Get All VMs IPs" "Create Public Network" "Create Private Network" "Create Custom Private Network" "Delete Network" "Show Network" "Get Volumes" "Get Volume Types" "Create Volume" "Create Multiple Volumes" "Create Multiple Volumes with Affinity" "Allocate Volumes to VM" "Delete Volume" "Delete All Unused Volumes" "Show Volume" "Create Virtual Machine" "Install PowerVS Admin Tool" "Get Users" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "Check Script Dependencies")
                check_dependencies
                break
                ;;
            "Install IBM Cloud CLI")
                install_ibmcloud
                break
                ;;
            "Connect to IBM Cloud")
                echo "Enter the API KEY, followed by [ENTER]:"
                read -rs API_KEY
                authenticate "$API_KEY"
                break
                ;;
	        "Get all CRNs")
	    	    get_all_services_crn
                break
                ;;
            "Get PowerVS Services CRN and GUID")
                get_all_services
                break
                ;;
            "Get PowerVS Instances Details")
                get_all_powervs_instances_details
                break
                ;;
            "Set Active PowerVS")
                echo "Enter the CRN, followed by [ENTER]:"
                read -r CRN
                set_powervs "$CRN"
                break
                ;;
            "Get Instances")
                get_instances
                break
                ;;
            "Inspect Instance")
                echo "Enter the image ID, followed by [ENTER]:"
                read -r IMAGE_ID
                inspect_vm "$IMAGE_ID"
                break
                ;;
            "Delete Instance")
                echo "Enter the instance ID, followed by [ENTER]:"
                read -r VM_ID
                delete_vm "$VM_ID"
                break
                ;;
            "Delete All Instances")
                delete_all_instances
                break
                ;;
	    "Reboot All Instances")
                reboot_all_instances
                break
                ;;
            "Get All Instances Console URL")
                get_all_instances_console_url
                break
                ;;
            "Open All Instances Console URL")
                open_all_instances_console_url
                break
                ;;
            "Get Images")
                get_images
                break
                ;;
	        "Get Images Age")
                get_images_age
                break
                ;;
            "Create Boot Image")
                echo "Enter the name of the new boot image, followed by [ENTER]:"
                read -r IMAGE_NAME
                echo "Enter the location of the object storage where the object data is located, followed by [ENTER]:"
                read -r IMAGE_COB_LOC
                echo "Enter the name of the bucket where the object is stored, followed by [ENTER]:"
                read -r IMAGE_COB_BUCKET_NAME
                echo "Enter the the name of the object within the given object storage, followed by [ENTER]:"
                read -r IMAGE_COB_OBJECT_NAME
                echo "Enter the cloud object storage HMAC access key, followed by [ENTER]:"
                read -rs ACCESS_KEY
                echo "Enter the cloud object storage HMAC secret key, followed by [ENTER]:"
                read -rs SECRET_KEY
                create_boot_image "$IMAGE_NAME" "$IMAGE_COB_LOC" "$IMAGE_COB_BUCKET_NAME" "$IMAGE_COB_OBJECT_NAME" "$ACCESS_KEY" "$SECRET_KEY"
                break
                ;;
            "Delete Image")
                echo "Enter the image ID, followed by [ENTER]:"
                read -r IMAGE_ID
                delete_image "$IMAGE_ID"
                break
                ;;
            "Get Networks")
                get_networks
                break
                ;;
            "Get Private Networks")
                get_private_networks
                break
                ;;
            "Get VMs IPs")
                get_instances_ips
                break
                ;;
            "Get All VMs IPs")
	    	    get_all_vms_ips
		        break
		        ;;
            "Get Volumes")
                get_volumes
                break
                ;;
            "Get SSH Keys")
                get_keys
                break
                ;;
            "Add New SSH Key")
                echo "Enter the new SSH Key name, followed by [ENTER]:"
                read -r KEY_NAME
                echo "Enter the new SSH Key, followed by [ENTER]:"
                read -r KEY
                add_ssh_key "$KEY_NAME" "$KEY"
                break
                ;;
            "Remove SSH Key")
                echo "Enter the new SSH Key name, followed by [ENTER]:"
                read -r KEY_NAME
                rm_ssh_key "$KEY_NAME"
                break
                ;;
            "Get Volume Types")
                get_storage_types
                break
                ;;
            "Create Public Network")
                echo "Enter the new network name, followed by [ENTER]:"
                read -r NETWORK_NAME
                create_public_network "$NETWORK_NAME"
                break
                ;;
            "Create Private Network")
                echo "Enter the new network name, followed by [ENTER]:"
                read -r NETWORK_NAME
                create_private_network "$NETWORK_NAME"
                break
                ;;
            "Create Custom Private Network")
                echo "Enter the new network name, followed by [ENTER]:"
                read -r NETWORK_NAME
		echo "Enter the new network CIDR (e.g 192.168.0.0/24), followed by [ENTER]:"
                read -r NETWORK_CIDR
		echo "Enter the new network ip range (e.g 192.168.0.2-192.168.0.253), followed by [ENTER]:"
                read -r NETWORK_RANGE
                create_custom_private_network "$NETWORK_NAME" "$NETWORK_CIDR" "$NETWORK_RANGE"
                break
                ;;
            "Delete Network")
                echo "Enter the network ID, followed by [ENTER]:"
                read -r NETWORK_ID
                delete_network "$NETWORK_ID"
                break
                ;;
            "Show Network")
                echo "Enter the network ID, followed by [ENTER]:"
                read -r NETWORK_ID
                network_info "$NETWORK_ID"
                break
                ;;
            "Create Volume")
                echo "Enter the new volume name, followed by [ENTER]:"
                read -r VOLUME_NAME

                echo "Enter the new volume size (G), followed by [ENTER]:"
                read -r VOLUME_SIZE

                echo "Enter the new volume tier (you can check what is available using the option \"Get Volume Types\"), followed by[ENTER]:"
                read -r VOLUME_TIER

                create_storage "$VOLUME_NAME" "$VOLUME_SIZE" "$VOLUME_TIER"
                break
                ;;
            "Create Multiple Volumes")
                echo "Enter the new volume name, followed by [ENTER]:"
                read -r VOLUME_NAME

                echo "Enter the new volume size (G), followed by [ENTER]:"
                read -r VOLUME_SIZE

                echo "Enter the new volume tier (tier1 or tier3), followed by[ENTER]:"
                read -r VOLUME_TIER

                echo "Enter the amount of volumes, followed by[ENTER]:"
                read -r VOLUME_AMOUNT

                create_multiple_storage "$VOLUME_NAME" "$VOLUME_SIZE" "$VOLUME_TIER" "$VOLUME_AMOUNT"
                break
                ;;
            "Create Multiple Volumes with Affinity")
                echo "Enter the new volume name, followed by [ENTER]:"
                read -r VOLUME_NAME

                echo "Enter the new volume size (G), followed by [ENTER]:"
                read -r VOLUME_SIZE

                echo "Enter the new volume tier (tier1 or tier3), followed by[ENTER]:"
                read -r VOLUME_TIER

                echo "Enter the amount of volumes, followed by[ENTER]:"
                read -r VOLUME_AMOUNT

		        echo "Enter the ID of the storage to be used for affinity, followed by[ENTER]:"
                read -r VOLUME_ID

                create_multiple_storage_with_affinity "$VOLUME_NAME" "$VOLUME_SIZE" "$VOLUME_TIER" "$VOLUME_AMOUNT" "$VOLUME_ID"
                break
                ;;

            "Allocate Volumes to VM")

                echo "Enter the target VM ID, followed by [ENTER]:"
                read -r TARGET_VM_ID

                echo "Enter the ID of volumes you want to attach separated by space, followed by [ENTER]:"
                read -r VOLUMES

                allocate_volumes_to_vm  "$TARGET_VM_ID" "$VOLUMES"
                break
                ;;
            "Delete Volume")
                echo "Enter the volume ID, followed by [ENTER]:"
                read -r VOLUME_ID
                delete_storage "$VOLUME_ID"
                break
                ;;
            "Delete All Unused Volumes")
                delete_unused_volumes
                break
                ;;
            "Show Volume")
                echo "Enter the volume ID, followed by [ENTER]:"
                read -r VOLUME_ID
                storage_info "$VOLUME_ID"
                break
                ;;
            "Create Virtual Machine")
                echo "Enter the name of the new VM, followed by [ENTER]:"
                read -r VM_NAME

                echo "Enter the name of the image to be used to create the VM (use the option 7 to get it), followed by [ENTER]:"
                read -r VM_IMAGE

                echo "Enter the amount of memory (G) for the VM, followed by [ENTER]:"
                read -r VM_MEM

                echo "Enter the amount of processors for the new VM, followed by [ENTER]:"
                read -r VM_PROC

                echo "Enter the type of system to run the new VM (s922, e880, e980), followed by [ENTER]:"
                read -r VM_SYS_TYPE

                echo "Enter the name of SSH key to be added in the new VM (use option 9 to get it), followed by [ENTER]:"
                read -r VM_SSH_KEY_NAME

                echo "Enter the name of the network to add to the new VM (use item 13 to create a new one or 12 to get the name of an existing one), followed by [ENTER]:"
                read -r VM_NETWORK_NAME

                echo "Enter the list of additional volumes (separated by spaces), to attach to the new VM (use option 16 to list existing volumes or use option 18 to create a new one), followed by [ENTER]:"
                read -r VM_ADITIONAL_VOLUMES

                create_vm "$VM_NAME" "$VM_IMAGE" "$VM_MEM" "$VM_PROC" "$VM_SYS_TYPE" "$VM_SSH_KEY_NAME" "$VM_NETWORK_NAME" "$VM_ADITIONAL_VOLUMES"
                break
                ;;
            "Install PowerVS Admin Tool")
	    	    identify_os
		        install_pvsadm_dependencies
                install_pvsadmin
                break
                ;;
            "Get Users")
                get_users
                break
                ;;
            "Quit")
                return
                break
                ;;
            *) echo invalid option;;
        esac
    done
}

run "$@"
