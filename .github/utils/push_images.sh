#!/bin/bash

set -e

REGISTRY_ADDRESS=${1:-""}
REGISTRY_USERNAME=${2:-""}
REGISTRY_PASSWORD=${3:-""}

check_push_tool() {
    TOOL_CLI="$( command -v docker )"
    if [[ -z "$TOOL_CLI" ]]; then
        TOOL_CLI="$( command -v sealos )"
    fi

    if [[ -n "$TOOL_CLI" ]]; then
        TOOL_CLI=${TOOL_CLI##*/}
    fi
}

login_registry() {
    if [[ -z "$REGISTRY_USERNAME" || -z "$REGISTRY_PASSWORD" ]]; then
        return
    fi
    echo "Logging into registry: $REGISTRY_ADDRESS"
    for i in {1..3}; do
        echo "${REGISTRY_PASSWORD}" | ${TOOL_CLI} login --password-stdin --username "${REGISTRY_USERNAME}" "${REGISTRY_ADDRESS}"
        login_ret=$?
        if [ $login_ret -eq 0 ]; then
            break
        fi
        echo "retry login registry: $REGISTRY_ADDRESS"
        sleep 1
    done
}

load_image_package() {
    image_package=("${@:4}")
    if [[ -z "$image_package" ]]; then
        return
    fi
    echo "Loading images from package: ${image_package[@]}"
    for image_pkg_name in "${image_package[@]}"; do
        echo "Loading image from file: $image_pkg_name"
        for i in {1..3}; do
            ${TOOL_CLI} load -i "$image_pkg_name"
            load_ret=$?
            if [ $load_ret -eq 0 ]; then
                break
            fi
            echo "retry load image from file: $image_pkg_name"
            sleep 1
        done

    done
}

push_images() {
    images_list_all=""
    if [[ "${TOOL_CLI}" == *"sealos" ]]; then
        images_list_all=$( sealos images --all --format "{{.Name}}:{{.Tag}}" )
    else
        images_list_all=$( docker images --all --format "{{.Repository}}:{{.Tag}}" )
    fi
    images_ret=$?
    if [ $images_ret -ne 0 ]; then
        images_list_all=$( ${TOOL_CLI} images --all | awk '{print $1":"$2}' | grep -v "REPOSITORY:TAG" )
    fi

    if [[ -z "${images_list_all}" ]]; then
        echo "$(tput -T xterm setaf 3)Not found images!$(tput -T xterm sgr0)"
        return
    fi

    images_list=$( echo "$images_list_all" | grep -v "${REGISTRY_ADDRESS}" )

    for image in ${images_list}; do
        new_image=""
        count=$(echo "${image}" | grep -o "/" | wc -l | tr -cd '0-9')
        case $count in
            0|1)
                new_image="${REGISTRY_ADDRESS}/${image}"
            ;;
            *)
                new_image=${image#*/}
                new_image="${REGISTRY_ADDRESS}/${new_image}"
            ;;
        esac
        echo "$new_image"
        for i in {1..3}; do
            ${TOOL_CLI} tag "$image" "$new_image"
            tag_ret=$?
            if [ $tag_ret -eq 0 ]; then
                break
            fi
            echo "retry tag $image to $new_image"
            sleep 1
        done

        for i in {1..3}; do
            ${TOOL_CLI} push "$new_image"
            push_ret=$?
            if [ $push_ret -eq 0 ]; then
                break
            fi
            echo "retry "
            sleep 1
        done
    done
}

main() {
    local TOOL_CLI=""

    if [[ -z "$REGISTRY_ADDRESS" ]]; then
        echo "$(tput -T xterm setaf 1)Please provide registry address!$(tput -T xterm sgr0)"
        return
    fi

    check_push_tool

    if [[ -z "${TOOL_CLI}" ]]; then
        echo "$(tput -T xterm setaf 1)Not found push tool!$(tput -T xterm sgr0)"
        return
    fi

    login_registry

    load_image_package "$@"

    push_images
}

main "$@"
