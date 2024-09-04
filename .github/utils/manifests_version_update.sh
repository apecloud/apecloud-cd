#!/bin/bash
MANIFESTS_FILE=${1:-""}
RELEASE_VERSION=${2:-""}


update_manifests_file_version() {
    echo "MANIFESTS_FILE:${MANIFESTS_FILE}"
    if [[ ! -f "${MANIFESTS_FILE}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=Not found manifests file:${MANIFESTS_FILE} $(tput -T xterm sgr0)"
        return
    fi

    if [[ -z "${RELEASE_VERSION}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=release version is empty $(tput -T xterm sgr0)"
        return
    fi
    echo "RELEASE_VERSION:${RELEASE_VERSION}"
    if [[ "${RELEASE_VERSION}" != "v"* ]]; then
        RELEASE_VERSION="v${RELEASE_VERSION}"
    fi
    RELEASE_VERSION_TMP=${RELEASE_VERSION/v/}

    KUBEBLOCKS_VERSION=$(yq e ".kubeblocks[0].version" "${MANIFESTS_FILE}")

    echo "KUBEBLOCKS_VERSION:${KUBEBLOCKS_VERSION}"
    charts_name=("kubeblocks-cloud" "kb-cloud-installer")
    update_images=("openconsole" "apiserver" "task-manager" "cubetran-front" "cr4w" "relay" "sentry" "sentry-init" "apecloud-charts" "kubeblocks-installer")
    for chart_name in "${charts_name[@]}"; do
        if [[ "${chart_name}" == "kb-cloud-installer" ]]; then
            yq e -i ".${chart_name}[0].version=\"${RELEASE_VERSION_TMP}\"" "${MANIFESTS_FILE}"
            update_images=("kb-cloud-installer")
        else
            yq e -i ".${chart_name}[0].version=\"${RELEASE_VERSION}\"" "${MANIFESTS_FILE}"
        fi

        manifests_images=$(yq e ".${chart_name}[0].images[]" ${MANIFESTS_FILE})
        image_num=0
        for manifests_image in $(echo "${manifests_images}"); do
            for update_image in "${update_images[@]}"; do
                if [[ "${manifests_image}" == "apecloud/${update_image}:"* ]]; then
                    if [[ "${manifests_image}" == "apecloud/kubeblocks-installer:"* ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}-${KUBEBLOCKS_VERSION}-offline\"" "${MANIFESTS_FILE}"
                    else
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}\"" "${MANIFESTS_FILE}"
                    fi
                    if [[ "${manifests_image}" == "apecloud/apiserver:"* && "${RELEASE_VERSION}" == "v0.25."* ]]; then
                        ((image_num++))
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}-jni\"" "${MANIFESTS_FILE}"
                    fi
                    break
                fi
            done
            ((image_num++))
        done
    done
    echo "update manifests file ${MANIFESTS_FILE} done!"
}


main() {
    local RELEASE_VERSION_TMP=""
    local KUBEBLOCKS_VERSION=""

    update_manifests_file_version
}

main "$@"
