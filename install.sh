#!/bin/bash
#
# This script installs development and QA tools for Fuel.
#

set -e

error() {
    printf "\e[31mError: %s\e[0m\n" "${*}" >&2
    exit 1
}

message() {
    printf "\e[33m%s\e[0m\n" "${1}"
}

print_usage() {
    echo "Usage: ${0##*/} [-h]"
    echo "Options:"
    echo "  -h: print this usage message and exit"
}

check_root() {
    local user=$(/usr/bin/id -u)
    if [ ${user} -ne 0 ]; then
        err "Only the superuser (uid 0) can use this script."
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
                err "An invalid option has been detected."
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

    message "Tuning cluster"
    keystone tenant-create --name demo
    keystone user-create --tenant demo --name demo --pass demo
}

install_puppet_tempest() {
    message "Installing puppet module for Tempest"
    TMP="`mktemp -d`"
    cd ${TMP}
    git clone https://github.com/shakhat/puppet-tempest.git
    cd puppet-tempest
    git checkout identity_uri_v3
    cd ../
    puppet module build puppet-tempest
    TEMPEST_MODULE="`ls puppet-tempest/pkg/*gz`"
    puppet module install --force ${TEMPEST_MODULE}
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
    message "Rally installed into ${RALLY_DIR}"
}

install_and_preconfigure_tempest() {
    message "Installing and configuring Tempest"
    TEMPEST_DIR="${DEST}/tempest"
    TEMPEST_SITE_PP="`mktemp`"
    cat > ${TEMPEST_SITE_PP} << EOF
node default {
  class { 'tempest':
    setup_venv           => true,
    tempest_clone_path   => "${TEMPEST_DIR}",

    identity_uri         => "http://${CONTROLLER_HOST}:5000/v2.0",
    identity_uri_v3      => "http://${CONTROLLER_HOST}:5000/v3.0/",
    image_name           => "TestVM",
    image_name_alt       => "TestVM",

    username             => "demo",
    password             => "demo",
    tenant_name          => "demo",

    admin_username       => "admin",
    admin_password       => "admin",
    admin_tenant_name    => "admin",
    admin_role           => "admin",

    # services
    neutron_available    => true,
    cinder_available     => false,
    glance_available     => false,
    nova_available       => false,

    public_network_name  => "net04",
  }
}
EOF

    puppet apply ${TEMPEST_SITE_PP}
    message "Tempest installed into ${TEMPEST_DIR}"
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
    "endpoint": {
        "auth_url": "http://${CONTROLLER_HOST}:5000/v2.0/",
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
. ${USER_HOME}/.rally/openrc
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

    # copy Rally's openrc
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
    install_puppet_tempest

    install_rally
    install_and_preconfigure_tempest
    configure_rally

    configure_user

    print_information
    exit 0
}

main "$@"
