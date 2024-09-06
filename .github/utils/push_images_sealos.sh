#!/bin/bash

set -e

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <registry-address> <docker-image-file>..."
    exit 1
fi
REGISTRY=$1
shift

for DOCKER_IMAGE_FILE in "$@"; do
    echo "Loading image from file: $DOCKER_IMAGE_FILE"
    sealos load -i "$DOCKER_IMAGE_FILE"
done

IMAGES_LIST_FILE="kubeblocks-image-list.txt"

if [ ! -f "$IMAGES_LIST_FILE" ]; then
    echo "Image list file does not exist."
    exit 1
fi

while IFS= read -r image; do
    if [[ $image = \#* ||  -z "$image" ]]; then
        continue
    fi

    image_name=$(echo "$image" | cut -d":" -f1)
    image_tag=$(echo "$image" | cut -d":" -f2)
    name_prefix="${image_name%%/*}"

    if [[ "$name_prefix" != "$image_name" ]]; then
        new_image_name="${image_name/$name_prefix/$REGISTRY}"
    else
        new_image_name="${REGISTRY}/${image_name}"
    fi

    if [[ -z "$image_tag" ]]; then
        image_tag="latest"
    fi

    new_image="${new_image_name}:${image_tag}"
    if [[ "$image" == "docker.io/library/"* ]]; then
        image=${image/docker.io\/library\//localhost\/}
    elif [[ "$image" == "docker.io/"* ]]; then
        image=${image/docker.io\//localhost\/}
    fi
    sealos tag "$image" "$new_image"
    sealos push "$new_image"

done < "$IMAGES_LIST_FILE"