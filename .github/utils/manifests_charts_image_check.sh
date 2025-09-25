#!/bin/bash
MANIFESTS_FILE=${1:-""}


add_chart_repo() {
    echo "helm repo add ${KB_REPO_NAME}  ${KB_REPO_URL}"
    helm repo add ${KB_REPO_NAME} ${KB_REPO_URL}
    helm repo update ${KB_REPO_NAME}

    echo "helm repo add ${KB_ENT_REPO_NAME} --username *** --password *** ${KB_ENT_REPO_URL}"
    helm repo add ${KB_ENT_REPO_NAME} --username ${CHART_ACCESS_USER} --password ${CHART_ACCESS_TOKEN} ${KB_ENT_REPO_URL}
    helm repo update ${KB_ENT_REPO_NAME}
}

check_images() {
    is_enterprise_tmp=${1:-""}
    chart_version_tmp=${2:-""}
    chart_name_tmp=${3:-""}
    chart_images_tmp=${4:-""}
    set_values_tmp=${5:-""}
    for j in {1..10}; do
        template_repo="${KB_REPO_NAME}"
        if [[ "$is_enterprise_tmp" == "true" ]]; then
            template_repo="${KB_ENT_REPO_NAME}"
        fi
        echo "helm template ${chart_name_tmp} ${template_repo}/${chart_name_tmp} --version ${chart_version_tmp} ${set_values_tmp}"
        images=$( helm template ${chart_name_tmp} ${template_repo}/${chart_name_tmp} --version ${chart_version_tmp} ${set_values_tmp} | egrep 'image:|repository:|tag:|docker.io/|apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/|infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com/|ghcr.io/|quay.io/' | awk '{print $2}' | sed 's/"//g' )
        ret_tmp=$?
        repository=""
        for image in $( echo "$images" ); do
            if [[ $image == *":"* ]]; then
                repository=$image
            elif [[ -z "$repository" || "$image" == *"/"* ]]; then
                repository=$image
                continue
            elif [[ -z "$image" || "$image" == "''" ]]; then
                repository=""
                continue
            else
                repository=$repository:$image
            fi

            case $chart_name_tmp in
                kubeblocks)
                    case $repository in
                        */prometheus:*|*/grafana:*|*/k8s-sidecar:*|*/alertmanager:*|*/configmap-reload:*|*/configmap-reload:*|*/node-exporter:*)
                            repository=""
                        ;;
                    esac
                ;;
                gemini)
                    case $repository in
                        */datasafed:*|busybox:busybox)
                            repository=""
                        ;;
                    esac
                ;;
                gemini-monitor)
                    case $repository in
                        */oteld:*)
                            repository=""
                        ;;
                    esac
                ;;
            esac

            if [[ -z "$repository" || "$repository" == "image:" || "$repository" == *':$('*')' || "$repository" == *"''" || "$repository" == *":'"*"'" ]]; then
                repository=""
                continue
            fi

            if [[ -n "$repository" && ("$repository" == *"apecloud/dm:8.1.4-6-20241231"* || "$repository" == *"apecloud/relay"* || "$repository" == *"apecloud/kubeviewer"*) ]]; then
                repository=""
                continue
            fi

            if [[ "$repository" == "'"*"'" ]]; then
                repository=${repository//\'/}
            fi

            echo "check image: $repository"
            repository=apecloud/${repository##*/}
            check_flag=0
            for chart_image in $( echo "$chart_images_tmp" ); do
                if [[ "$chart_image" == "$repository" ]]; then
                    check_flag=1
                    break
                fi
            done

            if [[ $check_flag -eq 0 ]]; then
                echo "$(tput -T xterm setaf 1)::error title=Not found ${chart_name_tmp} ${chart_version_tmp} image:$repository in manifests file:${MANIFESTS_FILE}$(tput -T xterm sgr0)"
                echo 1 > exit_result
            fi
            repository=""
        done
        if [[ $ret_tmp -eq 0 && -n "$images" ]]; then
            echo "$(tput -T xterm setaf 2)Template chart ${chart_name_tmp} ${chart_version_tmp} success$(tput -T xterm sgr0)"
            break
        fi
        sleep 1
    done
}

check_addon_charts_images() {
    chart_version_tmp=${1:-""}
    chart_name_tmp=${2:-""}
    chart_images_tmp=${3:-""}
    addon_charts_images=""
    charts_name=$(yq e "to_entries|map(.key)|.[]"  ${MANIFESTS_FILE})
    for chart_name in $(echo "$charts_name"); do
        if [[ -z "$chart_name" || "$chart_name" == "#"* || "$chart_name" == "kata" ]]; then
            continue
        fi

        if [[ "$chart_name" == "apecloud-mysql" || "$chart_name" == "mogdb" || "$chart_name" == "greatsql" ]]; then
            continue
        fi
        chart_versions=$(yq e '[.'${chart_name}'[].version] | join("|")' ${MANIFESTS_FILE})
        chart_index=0
        for chart_version in $(echo "$chart_versions" | sed 's/|/ /g'); do
            engine_type=$(yq e "."${chart_name}"[${chart_index}].type"  ${MANIFESTS_FILE})
            if [[ "${engine_type}" == "engine" ]]; then
            addon_charts_image="apecloud/apecloud-addon-charts:${chart_name}-${chart_version}"
            addon_charts_images="${addon_charts_images}|${addon_charts_image}"
            fi
            chart_index=$(( $chart_index + 1 ))
        done
    done
    if [[ -n "$addon_charts_images" ]]; then
        repository=""
        check_flag_all=0
        for image in $( echo "$addon_charts_images" | sed 's/|/ /g'); do
            repository=$image
            echo "check image: $repository"
            check_flag=0
            for chart_image in $( echo "$chart_images_tmp" ); do
                if [[ "$chart_image" == "$repository" ]]; then
                    check_flag=1
                    break
                fi
            done

            if [[ $check_flag -eq 0 ]]; then
                check_flag_all=1
                echo "$(tput -T xterm setaf 1)::error title=Not found ${chart_name_tmp} ${chart_version_tmp} image:$repository in manifests file:${MANIFESTS_FILE}$(tput -T xterm sgr0)"
                echo 1 > exit_result
            fi
            repository=""
        done
        if [[ $check_flag_all -eq 0 ]]; then
            echo "$(tput -T xterm setaf 2)Check addon charts in ${chart_name_tmp} ${chart_version_tmp} success$(tput -T xterm sgr0)"
        fi
    fi
}

check_charts_images() {
    touch exit_result
    echo 0 > exit_result
    if [[ ! -f "${MANIFESTS_FILE}" ]]; then
        echo "$(tput -T xterm setaf 1)::error title=Not found manifests file:${MANIFESTS_FILE} $(tput -T xterm sgr0)"
        return
    fi

    charts_name=$(yq e "to_entries|map(.key)|.[]"  ${MANIFESTS_FILE})
    for chart_name in $(echo "$charts_name"); do
        if [[ -z "$chart_name" || "$chart_name" == "#"* || "$chart_name" == "kata" ]]; then
            continue
        fi
        set_values=""
        chart_versions=$(yq e '[.'${chart_name}'[].version] | join("|")' ${MANIFESTS_FILE})
        chart_index=0
        for chart_version in $(echo "$chart_versions" | sed 's/|/ /g'); do
            is_enterprise=$(yq e "."${chart_name}"[${chart_index}].isEnterprise"  ${MANIFESTS_FILE})
            chart_images=$(yq e "."${chart_name}"[${chart_index}].images[]"  ${MANIFESTS_FILE})
            case $chart_name in
                kubeblocks-cloud)
                    set_values="${set_values} --set images.apiserver.tag=${chart_version} "
                    set_values="${set_values} --set images.sentry.tag=${chart_version} "
                    set_values="${set_values} --set images.sentryInit.tag=${chart_version} "
                    set_values="${set_values} --set images.relay.tag=${chart_version} "
                    set_values="${set_values} --set images.cr4w.tag=${chart_version} "
                    set_values="${set_values} --set images.openconsole.tag=${chart_version} "
                    set_values="${set_values} --set images.openconsoleAdmin.tag=${chart_version} "
                    set_values="${set_values} --set images.taskManager.tag=${chart_version} "
                ;;
                kb-cloud-installer)
                    set_values="${set_values} --set version=${chart_version} "
                ;;
                ingress-nginx)
                    set_values="${set_values} --set controller.image.image=apecloud/controller "
                    set_values="${set_values} --set controller.image.digest= "
                    set_values="${set_values} --set controller.admissionWebhooks.patch.image.image=apecloud/kube-webhook-certgen "
                    set_values="${set_values} --set controller.admissionWebhooks.patch.image.digest= "
                ;;
                gemini)
                    set_values="${set_values} --set cr-exporter.enabled=true "
                ;;
                kubebench)
                    set_values="${set_values} --set image.tag=0.0.12 "
                    set_values="${set_values} --set kubebenchImages.exporter=apecloud/kubebench:0.0.12"
                    set_values="${set_values} --set kubebenchImages.tools=apecloud/kubebench:0.0.12"
                ;;
                dbdrag)
                    continue
                ;;
            esac
            if [[ "$chart_name" == "kubeblocks-cloud" ]]; then
                check_addon_charts_images "$chart_version" "$chart_name" "$chart_images" &
            fi
            check_images "$is_enterprise" "$chart_version" "$chart_name" "$chart_images" "$set_values" &
            chart_index=$(( $chart_index + 1 ))
        done
    done
    wait
    cat exit_result
    exit $(cat exit_result)
}

main() {
    local KB_REPO_NAME="kb-charts"
    local KB_REPO_URL="https://apecloud.github.io/helm-charts"
    local KB_ENT_REPO_NAME="kb-ent-charts"
    local KB_ENT_REPO_URL="https://jihulab.com/api/v4/projects/${CHART_PROJECT_ID}/packages/helm/stable"
    add_chart_repo
    check_charts_images
}

main "$@"
