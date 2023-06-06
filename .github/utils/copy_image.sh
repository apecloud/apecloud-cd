#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_SRC_REGISTRY=docker.io
DEFAULT_DEST_REGISTRY=registry.cn-hangzhou.aliyuncs.com/apecloud

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help                Display help
    -t, --type                Image operation type
                                1) copy to dest registry
    -du, --dest-username      The dest registry username
    -dp, --dest-password      The dest registry password
    -dr, --dest-registry      The dest registry name (default: $DEFAULT_DEST_REGISTRY)
    -si, --src-image         The src image name (e.g. apecloud/apecd)
    -sr, --src-registry       The src registry name (default: $DEFAULT_SRC_REGISTRY)
    -st, --src-tag            The src tag name
EOF
}

main() {
    local DEST_REGISTRY=$DEFAULT_DEST_REGISTRY
    local DEST_USERNAME=
    local DEST_PASSWORD=
    local SRC_REGISTRY=$DEFAULT_SRC_REGISTRY
    local SRC_IMAGE=
    local SRC_TAG=

    parse_command_line "$@"

    if [[ $TYPE == 1 ]]; then
        copy_image
    fi

}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
                ;;
            -t|--type)
                if [[ -n "${2:-}" ]]; then
                    TYPE="$2"
                    shift
                fi
                ;;
            -du|--dest-username)
                if [[ -n "${2:-}" ]]; then
                    DEST_USERNAME="$2"
                    shift
                fi
                ;;
            -dp|--dest-password)
                if [[ -n "${2:-}" ]]; then
                    DEST_PASSWORD="$2"
                    shift
                fi
                ;;
            -i|--src-image)
                if [[ -n "${2:-}" ]]; then
                    SRC_IMAGE="$2"
                    shift
                fi
                ;;
            -sr|--src-registry)
                if [[ -n "${2:-}" ]]; then
                    SRC_REGISTRY="$2"
                    shift
                fi
                ;;
            -st|--src-tag)
                if [[ -n "${2:-}" ]]; then
                    SRC_TAG="$2"
                    shift
                fi
                ;;
            -dr|--dest-registry)
                if [[ -n "${2:-}" ]]; then
                    DEST_REGISTRY="$2"
                    shift
                fi
                ;;
            *)
                break
                ;;
        esac

        shift
    done

}

copy_image() {
    image_name=${SRC_IMAGE##*/}
    echo "copy $SRC_REGISTRY/$SRC_IMAGE:$SRC_TAG to $DEST_REGISTRY/$image_name:$SRC_TAG"
    skopeo copy --all \
        --dest-username "$DEST_USERNAME" \
        --dest-password "$DEST_PASSWORD" \
        docker://$SRC_REGISTRY/$SRC_IMAGE:$SRC_TAG \
        docker://$DEST_REGISTRY/$image_name:$SRC_TAG
}

main "$@"
