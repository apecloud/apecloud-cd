#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_SRC_REGISTRY=docker.io
DEFAULT_DEST_REGISTRY=apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help                Display help
    -t, --type                Image operation type
                                1) copy to dest registry
    -du, --dest-username      The dest registry username
    -dp, --dest-password      The dest registry password
    -dr, --dest-registry      The dest registry name (default: $DEFAULT_DEST_REGISTRY)
    -si, --src-image         The src image name (e.g. apecloud/apecloud-cd)
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
    skopeo_msg="skopeo copy $SRC_REGISTRY/$SRC_IMAGE:$SRC_TAG to $DEST_REGISTRY/$image_name:$SRC_TAG"
    echo "$skopeo_msg"
    skopeo_flag=0
    for i in {1..10}; do
        ret_msg=$(skopeo copy --all \
            --dest-username "$DEST_USERNAME" \
            --dest-password "$DEST_PASSWORD" \
            docker://$SRC_REGISTRY/$SRC_IMAGE:$SRC_TAG \
            docker://$DEST_REGISTRY/$image_name:$SRC_TAG)
        echo "return message:$ret_msg"
        if [[ "$ret_msg" == *"Storing list signatures"* || "$ret_msg" == *"Skipping"* ]]; then
            echo "$(tput -T xterm setaf 2)$skopeo_msg success$(tput -T xterm sgr0)"
            skopeo_flag=1
            break
        fi
        sleep 1
    done
    if [[ $skopeo_flag -eq 0 ]]; then
        echo "$(tput -T xterm setaf 1)$skopeo_msg error$(tput -T xterm sgr0)"
        exit 1
    fi
}

main "$@"
