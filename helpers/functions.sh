#!/bin/bash

error() {
    printf "\e[31mError: %s\e[0m\n" "${*}" >&2
    exit 1
}

message() {
    printf "\e[33m%s\e[0m\n" "${1}"
}
