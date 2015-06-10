exec_with_retry2 () {
    MAX_RETRIES=$1
    INTERVAL=$2

    COUNTER=0
    while [ $COUNTER -lt $MAX_RETRIES ]; do
        EXIT=0
        echo `date -u +%H:%M:%S` >> /home/jenkins-slave/console-$NAME.log 2>&1
        eval '${@:3} >> /home/jenkins-slave/console-$NAME.log 2>&1' || EXIT=$?
        if [ $EXIT -eq 0 ]; then
            return 0
        fi
        let COUNTER=COUNTER+1

        if [ -n "$INTERVAL" ]; then
            sleep $INTERVAL
        fi
    done
    return $EXIT
}

exec_with_retry () {
    CMD=$1
    MAX_RETRIES=${2-10}
    INTERVAL=${3-0}

    exec_with_retry2 $MAX_RETRIES $INTERVAL "$CMD"
}

run_wsmancmd_with_retry () {
    HOST=$1
    USERNAME=$2
    PASSWORD=$3
    CMD=$4

    exec_with_retry "python /home/jenkins-slave/wsman.py -U https://$HOST:5986/wsman -u $USERNAME -p $PASSWORD $CMD"
}

wait_for_listening_port () {
    HOST=$1
    PORT=$2
    TIMEOUT=$3
    exec_with_retry "nc -z -w$TIMEOUT $HOST $PORT" 50 5
}

run_ssh_cmd () {
    SSHUSER_HOST=$1
    SSHKEY=$2
    CMD=$3
    echo `date -u +%H:%M:%S` >> /home/jenkins-slave/console-$NAME.log 2>&1
    echo "Running $CMD" >> /home/jenkins-slave/console-$NAME.log 2>&1
    ssh -t -o 'PasswordAuthentication no' -o 'StrictHostKeyChecking no' -o 'UserKnownHostsFile /dev/null' -i $SSHKEY $SSHUSER_HOST "$CMD" >> /home/jenkins-slave/console-$NAME.log 2>&1
}

run_ssh_cmd_with_retry () {
    SSHUSER_HOST=$1
    SSHKEY=$2
    CMD=$3
    INTERVAL=$4
    MAX_RETRIES=10

    COUNTER=0
    while [ $COUNTER -lt $MAX_RETRIES ]; do
        EXIT=0
        run_ssh_cmd $SSHUSER_HOST $SSHKEY "$CMD" || EXIT=$?
        if [ $EXIT -eq 0 ]; then
            return 0
        fi
        let COUNTER=COUNTER+1

        if [ -n "$INTERVAL" ]; then
            sleep $INTERVAL
        fi
    done
    return $EXIT
}

### Critical 'relation-changed' item!  -Tim
join_hyperv (){
    run_wsmancmd_with_retry $1 administrator H@rd24G3t '"bash C:\OpenStack\devstack\scripts\gerrit-git-prep.sh --zuul-site '$ZUUL_SITE' --gerrit-site '$ZUUL_SITE' --zuul-ref '$ZUUL_REF' --zuul-change '$ZUUL_CHANGE' --zuul-project '$ZUUL_PROJECT' >>\\'$FIXED_IP'\openstack\logs\create-environment-'$1'.log 2>&1"'
    run_wsmancmd_with_retry $1 administrator H@rd24G3t 'powershell -ExecutionPolicy RemoteSigned C:\OpenStack\devstack\scripts\EnsureOpenStackServices.ps1 administrator H@rd24G3t >>\\'$FIXED_IP'\openstack\logs\create-environment-'$1'.log 2>&1'
    run_wsmancmd_with_retry $1 administrator H@rd24G3t '"powershell -ExecutionPolicy RemoteSigned C:\OpenStack\devstack\scripts\create-environment.ps1 -devstackIP '$FIXED_IP' -branchName '$ZUUL_BRANCH' -buildFor '$ZUUL_PROJECT' >>\\'$FIXED_IP'\openstack\logs\create-environment-'$1'.log 2>&1"'
}

#########
# OpenStack control.  Reserve IP, generate VM name/ID, log info to file.
#####
#
# source /home/jenkins-slave/keystonerc_admin
#
# FLOATING_IP=$(nova floating-ip-create public | awk '{print $2}'|sed '/^$/d' | tail -n 1) || echo `date -u +%H:%M:%S` "Failed to alocate floating IP" >> /home/jenkins-slave/console-$NAME.log 2>&1
# if [ -z "$FLOATING_IP" ]
# then
#    exit 1
# fi
# echo FLOATING_IP=$FLOATING_IP > devstack_params.txt
#
#
# UUID=$(python -c "import uuid; print uuid.uuid4().hex")
# export NAME="devstack-$UUID"
# echo NAME=$NAME >> devstack_params.txt
#
#
# NET_ID=$(nova net-list | grep private| awk '{print $2}')
# echo NET_ID=$NET_ID >> devstack_params.txt
#
#
# echo `date -u +%H:%M:%S` FLOATING_IP=$FLOATING_IP > /home/jenkins-slave/console-$NAME.log 2>&1
# echo `date -u +%H:%M:%S` NAME=$NAME >> /home/jenkins-slave/console-$NAME.log 2>&1
# echo `date -u +%H:%M:%S` NET_ID=$NET_ID >> /home/jenkins-slave/console-$NAME.log 2>&1
#
# echo `date -u +%H:%M:%S` "Deploying devstack $NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1
#
#########


devstack_image="devstack"
#if [ $ZUUL_BRANCH -eq "stable/icehouse" ]; then
#  devstack_image="devstack-icehouse"
#fi

echo `date -u +%H:%M:%S` "Image used is: $devstack_image" >> /home/jenkins-slave/console-$NAME.log 2>&1
echo `date -u +%H:%M:%S` "Deploying devstack $NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1

nova boot --availability-zone hyper-v --flavor nova.devstack --image $devstack_image --key-name default --security-groups devstack --nic net-id="$NET_ID" "$NAME" --poll >> /home/jenkins-slave/console-$NAME.log 2>&1
if [ $? -ne 0 ]
then
    echo `date -u +%H:%M:%S` "Failed to create devstack VM: $NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1
    nova show "$NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1
    exit 1
fi

nova show "$NAME"

export VMID=`nova show $NAME | awk '{if (NR == 20) {print $4}}'`
echo VM_ID=$VMID >> devstack_params.txt

echo `date -u +%H:%M:%S` VM_ID=$VMID >> /home/jenkins-slave/console-$NAME.log 2>&1

echo `date -u +%H:%M:%S` "Fetching devstack VM fixed IP address" >> /home/jenkins-slave/console-$NAME.log 2>&1
FIXED_IP=$(nova show "$NAME" | grep "private network" | awk '{print $5}')
export FIXED_IP="${FIXED_IP//,}"

COUNT=1
while [ -z "$FIXED_IP" ]
do
    if [ $COUNT -lt 10 ]
    then
        sleep 15
        FIXED_IP=$(nova show "$NAME" | grep "private network" | awk '{print $5}')
        export FIXED_IP="${FIXED_IP//,}"
        COUNT=$(($COUNT + 1))
    else
        echo "Failed to get fixed IP using nova show $NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1
        echo "Trying to get the IP from console-log and port-list" >> /home/jenkins-slave/console-$NAME.log 2>&1
        FIXED_IP1=`nova console-log $VMID | grep "ci-info" | grep "eth0" | grep "True" | awk '{print $7}'`
        echo "From console-log we got IP: $FIXED_IP1" >> /home/jenkins-slave/console-$NAME.log 2>&1
        FIXED_IP2=`neutron port-list -D -c device_id -c fixed_ips | grep $VMID | awk '{print $7}' | tr -d \" | tr -d }`
        echo "From neutron port-list we got IP: $FIXED_IP2" >> /home/jenkins-slave/console-$NAME.log 2>&1
        if [[ -z "$FIXED_IP1" || -z "$FIXED_IP2" ||  "$FIXED_IP1" != "$FIXED_IP2" ]]
        then
            echo `date -u +%H:%M:%S` "Failed to get fixed IP" >> /home/jenkins-slave/console-$NAME.log 2>&1
            echo `date -u +%H:%M:%S` "nova show output:" >> /home/jenkins-slave/console-$NAME.log 2>&1
            nova show "$NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1
            echo `date -u +%H:%M:%S` "nova console-log output:" >> /home/jenkins-slave/console-$NAME.log 2>&1
            nova console-log "$NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1
            echo `date -u +%H:%M:%S` "neutron port-list output:" >> /home/jenkins-slave/console-$NAME.log 2>&1
            neutron port-list -D -c device_id -c fixed_ips | grep $VMID >> /home/jenkins-slave/console-$NAME.log 2>&1
            exit 1
        else
            export FIXED_IP=$FIXED_IP1
        fi
    fi
done

echo FIXED_IP=$FIXED_IP >> devstack_params.txt
echo `date -u +%H:%M:%S` "FIXED_IP=$FIXED_IP" >> /home/jenkins-slave/console-$NAME.log 2>&1

sleep 10
exec_with_retry "nova add-floating-ip $NAME $FLOATING_IP" 15 5 || { echo `date -u +%H:%M:%S` "nova show $NAME:" >> /home/jenkins-slave/console-$NAME.log 2>&1; nova show "$NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1; echo `date -u +%H:%M:%S` "nova console-log $NAME:" >> /home/jenkins-slave/console-$NAME.log 2>&1; nova console-log "$NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1; exit 1; }

echo `date -u +%H:%M:%S` "nova show $NAME:"
nova show "$NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1

sleep 30
echo "Listening for ssh port on devstack" >> /home/jenkins-slave/console-$NAME.log 2>&1
wait_for_listening_port $FLOATING_IP 22 10 || { echo `date -u +%H:%M:%S` "nova console-log $NAME:" >> /home/jenkins-slave/console-$NAME.log 2>&1; nova console-log "$NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1;echo "Failed listening for ssh port on devstack" >> /home/jenkins-slave/console-$NAME.log 2>&1;exit 1; }
sleep 5





##########
# Start of DevStack on-box prep

echo "clean any apt files:"  >> /home/jenkins-slave/console-$NAME.log 2>&1
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "sudo rm -rf /var/lib/apt/lists/*" 1

echo "apt-get update:" >> /home/jenkins-slave/console-$NAME.log 2>&1
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "sudo apt-get update -y" 1

echo "apt-get upgrade:" >> /home/jenkins-slave/console-$NAME.log 2>&1
#run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem 'sudo DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get -q -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" upgrade' 1

run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem 'DEBIAN_FRONTEND=noninteractive && DEBIAN_PRIORITY=critical && sudo apt-get -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade' 1 

# This part trows exit status 255 so I will comment it out # Victor # 29.05.2015
#echo "apt-get cleanup:" >> /home/jenkins-slave/console-$NAME.log 2>&1
#run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "sudo apt-get autoremove -y" 1

#set timezone to UTC
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "sudo ln -fs /usr/share/zoneinfo/UTC /etc/localtime" 1

# *************************************************

# copy files to devstack
scp -v -r -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -i /home/jenkins-slave/admin-msft.pem /usr/local/src/ci-overcloud-init-scripts/scripts/devstack_vm/* ubuntu@$FLOATING_IP:/home/ubuntu/ >> /home/jenkins-slave/console-$NAME.log 2>&1
#####
### Above command should be replaced with a git clone and directory symlink.  -Tim
## git clone git://github.com/cloudbase/ci-overcloud-init-scripts.git /...


##########
# Get a VLAN range for this set of tests.  -Tim
set +e
VLAN_RANGE=`/usr/local/src/ci-overcloud-init-scripts/vlan_allocation.py -a $NAME`
if [ ! -z "$VLAN_RANGE" ]
then
  run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "sed -i 's/TENANT_VLAN_RANGE.*/TENANT_VLAN_RANGE='$VLAN_RANGE'/g' /home/ubuntu/devstack/localrc /home/ubuntu/devstack/local.conf" 1
fi
set -e
# end VLAN acquisition
##########

### This action (though modified) may still be required.  -Tim
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "sed -i 's/export OS_AUTH_URL.*/export OS_AUTH_URL=http:\/\/127.0.0.1:5000\/v2.0\//g' /home/ubuntu/keystonerc" 1

### What do I need to do with these interfaces?  We'll have physical interfaces available, but what do I do with them?  -Tim
# Add 2 more interfaces after successful SSH
nova interface-attach --net-id "$NET_ID" "$NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1
nova interface-attach --net-id "$NET_ID" "$NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1

##########
# Init the devstack repos!  -Tim
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "/home/ubuntu/bin/update_devstack_repos.sh --branch $ZUUL_BRANCH --build-for $ZUUL_PROJECT" 1

### Why are we doing this?  It should already be covered in the previous SCP, yes?  -Tim
scp -v -r -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -i /home/jenkins-slave/admin-msft.pem /usr/local/src/ci-overcloud-init-scripts/scripts/devstack_vm/devstack/* ubuntu@$FLOATING_IP:/home/ubuntu/devstack >> /home/jenkins-slave/console-$NAME.log 2>&1

ZUUL_SITE=`echo "$ZUUL_URL" |sed 's/.\{2\}$//'`
echo ZUUL_SITE=$ZUUL_SITE >> devstack_params.txt

##########
### Pull changeset!!!  -Tim
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem  "/home/ubuntu/bin/gerrit-git-prep.sh --zuul-site $ZUUL_SITE --gerrit-site $ZUUL_SITE --zuul-ref $ZUUL_REF --zuul-change $ZUUL_CHANGE --zuul-project $ZUUL_PROJECT" 1

##########
### We'll need these images to be on-box in our devstack image for POC.  -Tim
#get locally the vhdx files used by tempest
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "mkdir -p /home/ubuntu/devstack/files/images/"
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "wget http://dl.openstack.tld/cirros-0.3.3-x86_64.vhdx -O /home/ubuntu/devstack/files/images/cirros-0.3.3-x86_64.vhdx"
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "wget http://dl.openstack.tld/Fedora-x86_64-20-20140618-sda.vhdx -O /home/ubuntu/devstack/files/images/Fedora-x86_64-20-20140618-sda.vhdx"

##########
### More devstack node prep. -Tim
# install neutron pip package as it is external
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "sudo pip install -U networking-hyperv --pre"

# make local.sh executable
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "chmod a+x /home/ubuntu/devstack/local.sh"

# run devstack
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem 'source /home/ubuntu/keystonerc; /home/ubuntu/bin/run_devstack.sh' 5

# run post_stack
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "source /home/ubuntu/keystonerc && /home/ubuntu/bin/post_stack.sh" 5

##########
### Relation-changed notes for joining the hyper-v boxes. -Tim
# join Hyper-V servers
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "mkdir -p /openstack/logs"
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "chmod 777 /openstack/logs"
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem "sudo chown nobody:nogroup /openstack/logs"
echo `date -u +%H:%M:%S` "Joining Hyper-V node: $hyperv01"
echo `date -u +%H:%M:%S` "Joining Hyper-V node: $hyperv01" >> /home/jenkins-slave/console-$NAME.log 2>&1
join_hyperv $hyperv01
echo `date -u +%H:%M:%S` "Joining Hyper-V node: $hyperv02"
echo `date -u +%H:%M:%S` "Joining Hyper-V node: $hyperv02" >> /home/jenkins-slave/console-$NAME.log 2>&1
join_hyperv $hyperv02

##########
### Verify the hyper-v joins
# check for nova join (must equal 2)
echo "Checking if both Hyper-V nodes joined are running nova-compute" >> /home/jenkins-slave/console-$NAME.log 2>&1
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem 'source /home/ubuntu/keystonerc; NOVA_COUNT=$(nova service-list | grep nova-compute | grep -c -w up); if [ "$NOVA_COUNT" != 2 ];then nova service-list;exit 1;fi' 12
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem 'source /home/ubuntu/keystonerc; nova service-list' 1

# check for neutron join (must equal 2)
echo "Checking if both Hyper-V nodes joined are running neutron-hyperv-agent" >> /home/jenkins-slave/console-$NAME.log 2>&1
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem 'source /home/ubuntu/keystonerc; NEUTRON_COUNT=$(neutron agent-list | grep -c "HyperV agent.*:-)"); if [ "$NEUTRON_COUNT" != 2 ];then neutron agent-list;exit 1;fi' 12
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP /home/jenkins-slave/admin-msft.pem 'source /home/ubuntu/keystonerc; neutron agent-list' 1
### end verify of hyper-v joins
##########



######
# Script was assumed to be running on the OpenStack controller
# 
# BASE_LOG_PATH   ==> 11/176711/4/check
# ZUUL_PIPELINE   ==> check
# ZUUL_UUID       ==> 843270e15e4940e880bb70ff34aaeb60
# LOG_PATH        ==> 11/176711/4/check/01_Reserve_Hyper-V_Node_01/843270e
# ZUUL_CHANGE_IDS ==> 175238,8 176710,6 176711,4
# ZUUL_PATCHSET   ==> 4
# ZUUL_BRANCH     ==> master
# ZUUL_REF        ==> refs/zuul/master/Z7bda54c8acd04fa7bdb089f7a3037b26
# ZUUL_COMMIT     ==> 3182a7a8c02d189c40e92e6a7a9465dfa70418e1
# ZUUL_URL        ==> http://zuul.openstack.tld/p
# ZUUL_CHANGE     ==> 176711
# ZUUL_CHANGES    ==> openstack/neutron:master:refs/changes/38/175238/8^openstack/neutron:master:refs/changes/10/176710/6^openstack/neutron:master:refs/changes/11/176711/4
# ZUUL_PROJECT    ==> openstack/neutron
# hyperv01        ==> c2-r1-u13.openstack.tld
# hyperv02        ==> c2-r2-u31.openstack.tld
# 
# 
######