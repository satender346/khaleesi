#!/bin/bash -ex
#script to be used with component_settings.sh

function ensure_khaleesi() {
    if [ ! -d khaleesi ]; then
    git clone $KHALEESI
    fi
    if [ ! -d khaleesi-settings ]; then
    git clone $KHALEESI_SETTINGS
    fi
    source khaleesi-settings/packstack/jenkins/ansible_settings.sh
    export CONFIG_BASE="${TOP}/khaleesi-settings"
}

function ensure_rpm_prereqs() {
    sudo yum install -y rsync python-pip python-virtualenv gcc python-openstackclient
}


function ensure_ansible() {
    if [ ! -d ansible_venv ]; then
    virtualenv ansible_venv
    fi
    source ansible_venv/bin/activate
    pip install -U ansible
    pip install markupsafe
}

function ensure_ksgen() {
    if ! which ksgen >/dev/null 2>&1; then
    pushd khaleesi/tools/ksgen
    python setup.py develop
    popd
    fi
    pushd khaleesi
    ksgen --config-dir=$CONFIG_BASE/settings generate \
      --rules-file=$CONFIG_BASE/rules/packstack-rdo-aio.yml \
      --provisioner=openstack \
      --provisioner-site=qeos \
      --provisioner-site-user=rhos-jenkins \
      --extra-vars provisioner.key_file=$PRIVATE_KEY \
      --provisioner-options=execute_provision \
      --product-version=juno \
      --product-version-repo=production \
      --product-version-build=latest \
      --product-version-workaround=$DISTRO \
      --workarounds=enabled \
      --distro=$DISTRO \
      --installer-network=neutron \
      --installer-network-variant=ml2-vxlan \
      --installer-messaging=qpidd \
      --tester=tempest \
      --tester-setup=rpm \
      --tester-tests=minimal \
      ksgen_settings.yml
    popd
}

function ensure_ansible_connection(){
    pushd khaleesi
    ansible -i instack_hosts  \
        -u $TESTBED_USER \
        --private-key=$PRIVATE_KEY \
        -vvvv -m ping all
    connection=$?
    popd
    echo $connection
}

function ensure_ssh_key() {
    if ! ensure_ansible_connection; then
        ssh-copy-id "$TESTBED_USER@${TESTBED_IP}"
    else
        echo "ssh keys are properly set up"
    fi
}

function configure_ansible_hosts() {
    pushd khaleesi
    cat <<EOF >instack_hosts
[local]
localhost ansible_connection=local
EOF
    popd
}

function configure_ansible_cfg() {
    pushd khaleesi
    if [ ! -f  ansible.cfg ]; then
    cat <<EOF >ansible.cfg
[defaults]
host_key_checking = False
roles_path = ./roles
library = ./library:$VIRTUAL_ENV/share/ansible/
ssh_args =  -F ssh.config.ansible
pipelining=True
callback_plugins = plugins/callbacks/
EOF
    fi
    popd
}

function test_git_checkout() {
    if [ ! -d khaleesi-settings ]; then
     echo "khaleesi-settings not found"
     exit 1
    fi

    if [ ! -d khaleesi ]; then
         echo "khaleesi not found"
         exit 1
    fi
}


function run_ansible_packstack() {
    pushd khaleesi
    ansible-playbook -vv \
    -u $TESTBED_USER \
    --private-key=${PRIVATE_KEY} \
    -i local_hosts \
    --extra-vars @ksgen_settings.yml \
    playbooks/packstack.yml
    popd
}

if [ ! -f packstack-settings.sh ]; then
     echo "settings not found"
     exit 1
fi



TOP=$(pwd)
source packstack-settings.sh
ensure_rpm_prereqs
ensure_component
ensure_khaleesi
test_git_checkout
ensure_ansible
ensure_ksgen
configure_ansible_hosts
configure_ansible_cfg
run_ansible_packstack

