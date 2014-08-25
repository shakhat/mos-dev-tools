#!/bin/bash

TOP_DIR=$(cd $(dirname "$0") && pwd)
DEST=${DEST:-/opt/stack}

source ${TOP_DIR}/functions.sh

print_usage() {
    echo "This script configures and runs Tempest"
    echo "Usage: ${0##*/} [-d|h] "
    echo "Options:"
    echo "  -h:                prints this help message"
    echo "  -d:                switch debug logs on"
    echo "  -- [TESTROPTIONS]  Arguments are passed to testr"
}

parse_arguments() {
    LOGGING_DEBUG="false"

    while getopts ":hd" opt; do
        case ${opt} in
            h)
                print_usage
                exit 0
                ;;
            d)
                LOGGING_DEBUG="true"
                ;;
            *)
                error "An invalid option has been detected."
                print_usage
                exit 1
        esac
    done
    shift $((OPTIND-1))
    [ "$1" = "--" ] && shift
}

prepare() {
    message "Configuring Tempest"

    PUBLIC_NETWORK_ID="`neutron net-list --router:external=True -f csv -c id --quote none | tail -1`"
    PUBLIC_ROUTER_ID="`neutron router-list --external_gateway_info:network_id=${PUBLIC_NETWORK_ID} -F id -f csv --quote none | tail -1`"
    IMAGE_REF="`glance image-list --name TestVM | grep TestVM | awk '{print $2}'`"

    keystone tenant-create --name demo &>/dev/null || true
    keystone user-create --tenant demo --name demo --pass demo &>/dev/null || true
    nova flavor-create m1.nano 0 64 0 1 &>/dev/null || true

    TEMPEST_CONF="`mktemp`"

    cat > ${TEMPEST_CONF} << EOF
[DEFAULT]
debug = ${LOGGING_DEBUG}

[service_available]
neutron = true
nova = true
cinder = true
glance = true

[identity]
admin_password = ${OS_PASSWORD}
admin_tenant_name = ${OS_TENANT_NAME}
admin_username = ${OS_USERNAME}
admin_role = admin
password = demo
tenant_name = demo
username = demo
uri = ${OS_AUTH_URL}
uri_v3 = ${OS_AUTH_URL_V3}

[compute]
image_ref = ${IMAGE_REF}
flavor_ref = 0
image_ssh_user = cirros

[network]
public_network_id = ${PUBLIC_NETWORK_ID}
public_router_id = ${PUBLIC_ROUTER_ID}

[scenario]
image_dir = ${DEST}/.venv/files
qcow2_img_file = cirros-0.3.2-x86_64-blank.img
EOF

    config_file=`readlink -f "${TEMPEST_CONF}"`
    export TEMPEST_CONFIG_DIR=`dirname "${TEMPEST_CONF}"`
    export TEMPEST_CONFIG=`basename "${TEMPEST_CONF}"`
}

run() {
    message "Running Tempest with the following config:"
    message "`cat ${TEMPEST_CONF}`"

    cd /opt/stack/tempest/
    ./run_tempest.sh -N "$@"
    cd ${TOP_DIR}
}

main() {
    parse_arguments "$@"
    prepare
    run "$@"
    exit 0
}

main "$@"
