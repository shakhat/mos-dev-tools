#!/bin/bash

prepare() {

    PUBLIC_NETWORK_ID="`neutron net-list --router:external=True -f csv -c id --quote none | tail -1`"
    PUBLIC_ROUTER_ID="`neutron router-list --external_gateway_info:network_id=${PUBLIC_NETWORK_ID} -F id -f csv --quote none | tail -1`"

    keystone tenant-create --name demo
    keystone user-create --tenant demo --name demo --pass demo

    TEMPEST_CONF="`mktemp`"

    cat > ${TEMPEST_CONF} << EOF
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
[network]
public_network_id = ${PUBLIC_NETWORK_ID}
public_router_id = ${PUBLIC_ROUTER_ID}
[service_available]
neutron = true
nova = true
EOF

    config_file=`readlink -f "${TEMPEST_CONF}"`
    export TEMPEST_CONFIG_DIR=`dirname "${TEMPEST_CONF}"`
    export TEMPEST_CONFIG=`basename "${TEMPEST_CONF}"`
}

testr_init() {
    if [ ! -d .testrepository ]; then
        testr init
    fi
}

run() {

    testr_init

    testr run --subunit $testrargs | subunit-2to1
}

main() {
    prepare
    run
    exit 0
}

main "$@"
