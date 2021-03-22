#!/bin/bash

AMOUNT_VMS=$1
IMAGE=$2
NETWORK=$3

for i in $(seq 1 "$AMOUNT_VMS"); do
   SUFIX=$(openssl rand -hex 5)
   ibmcloud pi instance-create "$SUFIX$i" --image "$IMAGE" --memory 8 --network "$NETWORK" --processors 0.50 --processor-type shared --key-name rpsene --sys-type s922
done
