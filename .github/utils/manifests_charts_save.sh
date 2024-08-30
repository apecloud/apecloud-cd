#!/bin/bash
MANIFESTS_FILE=${1:-""}
RELEASE_VERSION=${2:-""}
KB_CHART_NAME=${3:-"kubeblocks-enterprise-charts"}
APPS_DIR=${4:-"apps"}


save_charts_package() {
    if [[ ! -f "${MANIFESTS_FILE}" ]]; then
        echo "$(tput -T xterm setaf 1)::error title=Not found manifests file:${MANIFESTS_FILE} $(tput -T xterm sgr0)"
        return
    fi

    mkdir -p ${KB_CHART_NAME}/apps

    if [[ -d ${APPS_DIR} ]]; then
        echo "cp -r ${APPS_DIR} to ${KB_CHART_NAME}/apps"
        cp -r ${APPS_DIR}/* ${KB_CHART_NAME}/apps/
    elif [[ -d apecloud-cd/${APPS_DIR} ]]; then
        echo "cp -r apecloud-cd/${APPS_DIR} to ${KB_CHART_NAME}/apps"
        cp -r apecloud-cd/${APPS_DIR}/* ${KB_CHART_NAME}/apps/
    fi

    charts_name=$(yq e "to_entries|map(.key)|.[]"  ${MANIFESTS_FILE})
    tar_flag=0
    for i in {1..10}; do
        for chart_name in $(echo "$charts_name"); do
            ent_flag=0
            if [[ -z "$chart_name" || "$chart_name" == "#"* ]]; then
                continue
            fi
            chart_version=$(yq e "."${chart_name}"[0].version"  ${MANIFESTS_FILE})
            chart_tmp="${chart_name}-${chart_version}"
            case $chart_name in
                kubeblocks-cloud)
                    if [[ -z "$RELEASE_VERSION" ]]; then
                        RELEASE_VERSION="${chart_version}"
                    fi
                    APP_PKG_NAME="${KB_CHART_NAME}-${RELEASE_VERSION}.tar.gz"
                    echo "helm repo add ${ENT_REPO_NAME} --username ${CHART_ACCESS_USER} --password ${CHART_ACCESS_TOKEN} ${KB_ENT_REPO_URL}"
                    helm repo add ${ENT_REPO_NAME} --username ${CHART_ACCESS_USER} --password ${CHART_ACCESS_TOKEN} ${KB_ENT_REPO_URL}
                    helm repo update ${ENT_REPO_NAME}
                    ent_flag=1
                ;;
                starrocks|oceanbase)
                    ent_flag=1
                ;;
            esac

            echo "fetch chart $chart_tmp"
            for j in {1..10}; do
                if [[ $ent_flag -eq 1 ]]; then
                    helm pull -d ${KB_CHART_NAME} ${ENT_REPO_NAME}/${chart_name} --version ${chart_version}
                else
                    helm fetch -d ${KB_CHART_NAME} "$REPO_URL/${chart_tmp}/${chart_tmp}.tgz"
                fi
                ret_msg=$?
                if [[ $ret_msg -eq 0 ]]; then
                    echo "$(tput -T xterm setaf 2)fetch chart $chart_tmp success$(tput -T xterm sgr0)"
                    break
                fi
                sleep 1
            done
        done
        echo "tar ${KB_CHART_NAME}"
        tar -czvf ${APP_PKG_NAME} ${KB_CHART_NAME}
        ret_msg=$?
        if [[ $ret_msg -eq 0 ]]; then
            echo "$(tput -T xterm setaf 2)tar ${APP_PKG_NAME} success$(tput -T xterm sgr0)"
            tar_flag=1
            break
        fi
        sleep 1
    done
    if [[ $tar_flag -eq 0 ]]; then
        echo "$(tput -T xterm setaf 1)tar ${APP_PKG_NAME} error$(tput -T xterm sgr0)"
        exit 1
    fi
}

main() {
    local ENT_REPO_NAME="kb-ent"
    local APP_PKG_NAME=""
    local REPO_URL="https://github.com/apecloud/helm-charts/releases/download"
    local KB_ENT_REPO_URL="https://jihulab.com/api/v4/projects/${CHART_PROJECT_ID}/packages/helm/stable"

    save_charts_package
}

main "$@"
