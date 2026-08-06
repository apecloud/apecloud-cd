#!/bin/bash
MANIFESTS_FILE=${1:-""}
ADD_CHART=${2:-"true"}
CHECK_ENGINE_FILE=${3:-"./fountain/hack/check-engine-images.py"}
SKIP_DELETE_FILE=${4:-""}


is_chart_enabled() {
    local chart_name_tmp="${1:-}"
    local deploy_values_file
    deploy_values_file="$(dirname "${MANIFESTS_FILE}")/deploy-values.yaml"
    if [[ ! -f "${deploy_values_file}" ]]; then
        return 0
    fi
    local enable_val
    enable_val=$(yq e ".${chart_name_tmp}.enable" "${deploy_values_file}" 2>/dev/null || echo "true")
    if [[ "${enable_val}" == "false" ]]; then
        echo "$(tput -T xterm setaf 3)Skip check chart ${chart_name_tmp}, enable is false in deploy-values.yaml$(tput -T xterm sgr0)"
        return 1
    fi
    return 0
}

add_chart_repo() {
    echo "helm repo add ${KB_REPO_NAME}  ${KB_REPO_URL}"
    helm repo add ${KB_REPO_NAME} ${KB_REPO_URL}
    helm repo update ${KB_REPO_NAME}

    echo "helm repo add ${KB_ENT_REPO_NAME} --username *** --password *** ${KB_ENT_REPO_URL}"
    helm repo add ${KB_ENT_REPO_NAME} --username ${CHART_ACCESS_USER} --password ${CHART_ACCESS_TOKEN} ${KB_ENT_REPO_URL}
    helm repo update ${KB_ENT_REPO_NAME}
}

check_service_version_images() {
    service_versions_tmp=${1:-""}
    chart_version_tmp=${2:-""}
    chart_name_tmp=${3:-""}
    chart_images_tmp=${4:-""}

    if [[ ! -f "${CHECK_ENGINE_FILE}" ]]; then
        echo "$(tput -T xterm setaf 1)Check engine file not exist, please check$(tput -T xterm sgr0)"
        return
    fi

    # Export env vars so Python script uses the same repos and credentials as Bash
    export COMMUNITY_REPO_NAME="${KB_REPO_NAME}"
    export COMMUNITY_REPO_URL="${KB_REPO_URL}"
    export ENTERPRISE_REPO_NAME="${KB_ENT_REPO_NAME}"
    export ENTERPRISE_REPO_URL="${KB_ENT_REPO_URL}"
    export CHART_ACCESS_USER="${CHART_ACCESS_USER}"
    export CHART_ACCESS_TOKEN="${CHART_ACCESS_TOKEN}"

    check_failed=0
    for j in {1..10}; do
        stderr_file="check-${chart_name_tmp}-${chart_version_tmp}-stderr.log"
        python3 ${CHECK_ENGINE_FILE} -m ${MANIFESTS_FILE} -e ${chart_name_tmp} --addonVersion ${chart_version_tmp} --serviceVersion "${service_versions_tmp}" 2>"${stderr_file}"
        ret_tmp=$?
        check_engine_result_file="images-${chart_name_tmp}-${chart_version_tmp}.yaml"
        images=""
        check_ran_ok=0
        if [[ -f "${check_engine_result_file}" ]]; then
            check_ran_ok=1
            images=$(yq e '.'${chart_name_tmp}'[0].images[]' ${check_engine_result_file} | grep -v 'IMAGE_TAG')
            if [[ -z "${SKIP_DELETE_FILE}" || "${check_engine_result_file}" != *"${SKIP_DELETE_FILE}"* ]]; then
                rm -rf ${check_engine_result_file}
                rm -rf charts/${chart_name_tmp}-${chart_version_tmp}.tgz
            fi
        fi
        repository=""
        for repository in $( echo "$images" ); do
            if [[ "${repository}" == "null" || ("${chart_name_tmp}" == "redis" && "$repository" == "docker.io/busybox:"*) ]]; then
                continue
            fi
            echo "check engine image (${chart_name_tmp} ${chart_version_tmp}): $repository"
            check_flag=0
            for chart_image in $( echo "$chart_images_tmp" ); do
                if [[ "$chart_image" == "$repository" ]]; then
                    check_flag=1
                    break
                fi
            done

            if [[ $check_flag -eq 0 ]]; then
                check_result_tmp="$(tput -T xterm setaf 1)Not found ${chart_name_tmp} ${chart_version_tmp} image:${repository} in manifests file:${MANIFESTS_FILE}$(tput -T xterm sgr0)"
                echo "${check_result_tmp}"
                CHECK_RESULTS="$(cat check_manifest_result)"
                if [[ "${CHECK_RESULTS}" != *"${check_result_tmp}"* ]]; then
                    echo "${check_result_tmp}" >> check_manifest_result
                fi
                echo 1 > exit_result
            fi
            repository=""
        done
        # Success = Python ran and produced a result file.
        # Python exit code 1 just means differences were found, not a runtime failure.
        # We check check_ran_ok (set before we deleted the result file) instead of
        # checking file existence (file is already cleaned up by this point).
        if [[ $check_ran_ok -eq 1 ]]; then
            echo "$(tput -T xterm setaf 2)Check chart ${chart_name_tmp} ${chart_version_tmp} success$(tput -T xterm sgr0)"
            rm -f "${stderr_file}"
            check_failed=0
            break
        fi
        check_failed=1
        sleep 1
    done

    if [[ $check_failed -eq 1 ]]; then
        local log_prefix="[$chart_name_tmp/$chart_version_tmp]"
        check_result_tmp="$(tput -T xterm setaf 1)Failed to check ${chart_name_tmp} ${chart_version_tmp} (chart download or render failed after 10 retries)$(tput -T xterm sgr0)"
        echo "${log_prefix} ${check_result_tmp}"
        stderr_file="check-${chart_name_tmp}-${chart_version_tmp}-stderr.log"
        if [[ -f "${stderr_file}" && -s "${stderr_file}" ]]; then
            echo "${log_prefix} $(tput -T xterm setaf 3)Last attempt stderr:$(tput -T xterm sgr0)"
            cat "${stderr_file}" | sed "s/^/${log_prefix}   /"
            rm -f "${stderr_file}"
        else
            echo "${log_prefix} $(tput -T xterm setaf 3)(no stderr output from check-engine-images.py — script may have failed to start or produced no output)$(tput -T xterm sgr0)"
            rm -f "${stderr_file}"
        fi
        CHECK_RESULTS="$(cat check_manifest_result)"
        if [[ "${CHECK_RESULTS}" != *"${check_result_tmp}"* ]]; then
            echo "${check_result_tmp}" >> check_manifest_result
        fi
        echo "1" > "fail-${chart_name_tmp}-${chart_version_tmp}.flag"
        echo 1 > exit_result
    fi
}

check_images() {
    is_enterprise_tmp=${1:-""}
    chart_version_tmp=${2:-""}
    chart_name_tmp=${3:-""}
    chart_images_tmp=${4:-""}
    set_values_tmp=${5:-""}
    local log_prefix="[$chart_name_tmp/$chart_version_tmp]"
    local helm_stderr="helm-${chart_name_tmp}-${chart_version_tmp}-stderr.log"
    local helm_stdout="helm-${chart_name_tmp}-${chart_version_tmp}-stdout.log"
    for j in {1..10}; do
        template_repo="${KB_REPO_NAME}"
        if [[ "$is_enterprise_tmp" == "true" ]]; then
            template_repo="${KB_ENT_REPO_NAME}"
        fi
        echo "${log_prefix} helm template ${chart_name_tmp} ${template_repo}/${chart_name_tmp} --version ${chart_version_tmp} ${set_values_tmp}"
        # Run helm template separately to capture its real exit code and stderr
        helm template ${chart_name_tmp} ${template_repo}/${chart_name_tmp} --version ${chart_version_tmp} ${set_values_tmp}             > "${helm_stdout}" 2> "${helm_stderr}"
        ret_tmp=$?
        if [[ $ret_tmp -ne 0 ]]; then
            # Check for deterministic errors that should not be retried
            if grep -q "not found in" "${helm_stderr}" 2>/dev/null; then
                echo "${log_prefix} $(tput -T xterm setaf 1)Chart version not found in repo, will not retry.$(tput -T xterm sgr0)"
                cat "${helm_stderr}" | sed "s/^/${log_prefix} (helm stderr) /"
                echo "${log_prefix} $(tput -T xterm setaf 1)Failed to check ${chart_name_tmp} ${chart_version_tmp} (chart version not found)$(tput -T xterm sgr0)" >> check_manifest_result
                echo "1" > "fail-${chart_name_tmp}-${chart_version_tmp}.flag"
                echo 1 > exit_result
                rm -f "${helm_stdout}" "${helm_stderr}"
                return
            fi
            # Retry for transient errors
            if [[ $j -lt 10 ]]; then
                echo "${log_prefix} helm template failed (attempt $j/10), retrying in 1s..."
                sleep 1
                continue
            fi
            # Final failure after all retries
            echo "${log_prefix} $(tput -T xterm setaf 1)helm template failed after 10 retries$(tput -T xterm sgr0)"
            echo "${log_prefix} Last attempt stderr:"
            cat "${helm_stderr}" | sed "s/^/${log_prefix}   /"
            echo "${log_prefix} $(tput -T xterm setaf 1)Failed to check ${chart_name_tmp} ${chart_version_tmp} (helm template failed after 10 retries)$(tput -T xterm sgr0)" >> check_manifest_result
            echo "1" > "fail-${chart_name_tmp}-${chart_version_tmp}.flag"
            echo 1 > exit_result
            rm -f "${helm_stdout}" "${helm_stderr}"
            return
        fi
        # Parse images from stdout
        images=$( cat "${helm_stdout}" | egrep 'image:|repository:|tag:|docker.io/|apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/|ghcr.io/|quay.io/' | (grep -v '[A-Z]' || true) | awk '{print $2}' | sed 's/"//g' )
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
                kubeblocks-cloud)
                    # skip check cloud release images
                    case $repository in
                        */openconsole:*|*/kubeblocks-console:*|*/apiserver:*|*/cr4w:*|*/kb-cloud-hook:*|*/kb-cloud-docs:*|*/kubeblocks-installer:*)
                            repository=""
                        ;;
                    esac
                ;;
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

            if [[ -n "$repository" && ("$repository" == *"apecloud/relay"* || "$repository" == *"apecloud/kubeviewer"* || "$repository" == *"apecloud/be-ubuntu"* || "$repository" == *"apecloud/"*"ubuntu:3.2.2"* || "$repository" == *"apecloud/"*"ubuntu:3.3.0"*  || "$repository" == *"apecloud/"*"ubuntu:3.3.2"*) ]]; then
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
                check_result_tmp="$(tput -T xterm setaf 1)Not found ${chart_name_tmp} ${chart_version_tmp} image:${repository} in manifests file:${MANIFESTS_FILE}$(tput -T xterm sgr0)"
                echo "${check_result_tmp}"
                CHECK_RESULTS="$(cat check_manifest_result)"
                if [[ "${CHECK_RESULTS}" != *"${check_result_tmp}"* ]]; then
                    echo "${check_result_tmp}" >> check_manifest_result
                fi
                echo 1 > exit_result
            fi
            repository=""
        done
        if [[ -n "$images" ]]; then
            echo "${log_prefix} $(tput -T xterm setaf 2)Template chart ${chart_name_tmp} ${chart_version_tmp} success$(tput -T xterm sgr0)"
            rm -f "${helm_stdout}" "${helm_stderr}"
            break
        fi
        # helm template succeeded but no images extracted — might be transient
        if [[ $j -lt 10 ]]; then
            echo "${log_prefix} no images extracted (attempt $j/10), retrying in 1s..."
            sleep 1
        else
            echo "${log_prefix} $(tput -T xterm setaf 1)Failed to check ${chart_name_tmp} ${chart_version_tmp} (no images extracted after 10 retries)$(tput -T xterm sgr0)"
            echo "${log_prefix} $(tput -T xterm setaf 1)Failed to check ${chart_name_tmp} ${chart_version_tmp} (no images extracted after 10 retries)$(tput -T xterm sgr0)" >> check_manifest_result
            echo "1" > "fail-${chart_name_tmp}-${chart_version_tmp}.flag"
            echo 1 > exit_result
            rm -f "${helm_stdout}" "${helm_stderr}"
        fi
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

        if ! is_chart_enabled "$chart_name"; then
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
                check_result_tmp="$(tput -T xterm setaf 1)Not found ${chart_name_tmp} ${chart_version_tmp} image:$repository in manifests file:${MANIFESTS_FILE}$(tput -T xterm sgr0)"
                echo "${check_result_tmp}"
                CHECK_RESULTS="$(cat check_manifest_result)"
                if [[ "${CHECK_RESULTS}" != *"${check_result_tmp}"* ]]; then
                    echo "${check_result_tmp}" >> check_manifest_result
                fi
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
    touch exit_result check_manifest_result
    echo 0 > exit_result
    echo "" > check_manifest_result
    if [[ ! -f "${MANIFESTS_FILE}" ]]; then
        echo "$(tput -T xterm setaf 1)Not found manifests file:${MANIFESTS_FILE} $(tput -T xterm sgr0)"
        return
    fi

    charts_name=$(yq e "to_entries|map(.key)|.[]"  ${MANIFESTS_FILE})
    for chart_name in $(echo "$charts_name"); do
        if [[ -z "$chart_name" || "$chart_name" == "#"* || "$chart_name" == "kata" ]]; then
            continue
        fi

        if ! is_chart_enabled "$chart_name"; then
            continue
        fi

        if [[ -n "${SKIP_DELETE_FILE}" && "${chart_name}" != "${SKIP_DELETE_FILE}" ]]; then
            continue
        fi

        set_values=""
        chart_versions=$(yq e '[.'${chart_name}'[].version] | join("|")' ${MANIFESTS_FILE})
        chart_index=0
        for chart_version in $(echo "$chart_versions" | sed 's/|/ /g'); do
            is_enterprise=$(yq e "."${chart_name}"[${chart_index}].isEnterprise"  ${MANIFESTS_FILE})
            chart_images=$(yq e "."${chart_name}"[${chart_index}].images[]"  ${MANIFESTS_FILE})
            service_versions=""
            if yq e '.'${chart_name}'['${chart_index}'] | has("serviceVersions")' "${MANIFESTS_FILE}" >/dev/null 2>&1; then
                service_versions=$(yq e '[.'${chart_name}'['${chart_index}'].serviceVersions[]] | join(",")' ${MANIFESTS_FILE})
            fi

            if [[ -n "${service_versions}" ]]; then
                check_service_version_images "${service_versions}" "$chart_version" "$chart_name" "$chart_images" &
            else
                case $chart_name in
                    kubeblocks-cloud)
                        set_values="${set_values} --set images.apiserver.tag=${chart_version} "
                        set_values="${set_values} --set images.cr4w.tag=${chart_version} "
                        set_values="${set_values} --set images.openconsole.tag=${chart_version} "
                        set_values="${set_values} --set images.openconsoleAdmin.tag=${chart_version} "
                        set_values="${set_values} --set images.console.tag=${chart_version} "
                        set_values="${set_values} --set images.hook.tag=${chart_version} "
                        set_values="${set_values} --set images.docs.tag=${chart_version} "
                        set_values="${set_values} --set onlyNewConsole=true "
                    ;;
                    ingress-nginx)
                        set_values="${set_values} --set controller.image.image=apecloud/controller "
                        set_values="${set_values} --set controller.image.digest= "
                        set_values="${set_values} --set controller.admissionWebhooks.patch.image.image=apecloud/kube-webhook-certgen "
                        set_values="${set_values} --set controller.admissionWebhooks.patch.image.digest= "
                    ;;
                    kb-cloud-installer|dbdrag)
                        continue
                    ;;
                esac
                if [[ "$chart_name" == "kubeblocks-cloud" ]]; then
                    check_addon_charts_images "$chart_version" "$chart_name" "$chart_images" &
                fi
                check_images "$is_enterprise" "$chart_version" "$chart_name" "$chart_images" "$set_values" &
            fi
            chart_index=$(( $chart_index + 1 ))
        done
    done
    wait

    # Collect and print failure summary
    echo ""
    echo "============================================"
    echo "  FAILURE SUMMARY"
    echo "============================================"
    local fail_count=0
    for f in fail-*.flag; do
        [[ -f "$f" ]] || continue
        local name_ver="${f#fail-}"
        name_ver="${name_ver%.flag}"
        fail_count=$((fail_count + 1))
        echo "  FAIL: ${name_ver}"
        rm -f "$f"
    done
    if [[ $fail_count -eq 0 ]]; then
        echo "  All checks passed."
    else
        echo "--------------------------------------------"
        echo "  Total failed: ${fail_count}"
    fi
    echo "============================================"
    echo ""

    cat check_manifest_result
    cat exit_result
    exit $(cat exit_result)
}

main() {
    local KB_REPO_NAME="kb-charts"
    local KB_REPO_URL="https://apecloud.github.io/helm-charts"
    local KB_ENT_REPO_NAME="kb-ent-charts"
    local KB_ENT_REPO_URL="https://jihulab.com/api/v4/projects/${CHART_PROJECT_ID}/packages/helm/stable"
    if [[ "${ADD_CHART}" == "true" ]]; then
        add_chart_repo
    else
        KB_REPO_NAME="kubeblocks-addons"
        KB_REPO_URL="https://jihulab.com/api/v4/projects/150246/packages/helm/stable"
    fi

    check_charts_images
}

main "$@"
