########
# DevStack installation
########
## Currently supplied by DevStack disk image.

########
# DevStack initial config
########

### Variables
# Magic variable for VLANs.  Replace with a script call eventually.
VLAN_RANGE='175:199'
#ZUUL_BRANCH
#ZUUL_PROJECT
#ZUUL_REF
#ZUUL_CHANGE


sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update -y
DEBIAN_FRONTEND=noninteractive
DEBIAN_PRIORITY=critical
sudo apt-get -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
sudo ln -fs /usr/share/zoneinfo/UTC /etc/localtime

git clone git://github.com/cloudbase/ci-overcloud-init-scripts.git ~/ci-overcloud-init-scripts
cp -a ~/ci-overcloud-init-scripts/scripts/devstack_vm/* ~/
#ln -s ~/ci-overcloud-init-scripts/scripts/devstack_vm ~/devstack_scripts
#ln -s ~/ci-overcloud-init-scripts/scripts/devstack_vm/devstack ~/devstack

sed -i 's/TENANT_VLAN_RANGE.*/TENANT_VLAN_RANGE='$VLAN_RANGE'/g' /home/ubuntu/devstack/localrc /home/ubuntu/devstack/local.conf

sed -i 's/export OS_AUTH_URL.*/export OS_AUTH_URL=http:\/\/127.0.0.1:5000\/v2.0\//g' /home/ubuntu/keystonerc



########
# Test repository prep
########

/home/ubuntu/bin/update_devstack_repos.sh --branch $ZUUL_BRANCH --build-for $ZUUL_PROJECT
ZUUL_SITE=`echo "$ZUUL_URL" |sed 's/.\{2\}$//'`
/home/ubuntu/bin/gerrit-git-prep.sh --zuul-site $ZUUL_SITE --gerrit-site $ZUUL_SITE --zuul-ref $ZUUL_REF --zuul-change $ZUUL_CHANGE --zuul-project $ZUUL_PROJECT

########
# Continued Setup/Construction
########
sudo pip install -U networking-hyperv --pre
chmod a+x /home/ubuntu/devstack/local.sh
source /home/ubuntu/keystonerc
/home/ubuntu/bin/run_devstack.sh
/home/ubuntu/bin/post_stack.sh


mkdir -p /openstack/logs
chmod 777 /openstack/logs
sudo chown nobody:nogroup /openstack/logs