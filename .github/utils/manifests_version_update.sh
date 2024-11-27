#!/bin/bash
MANIFESTS_FILE=${1:-""}
RELEASE_VERSION=${2:-""}

update_addon_chart_version() {
    if [[ ! -f "${MANIFESTS_FILE}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=Not found manifests file:${MANIFESTS_FILE} $(tput -T xterm sgr0)"
        return
    fi

    charts_name=$(yq e "to_entries|map(.key)|.[]"  ${MANIFESTS_FILE})
    for chart_name in $(echo "${charts_name}"); do
        is_addon=$(yq e "."${chart_name}"[0].isAddon" ${MANIFESTS_FILE})
        if [[ "$is_addon" == "false" && "${chart_name}" != "minio" ]]; then
            continue
        fi
        chart_version=$(yq e "."${chart_name}"[0].version"  ${MANIFESTS_FILE})
        is_enterprise=$(yq e "."${chart_name}"[0].isEnterprise"  ${MANIFESTS_FILE})

        # update addon isEnterprise
        if [[ "$is_addon" == "true" && -d "${INSTALLER_ADDON_DIR}"  ]]; then
            for installer_addon_chart in $(ls ${INSTALLER_ADDON_DIR}); do
                installer_addon_chart_dir="${INSTALLER_ADDON_DIR}/${installer_addon_chart}"
                installer_addon_enterprise=$(yq e ".isEnterprise"  ${installer_addon_chart_dir})
                installer_addon_name=$(yq e ".name"  ${installer_addon_chart_dir})
                if [[ "$installer_addon_name" == "$chart_name" && "$is_enterprise" != "${installer_addon_enterprise}" ]]; then
                    echo "set ${installer_addon_name} isEnterprise to ${installer_addon_enterprise}"
                    is_enterprise="${installer_addon_enterprise}"
                    yq e -i ".${chart_name}[0].isEnterprise=${installer_addon_enterprise}" "${MANIFESTS_FILE}"
                fi
            done
        fi

        if [[ "$is_enterprise" == "true" ]]; then
            addon_chart_file="${APECLOUD_ADDON_DIR}/${chart_name}/Chart.yaml"
        else
            addon_chart_file="${KUBEBLOCKS_ADDON_DIR}/${chart_name}/Chart.yaml"
        fi

        if [[ -f "${addon_chart_file}" ]]; then
            addon_chart_version=$(yq e ".version" "${addon_chart_file}")
            if [[ "${chart_version}" != "${addon_chart_version}" ]]; then
                yq e -i ".${chart_name}[0].version=\"${addon_chart_version}\"" "${MANIFESTS_FILE}"
                chart_version="${addon_chart_version}"
            fi
        fi

        installer_addon_chart_file="${INSTALLER_ADDON_DIR}/${chart_name}.yaml"
        if [[ -f "${installer_addon_chart_file}" ]]; then
            installer_addon_chart_version=$(yq e ".version" "${installer_addon_chart_file}")
            if [[ "${chart_version}" != "${installer_addon_chart_version}" ]]; then
                yq e -i ".version=\"${chart_version}\"" "${installer_addon_chart_file}"
            fi
        fi
    done
}

update_kbInstaller_version() {
    kbInstaller_version="${1}"
    if [[ ! -f "${INSTALLER_CHART_FILE}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=Not found installer chart values file:${INSTALLER_CHART_FILE} $(tput -T xterm sgr0)"
        return
    fi
    if [[ "$UNAME" == "Darwin" ]]; then
        sed -i '' "s/^  kbInstaller:.*/  kbInstaller: \"${kbInstaller_version}\"/" "${INSTALLER_CHART_FILE}"
    else
        sed -i "s/^  kbInstaller:.*/  kbInstaller: \"${kbInstaller_version}\"/" "${INSTALLER_CHART_FILE}"
    fi
}

update_oteld_version() {
    oteld_version="${1}"
    if [[ ! -f "${INSTALLER_CHART_FILE}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=Not found installer chart values file:${INSTALLER_CHART_FILE} $(tput -T xterm sgr0)"
        return
    fi
    if [[ "$UNAME" == "Darwin" ]]; then
        sed -i '' "s/^  oteld:.*/  oteld: \"${oteld_version}\"/" "${INSTALLER_CHART_FILE}"
    else
        sed -i "s/^  oteld:.*/  oteld: \"${oteld_version}\"/" "${INSTALLER_CHART_FILE}"
    fi
}

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
    update_images=("openconsole" "apiserver" "task-manager" "cubetran-front" "cr4w" "relay" "sentry" "sentry-init" "apecloud-charts" "kubeblocks-installer" "dms" "servicemirror" "kb-cloud-hook" "apecloud-addon-charts")
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
                    if [[ "${manifests_image}" == "apecloud/oteld:"* ]]; then
                        oteld_version="${manifests_image#*:}"
                        update_oteld_version "${oteld_version}"
                    fi

                    if [[ "${manifests_image}" == "apecloud/kubeblocks-installer:"* ]]; then
                        kbInstaller_version="${RELEASE_VERSION}-${KUBEBLOCKS_VERSION}-offline"
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${kbInstaller_version}\"" "${MANIFESTS_FILE}"
                        update_kbInstaller_version "${kbInstaller_version}"
                    elif [[ "${manifests_image}" == "apecloud/dms:"* && -n "${DMS_VERSION}" ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${DMS_VERSION}\"" "${MANIFESTS_FILE}"
                    elif [[ "${manifests_image}" == "apecloud/servicemirror:"* && -n "${SERVICEMIRROR_VERSION}" ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${SERVICEMIRROR_VERSION}\"" "${MANIFESTS_FILE}"
                    elif [[ "${manifests_image}" == "apecloud/apiserver:"* && "${manifests_image}" != "apecloud/apiserver:"*"-jni" ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}\"" "${MANIFESTS_FILE}"
                    elif [[ "${manifests_image}" == "apecloud/apiserver:"*"-jni" ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}-jni\"" "${MANIFESTS_FILE}"
                    else
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}\"" "${MANIFESTS_FILE}"
                    fi
                    break
                fi
            done
            ((image_num++))
        done
    done

    update_addon_chart_version

    echo "update manifests file ${MANIFESTS_FILE} done!"
}

get_dependencies_version() {
    if [[ ! -f "${CLOUD_CHART_FILE}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=Not found cloud chart file:${INSTALLER_CHART_FILE} $(tput -T xterm sgr0)"
        return
    fi
    cloud_dependencies=$(yq e '.dependencies[].name' "${CLOUD_CHART_FILE}")
    if [[ -z "${cloud_dependencies}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=Not found cloud chart dependencies $(tput -T xterm sgr0)"
        return
    fi
    dep_num=0
    for cloud_dependency in $(echo "${cloud_dependencies}"); do
        if [[ "${cloud_dependency}" == "dms" ]]; then
            DMS_VERSION=$(yq e ".dependencies[${dep_num}].version" "${CLOUD_CHART_FILE}")
        elif [[ "${cloud_dependency}" == "servicemirror" ]]; then
            SERVICEMIRROR_VERSION=$(yq e ".dependencies[${dep_num}].version" "${CLOUD_CHART_FILE}")
        fi
        ((dep_num++))
    done
}

main() {
    local RELEASE_VERSION_TMP=""
    local KUBEBLOCKS_VERSION=""
    local UNAME="$(uname -s)"
    local DMS_VERSION=""
    local SERVICEMIRROR_VERSION=""
    local INSTALLER_CHART_FILE="deploy/installer/values.yaml"
    local INSTALLER_ADDON_DIR="docker/kb-installer/addons"
    local CLOUD_CHART_FILE="deploy/helm/Chart.yaml"
    local KUBEBLOCKS_ADDON_DIR="kubeblocks-addons/addons"
    local APECLOUD_ADDON_DIR="apecloud-addons/addons"

    get_dependencies_version
    update_manifests_file_version
}

main "$@"
