#!/bin/bash

TOP_DIR=$(cd $(dirname "$0") && pwd)
DEST=${DEST:-/opt/stack}
VIRTUALENV_DIR=${DEST}/.venv

source ${TOP_DIR}/functions.sh

MODULE="$1"

print_usage() {
    echo "This script syncs code from local repo to nodes and restarts corresponding services"
    echo "Usage: ${0##*/} [-h] <MODULE>"
    echo "Options:"
    echo "  -h:         prints this help message"
    echo "  [MODULE]:   name of module to sync"
}

if [ "${MODULE}" = "" ]; then
    print_usage
    exit 1
fi

if [ ! -d "${DEST}/${MODULE}" ]; then
    error "Module ${MODULE} not found in ${DEST}"
    exit 1
fi

message "Packaging ${MODULE}"

NODE_IDS="`fuel node | grep ready | awk '{print $1}'`"

TMP="`mktemp -d`"
cd ${DEST}/${MODULE}
${VIRTUALENV_DIR}/bin/python setup.py sdist --dist-dir ${TMP}
DIST="`ls ${TMP}`"

if [ ! -f "${TMP}/${DIST}" ]; then
    error "Failed to build package for module ${MODULE}"
    exit 1
fi

while read -r line; do
    NODE="node-${line}"
    message "Syncing ${MODULE} to ${NODE}"
    scp ${TMP}/${DIST} root@${NODE}:/tmp/
    ssh root@${NODE} pip install /tmp/${DIST}

    if [ "${MODULE}" = "neutron" ]; then
        ssh root@${NODE} service neutron-openvswitch-agent restart
    fi

done <<< "${NODE_IDS}"
