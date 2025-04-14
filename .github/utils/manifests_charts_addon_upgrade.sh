#!/bin/bash
MANIFESTS_FILE=${1:-""}


add_chart_repo() {
    echo "helm repo add ${KB_REPO_NAME}  ${KB_REPO_URL}"
    helm repo add ${KB_REPO_NAME} ${KB_REPO_URL}
    helm repo update ${KB_REPO_NAME}

    echo "helm repo add ${KB_ENT_REPO_NAME} --username *** --password *** ${KB_ENT_REPO_URL}"
    helm repo add ${KB_ENT_REPO_NAME} --username ${JIHULAB_ACCESS_USER} --password ${JIHULAB_ACCESS_TOKEN} ${KB_ENT_REPO_URL}
    helm repo update ${KB_ENT_REPO_NAME}
}

upgrade_charts_addon() {
    if [[ ! -f "${MANIFESTS_FILE}" ]]; then
        echo "$(tput -T xterm setaf 1)::error title=Not found manifests file:${MANIFESTS_FILE} $(tput -T xterm sgr0)"
        return
    fi

    upgrade_flag=0
    deploy_addons=$(helm list -n kb-system | (grep "kb-addon-" || true) | awk '{print $1}')
    charts_name=$(yq e "to_entries|map(.key)|.[]"  ${MANIFESTS_FILE})
    for chart_name in $(echo "$charts_name"); do
        # check engine type
        chart_type=$(yq e "."${chart_name}"[0].type"  ${MANIFESTS_FILE})
        if [[ "$chart_type" != "engine" ]]; then
            continue
        fi

        # check deploy addon
        deploy_flag=0
        deploy_addon_tmp=""
        for deploy_addon in $(echo "$deploy_addons"); do
            if [[ "kb-addon-${chart_name}" == "${deploy_addon}" ]]; then
                deploy_flag=1
                deploy_addon_tmp="${deploy_addon}"
                break
            fi
        done

        if [[ $deploy_flag -eq 0 || -z "${deploy_addon_tmp}" ]]; then
            continue
        fi

        # check deploy addon commit id
        deploy_addon_commit_id=""
        if [[ -n "${deploy_addon_tmp}" ]]; then
            deploy_addon_commit_id="$(helm get notes -n kb-system ${deploy_addon_tmp} | (grep "Commit ID:" || true) | awk '{print $3}')"
        fi

        is_enterprise=$(yq e "."${chart_name}"[0].isEnterprise"  ${MANIFESTS_FILE})
        chart_version=$(yq e "."${chart_name}"[0].version"  ${MANIFESTS_FILE})

        helm_chart_repo_tmp="${KB_REPO_NAME}"
        if [[ "$is_enterprise" == "true" ]]; then
            helm_chart_repo_tmp="${KB_ENT_REPO_NAME}"
        fi
        helm pull ${helm_chart_repo_tmp}/${chart_name} --version ${chart_version}  --untar
        release_addon_commit_id=""
        release_addon_note_path="${chart_name}/templates/NOTES.txt"
        if [[ -f "${release_addon_note_path}" ]]; then
            release_addon_commit_id=$(cat "${release_addon_note_path}" | (grep "Commit ID:" || true) | awk '{print $3}')
        fi

        rm -rf ./${chart_name}
        if [[ -n "$deploy_addon_commit_id" && -n "$release_addon_commit_id" && "$deploy_addon_commit_id" == "$release_addon_commit_id" ]]; then
            echo "$(tput -T xterm setaf 3)skip upgrade addon ${chart_name} ${chart_version} with the same commit id$(tput -T xterm sgr0)"
            echo ""
            continue
        fi

        upgrade_flag=1
        echo "deploy addon commit id:  ${deploy_addon_commit_id}"
        echo "release addon commit id: ${release_addon_commit_id}"
        echo "helm upgrade -n kb-system ${deploy_addon_tmp} ${helm_chart_repo_tmp}/${chart_name} --version ${chart_version} --reset-then-reuse-values"
        helm upgrade -n kb-system ${deploy_addon_tmp} ${helm_chart_repo_tmp}/${chart_name} --version ${chart_version} --reset-then-reuse-values
        echo "$(tput -T xterm setaf 2)upgrade addon ${chart_name} ${chart_version} success $(tput -T xterm sgr0)"
        echo ""
    done

    if [[ $upgrade_flag -eq 0 ]]; then
        return
    fi

    echo "annotate unavailable componentDefinition"
    unavailable_cmpds=$(kubectl get componentDefinition | (grep "Unavailable" || true) | awk '{print $1}')
    if [[ -n "${unavailable_cmpds}" ]]; then
        for unavailable_cmpd in $(echo "$unavailable_cmpds"); do
            kubectl annotate componentDefinition unavailable_cmpd apps.kubeblocks.io/skip-immutable-check=true --overwrite=true
        done
    fi
}

main() {
    local KB_REPO_NAME="kb-charts"
    local KB_REPO_URL="https://apecloud.github.io/helm-charts"
    local KB_ENT_REPO_NAME="kb-ent-charts"
    local KB_ENT_REPO_URL="https://jihulab.com/api/v4/projects/${CHART_PROJECT_ID}/packages/helm/stable"
    add_chart_repo

    upgrade_charts_addon
}

main "$@"
