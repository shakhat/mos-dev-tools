#!/bin/bash
#
# This script installs development and QA tools for Fuel.
#

set -e

TOP_DIR=$(cd $(dirname "$0") && pwd)

source ${TOP_DIR}/helpers/functions.sh

print_usage() {
    echo "Usage: ${0##*/} [-h]"
    echo "Options:"
    echo "  -h: print this usage message and exit"
}

check_root() {
    local user=$(/usr/bin/id -u)
    if [ ${user} -ne 0 ]; then
        error "Only the superuser (uid 0) can use this script."
        exit 1
    fi
}

parse_arguments() {
    while getopts ":h" opt; do
        case ${opt} in
            h)
                print_usage
                exit 0
                ;;
            *)
                error "An invalid option has been detected."
                print_usage
                exit 1
        esac
    done
}

init_variables() {
    USER_NAME=developer
    USER_HOME=/home/${USER_NAME}
    DEST=${DEST:-/opt/stack}
    VIRTUALENV_DIR=${DEST}/.venv

    PIP_SECURE_LOCATION="https://raw.github.com/pypa/pip/master/contrib/get-pip.py"
    TMP="`dirname \"$0\"`"
    TMP="`( cd \"${TMP}\" && pwd )`"

    mkdir -p ${DEST}
}

install_system_requirements() {
    message "Enable default CentOS repos"
    yum -y reinstall centos-release  # enable default CentOS repos

    message "Installing system requirements"
    yum -y install gcc
    yum -y install zlib-devel
    yum -y install sqlite-devel
    yum -y install readline-devel
    yum -y install bzip2-devel
    yum -y install libgcrypt-devel
    yum -y install openssl-devel
    yum -y install libffi-devel
    yum -y install libxml2-devel
    yum -y install libxslt-devel
}

install_python_27() {
    message "Installing Python 2.7"
    TMP="`mktemp -d`"
    cd ${TMP}
    wget https://www.python.org/ftp/python/2.7.8/Python-2.7.8.tgz
    tar xzf Python-2.7.8.tgz
    cd Python-2.7.8
    ./configure --prefix=/usr/local --enable-unicode=ucs4 --enable-shared LDFLAGS="-Wl,-rpath /usr/local/lib"
    make altinstall

    message "Installing pip and virtualenv for Python 2.7"
    GETPIPPY_FILE="`mktemp`"
    wget -O ${GETPIPPY_FILE} ${PIP_SECURE_LOCATION}
    python2.7 ${GETPIPPY_FILE}

    pip2.7 install -U tox
    pip2.7 install -U virtualenv
}

setup_virtualenv() {
    message "Setup virtualenv in ${VIRTUALENV_DIR}"
    virtualenv -p python2.7 ${VIRTUALENV_DIR}
}

activate_virtualenv() {
    source ${VIRTUALENV_DIR}/bin/activate
}

init_cluster_variables() {
    message "Initializing cluster variables"
    CONTROLLER_HOST_ID="`fuel node | grep controller | awk '{print $1}'`"
    CONTROLLER_HOST="node-${CONTROLLER_HOST_ID}"
    message "Controller host: ${CONTROLLER_HOST}"

    export OS_AUTH_URL=http://${CONTROLLER_HOST}:5000/v2.0/
    export OS_AUTH_URL_v3=http://${CONTROLLER_HOST}:5000/v3.0/
    export OS_USERNAME=admin
    export OS_PASSWORD=admin
    export OS_TENANT_NAME=admin

    ADMIN_URL="`keystone catalog --service identity | grep adminURL | awk '{print $4}'`"
    MGMT_IP="`echo ${ADMIN_URL} | sed 's/[\/:]/ /g' | awk '{print $2}'`"
    MGMT_CIDR="`echo ${MGMT_IP} | awk -F '.' '{print $1 "." $2 "." $3 ".0/24"}'`"

    message "Keystone admin URL: ${ADMIN_URL}"
    message "Calculated mgmt network CIDR: ${MGMT_CIDR}"

    message "Adding route to mgmt network"
    ip ro add ${MGMT_CIDR} dev eth0 || true

    # fix permissions on fuel client
    chmod o+r /etc/fuel/client/config.yaml
}

install_rally() {
    message "Installing Rally into ${DEST}"
    cd ${DEST}
    RALLY_DIR=${DEST}/rally
    rm -rf ${RALLY_DIR}
    git clone git://git.openstack.org/stackforge/rally.git
    cd ${RALLY_DIR}
    ${VIRTUALENV_DIR}/bin/pip install -U pbr
    ${VIRTUALENV_DIR}/bin/python setup.py install
    RALLY_CONFIGURATION_DIR="/etc/rally"
    RALLY_DATABASE_DIR="${VIRTUALENV_DIR}/database"
    mkdir -p /etc/rally
    chmod -R o+w /etc/rally
    message "Rally installed into ${RALLY_DIR}"
}

install_tempest() {
    message "Installing Tempest into ${DEST}"
    cd ${DEST}
    TEMPEST_DIR="${DEST}/tempest"
    rm -rf ${TEMPEST_DIR}
    git clone git://git.openstack.org/openstack/tempest.git
    cd ${TEMPEST_DIR}
    ${VIRTUALENV_DIR}/bin/python setup.py install
    mkdir -p /etc/tempest
    chmod -R o+w /etc/tempest
    cp ${TOP_DIR}/helpers/tempest.sh ${VIRTUALENV_DIR}/bin/tempest
    cp ${TOP_DIR}/helpers/sync.sh ${VIRTUALENV_DIR}/bin/sync
    cp ${TOP_DIR}/helpers/functions.sh ${VIRTUALENV_DIR}/bin/
    cp ${TOP_DIR}/helpers/shouldfail ${DEST}/
    message "Tempest installed into ${TEMPEST_DIR}"

    message "Downloading necessary resources"
    TEMPEST_FILES="${VIRTUALENV_DIR}/files"
    mkdir ${TEMPEST_FILES}

    CIRROS_VERSION=${CIRROS_VERSION:-"0.3.2"}
    CIRROS_IMAGE_URL="http://download.cirros-cloud.net/${CIRROS_VERSION}/cirros-${CIRROS_VERSION}-x86_64-uec.tar.gz"
    wget -O ${TEMPEST_FILES}/cirros-${CIRROS_VERSION}-x86_64-uec.tar.gz ${CIRROS_IMAGE_URL}
    cd ${TEMPEST_FILES}
    tar xzf cirros-${CIRROS_VERSION}-x86_64-uec.tar.gz
}

configure_rally() {
    message "Configuring Rally"

    mkdir -p ${RALLY_DATABASE_DIR} ${RALLY_CONFIGURATION_DIR}
    sed 's|#connection=<None>|connection=sqlite:///'${RALLY_DATABASE_DIR}'/rally.sqlite|' \
        ${RALLY_DIR}/etc/rally/rally.conf.sample > ${RALLY_CONFIGURATION_DIR}/rally.conf
    ${VIRTUALENV_DIR}/bin/rally-manage db recreate
    chmod -R go+w ${RALLY_DATABASE_DIR}

    RALLY_CLUSTER_FILE="`mktemp`"
    cat > ${RALLY_CLUSTER_FILE} << EOF
{
    "type": "ExistingCloud",
    "auth_url": "http://${CONTROLLER_HOST}:5000/v2.0/",
    "region_name": "RegionOne",
    "endpoint_type": "public",
    "admin_port": 35357,
    "admin": {
        "username": "admin",
        "password": "admin",
        "tenant_name": "admin"
    }
}
EOF

    ${VIRTUALENV_DIR}/bin/rally deployment create --filename=${RALLY_CLUSTER_FILE} --name=SkyNet
    ${VIRTUALENV_DIR}/bin/rally use deployment --name SkyNet
    ${VIRTUALENV_DIR}/bin/rally deployment check
}

configure_user() {
    message "Creating and configuring user ${USER_NAME}"

    useradd -m ${USER_NAME}
    cp -r /root/.ssh ${USER_HOME}
    chown -R ${USER_NAME} ${USER_HOME}/.ssh

    chown -R ${USER_NAME} ${VIRTUALENV_DIR}

    # bashrc
    cat > ${USER_HOME}/.bashrc <<EOF
test "\${PS1}" || return
shopt -s histappend
HISTCONTROL=ignoredups:ignorespace
HISTFILESIZE=2000
HISTSIZE=1000
export EDITOR=vi
alias ..=cd\ ..
alias ls=ls\ --color=auto
alias ll=ls\ --color=auto\ -lhap
alias vi=vim\ -XNn
alias d=df\ -hT
alias f=free\ -m
alias g=grep\ -iI
alias gr=grep\ -riI
alias l=less
alias n=netstat\ -lnptu
alias p=ps\ aux
alias u=du\ -sh
echo \${PATH} | grep ":\${HOME}/bin" >/dev/null || export PATH="\${PATH}:\${HOME}/bin"
if test \$(id -u) -eq 0
then
export PS1='\[\033[01;41m\]\u@\h:\[\033[01;44m\] \W \[\033[01;41m\] #\[\033[0m\] '
else
export PS1='\[\033[01;33m\]\u@\h\[\033[01;0m\]:\[\033[01;34m\]\W\[\033[01;0m\]$ '
fi
cd ${DEST}
. ${VIRTUALENV_DIR}/bin/activate
. ${USER_HOME}/openrc
EOF
    chown ${USER_NAME} ${USER_HOME}/.bashrc

    # vimrc
    cat > ${USER_HOME}/.vimrc <<EOF
set nocompatible
set nobackup
set nowritebackup
set noswapfile
set viminfo=
syntax on
colorscheme slate
set number
set ignorecase
set smartcase
set hlsearch
set smarttab
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4
filetype on
filetype plugin on
EOF
    chown ${USER_NAME} ${USER_HOME}/.vimrc

    cat >> ${USER_HOME}/.ssh/config <<EOF
User root
EOF

    # openrc
    cat > ${USER_HOME}/openrc <<EOF
export OS_TENANT_NAME=${OS_TENANT_NAME}
export OS_USERNAME=${OS_USERNAME}
export OS_PASSWORD=${OS_PASSWORD}
export OS_AUTH_URL=${OS_AUTH_URL}
export OS_AUTH_URL_V3=${OS_AUTH_URL_v3}
EOF

    # copy Rally deployment openrc
    cp -r /root/.rally ${USER_HOME}
    chown -R ${USER_NAME} ${USER_HOME}/.rally

    chown -R ${USER_NAME} ${DEST}
}

print_information() {
    echo "======================================================================"
    echo "Information about your installation:"
    echo " * User: ${USER_NAME}"
    echo " * Tempest: ${DEST}/tempest"
    echo " * Rally: ${DEST}/rally"
    echo " * Rally database at: ${RALLY_DATABASE_DIR}"
    echo " * Rally configuration file at: ${RALLY_CONFIGURATION_DIR}"
    echo "======================================================================"
}

main() {
    check_root
    parse_arguments "$@"
    init_variables
    install_system_requirements
    install_python_27
    setup_virtualenv

    init_cluster_variables

    install_rally
    install_tempest

    configure_rally
    configure_user

    print_information
    exit 0
}

main "$@"
