#!/usr/bin/env bash

DOCKER_USERNAME=$1
DOCKER_PASSWORD=$2
FILE_NAME=$3
REGISTRY=$4
ECR_PASSWORD=$5
ECR_USER=AWS

if [[ -z "$REGISTRY" ]]; then
    REGISTRY=docker.io
fi

while read -r image
do
    skopeo_msg="skopeo sync $REGISTRY/$image to docker.io/apecloud"
    echo "$skopeo_msg"
    skopeo_flag=0
    ret_msg=""
    for i in {1..10}; do
        if [[ "${REGISTRY}" == *"ecr"* ]]; then
            ret_msg=$(skopeo sync --all \
                --src-username "$ECR_USER" \
                --src-password "$ECR_PASSWORD" \
                --dest-username "$ALIYUN_USERNAME" \
                --dest-password "$ALIYUN_PASSWORD" \
                --src docker \
                --dest docker \
                $REGISTRY/$image \
                docker.io/apecloud)
        else
            ret_msg=$(skopeo sync --all \
                --src-username "$DOCKER_USERNAME" \
                --src-password "$DOCKER_PASSWORD" \
                --dest-username "$DOCKER_USERNAME" \
                --dest-password "$DOCKER_PASSWORD" \
                --src docker \
                --dest docker \
                $REGISTRY/$image \
                docker.io/apecloud)
        fi
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
done < $FILE_NAME
