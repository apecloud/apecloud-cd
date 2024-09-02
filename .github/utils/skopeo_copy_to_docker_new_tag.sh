#!/usr/bin/env bash

DOCKER_USERNAME=$1
DOCKER_PASSWORD=$2
SRC_IMAGE=$3
DEST_TAG=$4
SRC_REGISTRY=${5:-"docker.io"}
DEST_REGISTRY=${6:-"docker.io"}


main() {
    image_name=${SRC_IMAGE##*/}
    skopeo_msg="skopeo copy $SRC_REGISTRY/$SRC_IMAGE to $DEST_REGISTRY/apecloud/$image_name:$DEST_TAG"
    echo "$skopeo_msg"
    skopeo_flag=0
    ret_msg=""
    for i in {1..10}; do
        ret_msg=$(skopeo copy --all \
            --dest-username "${DOCKER_USERNAME}" \
            --dest-password "${DOCKER_PASSWORD}" \
            --src-username "${DOCKER_USERNAME}" \
            --src-password "${DOCKER_PASSWORD}" \
            docker://$SRC_REGISTRY/$SRC_IMAGE \
            docker://$DEST_REGISTRY/apecloud/$image_name:$DEST_TAG)
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
