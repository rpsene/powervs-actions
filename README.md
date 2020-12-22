# powervs-actions

An user friendly set of PowerVS actions.

```
 1) Check Script Dependencies           19) Get Networks
 2) Install IBM Cloud CLI               20) Get Private Networks
 3) Connect to IBM Cloud                21) Get VMs IPs
 4) Get All Services                    22) Create Public Network
 5) Get PowerVS Instances Details       23) Create Private Network
 6) Set Active PowerVS                  24) Delete Network
 7) Get Instances                       25) Show Network
 8) Inspect Instance                    26) Get Volumes
 9) Delete Instance                     27) Get Volume Types
10) Delete All Instances                28) Create Volume
11) Get All Instances Console URL       29) Create Multiple Volume
12) Open All Instances Console URL      30) Delete Volume
13) Get Images                          31) Delete All Unused Volumes
14) Delete Image                        32) Show Volume
15) Create Boot Image                   33) Create Virtual Machine
16) Get SSH Keys                        34) Install PowerVS Admin Tool
17) Add New SSH Key                     35) Quit
18) Remove SSH Key
```

# Step 0

Execute: 

```
1) Check Script Dependencies
2) Install IBM Cloud CLI
3) Connect to IBM Cloud
4) Get All Services
5) Set Active PowerVS
```

# Creating a VM

1) Execute Step 0
22) Create Public Network (save the ID or name of the public network)
28) Create Volume (this is optional, if you do not need extra storage ignore it)
13) Get Images (to check what is available to use)
16) Get SSH Keys (if you do not remember the name of your ssh key)
17) Add New SSH Key (if you need to create a new SSH key)

```
ibmcloud pi instance-create VM_NAME --image BASE_IMAGE --memory AMOUNT_MEMORY --network NETWORK_NAME --processors AMOUNT_PROCESSORS --processor-type shared --volumes "ID_VOLUME" --key-name SSH_KEY --sys-type s922
```
