#!/usr/bin/env bash

set -o nounset

DEFAULT_DELETE_FORCE="false"
REGISTRY_DEFAULT=docker.io

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help                Display help
    -t, --type                Operation type
                                1) remove v prefix
                                2) replace '-' with '.'
                                3) get release asset upload url
                                4) get latest release tag
                                5) update release latest
                                6) get the ci trigger mode
                                7) trigger other repo actions workflow
                                8) delete release version
                                9) delete release charts
                                10) delete docker images
                                11) delete aliyun images
                                12) get test result
                                13) helm dep update
                                14) get delete alpha/beta release
                                15) comment issue
                                16) delete runner
                                17) get job url
                                18) delete aliyun images new
                                19) delete helm-charts index
                                20) get incremental chart package
                                21) set pr size label
                                22) set pr milestone
                                23) set issue milestone
                                24) move pr/issue to next milestone
                                25) remove runner
                                26) set images list
                                27) generate image yaml
                                28) get release branch
                                29) delete tag
                                30) delete actions cache
                                31) check release version
                                32) generate image yaml apecloud
                                33) set label
                                34) get e2e tes _result
                                35) bump chart version
                                36) parse test result
                                37) update k3d coredns configmap
                                38) get cloud test result
                                39) get cloud pre version
                                40) get ginkgo test result
                                41) get ginkgo test result total
                                42) set api coverage result url
                                43) set engine summary result url
                                44) get github actions job url
                                45) set engine summary result url2
                                46) get playwright test result
                                47) get playwright test result total
                                48) get cloud delete release
                                49) delete release chart
    -tn, --tag-name           Release tag name
    -gr, --github-repo        Github Repo
    -gt, --github-token       Github token
    -bn, --branch-name        The branch name that triggers the workflow
    -wi, --workflow-id        The workflow id that triggers the workflow
    -v, --version             Release version
    -u, --user                The docker registry user
    -p, --password            The docker registry password
    -df, --delete-force       Force to delete stable release (default: DEFAULT_DELETE_FORCE)
    -ri, --run-id             The github run id
    -tr, --test-result        The test result
    -cr, --coverage-result    The api coverage result
    -cp, --chart-path         The chart path
    -in, --issue-number       The issue number
    -ic, --issue-comment      The issue comment body
    -jn, --job-name           The github runner job name
    -pn, --pr-number          The pull request number
    -ln, --limit-number       Maximum number of issues/pulls to fetch
    -rn, --runner-name        The runner name
    -i, --images              Docker images
    -il, --images-list        Docker images list
    -ea, --extra-args         The extra args for workflow
    -r, --registry            Docker image registry (default: $REGISTRY_DEFAULT)
    -lb, --label-name         The pr label name
    -lo, --label-ops          The pr label ops (add/remove)
    -ru, --report-url         The test report url
    -tt, --test-type          The test type for e2e
EOF
}

GITHUB_API="https://api.github.com"
DEFAULT_GITHUB_REPO=apecloud/kubeblocks

is_number() {
    if [[ "$1" =~ ^-?[0-9]+$ ]]; then
        echo "true"
    else
        echo "false"
    fi
}

gh_curl() {
    if [[ -z "$GITHUB_TOKEN" ]]; then
        curl -H "Accept: application/vnd.github.v3.raw" \
            $@
    else
        curl -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3.raw" \
            $@
    fi
}

get_upload_url() {
    gh_curl -s $GITHUB_API/repos/$GITHUB_REPO/releases/tags/$TAG_NAME > release_body.json
    echo $(jq '.upload_url' release_body.json) | sed 's/\"//g'
}

get_latest_tag() {
    latest_release_tag=`gh_curl -s $GITHUB_API/repos/$GITHUB_REPO/releases/latest | jq -r '.tag_name'`
    echo $latest_release_tag
}

update_release_latest() {
    release_id=`gh_curl -s $GITHUB_API/repos/$GITHUB_REPO/releases/tags/$TAG_NAME | jq -r '.id'`

    gh_curl -X PATCH \
        $GITHUB_API/repos/$GITHUB_REPO/releases/$release_id \
        -d '{"draft":false,"prerelease":false,"make_latest":true}'
}

add_trigger_mode() {
    trigger_mode=$1
    if [[ "$TRIGGER_MODE" != *"$trigger_mode"* ]]; then
        TRIGGER_MODE=$trigger_mode$TRIGGER_MODE
    fi
}

trigger_repo_workflow() {
    data='{"ref":"'$BRANCH_NAME'"}'
    if [[ -n "$EXTRA_ARGS" ]]; then
        extra_args_json=""
        if [[ -n "$VERSION" ]]; then
            extra_args_json="\"VERSION\":\"$VERSION\""
        fi
        if [[ -n "$TEST_TYPE" ]]; then
            extra_args_json="\"TEST_TYPE\":\"$TEST_TYPE\""
        fi
        for extra_arg in $(echo "$EXTRA_ARGS" | sed 's/#/ /g'); do
            extra_arg_key=${extra_arg%=*}
            extra_arg_value=${extra_arg#*=}
            if [[ -n "$extra_args_json" ]]; then
                extra_args_json="$extra_args_json,\"$extra_arg_key\":\"$extra_arg_value\""
            else
                extra_args_json="\"$extra_arg_key\":\"$extra_arg_value\""
            fi
        done
        if [[ -n "$BRANCH_NAME" ]]; then
            data='{"ref":"'$BRANCH_NAME'","inputs":{'$extra_args_json'}}'
        else
            data='{"ref":"main","inputs":{'$extra_args_json'}}'
        fi
    elif [[ -n "$VERSION" ]]; then
        if [[ -n "$BRANCH_NAME" ]]; then
            data='{"ref":"'$BRANCH_NAME'","inputs":{"VERSION":"'$VERSION'"}}'
        else
            data='{"ref":"main","inputs":{"VERSION":"'$VERSION'"}}'
        fi
    fi
    echo "data:"$data
    gh_curl -X POST \
        $GITHUB_API/repos/$GITHUB_REPO/actions/workflows/$WORKFLOW_ID/dispatches \
        -d $data
}

get_trigger_mode() {
    for filePath in $( git diff --name-only HEAD HEAD^ ); do
        if [[ "$filePath" == "go."* ]]; then
            add_trigger_mode "[test]"
            continue
        elif [[ "$filePath" != *"/"* ]]; then
            add_trigger_mode "[other]"
            continue
        fi

        case $filePath in
            docs/*)
                add_trigger_mode "[docs]"
            ;;
            docker/*)
                add_trigger_mode "[docker]"
            ;;
            deploy/*)
                add_trigger_mode "[deploy]"
            ;;
            .github/*|.devcontainer/*|githooks/*|examples/*)
                add_trigger_mode "[other]"
            ;;
            internal/cli/cmd/*)
                add_trigger_mode "[cli][test]"
            ;;
            *)
                add_trigger_mode "[test]"
            ;;
        esac
    done
    echo $TRIGGER_MODE
}

check_stable_release() {
    release_tag="v"*"."*"."*
    not_stable_release_tag="v"*"."*"."*"-"*
    if [[ -z "$TAG_NAME" || ("$TAG_NAME" == $release_tag && "$TAG_NAME" != $not_stable_release_tag) ]]; then
        echo "1"
    else
        echo "0"
    fi
}

delete_tag() {
    echo "delete $GITHUB_REPO tag $TAG_NAME"
    gh_curl -s -X DELETE  $GITHUB_API/repos/$GITHUB_REPO/git/refs/tags/$TAG_NAME
}

delete_release_versions_all() {
    local versions_str="$TAG_NAME"
    if [[ "$versions_str" != *"|"* ]]; then
        delete_release_version
        return
    fi
    local -a versions
    IFS='|' read -r -a versions <<< "$versions_str"
    for version in "${versions[@]}"; do
        TAG_NAME="$version"
        delete_release_version
    done
}

delete_release_version() {
    release_id=$( gh_curl -s $GITHUB_API/repos/$GITHUB_REPO/releases/tags/$TAG_NAME | jq -r '.id' )
    if [[ -n "$release_id" && "$release_id" != "null" ]]; then
        echo "delete $GITHUB_REPO release $TAG_NAME"
        gh_curl -s -X DELETE $GITHUB_API/repos/$GITHUB_REPO/releases/$release_id
    else
        echo "delete $GITHUB_REPO release $TAG_NAME via gh cli"
        gh release delete "$TAG_NAME" --repo $GITHUB_REPO --yes
    fi
    delete_tag
}

filter_charts() {
    while read -r chart; do
        chart_dir=$DELETE_CHARTS_DIR/$chart
        if [[ ! -d "$chart_dir" ]]; then
            echo "not found chart dir $chart_dir"
            continue
        fi
        local file="$chart_dir/Chart.yaml"
        if [[ -f "$file" ]]; then
            chart_name=$(cat $file | yq eval '.name' -)
            echo "delete chart $chart_name-$TAG_NAME_TMP"
            TAG_NAME="$chart_name-$TAG_NAME_TMP"
            delete_release_version &
        fi
    done
    wait
}

delete_release_charts() {
    local DELETE_CHARTS_DIR=""
    for charts_dir in $(echo "deploy" | sed 's/|/ /g'); do
        if [[ ! -d "$charts_dir" ]]; then
            echo "not found chart dir $charts_dir"
            continue
        fi
        DELETE_CHARTS_DIR=$charts_dir
        charts_files=$( ls -1 $charts_dir )
        echo "$charts_files" | filter_charts
    done
}

delete_kubeblocks_release_charts_all() {
    local versions_str="$TAG_NAME"
    if [[ "$versions_str" != *"|"* ]]; then
        delete_kubeblocks_release_chart
        return
    fi
    local -a versions
    IFS='|' read -r -a versions <<< "$versions_str"
    for version in "${versions[@]}"; do
        local clean_v="${version/v/}"
        TAG_NAME_TMP="$clean_v"
        delete_kubeblocks_release_chart
    done
}

delete_kubeblocks_release_chart() {
    chart_file="deploy/helm/Chart.yaml"
    if [[ -f "$chart_file" ]]; then
        chart_name=$(cat $chart_file | yq eval '.name' -)
        echo "delete chart $chart_name-$TAG_NAME_TMP"
        TAG_NAME="$chart_name-$TAG_NAME_TMP"
        delete_release_version
    fi
}

delete_release_charts_all() {
    local versions_str="$TAG_NAME"
    if [[ "$versions_str" != *"|"* ]]; then
        delete_release_chart
        return
    fi
    local -a versions
    IFS='|' read -r -a versions <<< "$versions_str"
    for version in "${versions[@]}"; do
        local clean_v="${version/v/}"
        TAG_NAME_TMP="$clean_v"
        delete_release_chart
    done
}

delete_release_chart() {
    if [[ -n "$CHART_PATH" ]]; then
        for chart_name in $(echo "$CHART_PATH" | sed 's/|/ /g'); do
            echo "delete chart $chart_name-$TAG_NAME_TMP"
            if [[ "$chart_name" == "kubeblocks-cloud" ]]; then
                TAG_NAME="$chart_name-v$TAG_NAME_TMP"
            else
                TAG_NAME="$chart_name-$TAG_NAME_TMP"
            fi
            delete_release_version
        done
    fi
}

delete_docker_images() {
    local -a images=(
        "apecloud/kubeblocks"
        "apecloud/kubeblocks-tools"
        "apecloud/kubeblocks-datascript"
        "apecloud/kubeblocks-charts"
        "apecloud/kubeblocks-dataprotection"
    )

    local -a versions
    IFS='|' read -r -a versions <<< "$TAG_NAME_TMP"

    local fail_count=0
    local total_count=0

    for version in "${versions[@]}"; do
        (
            for image in "${images[@]}"; do
                echo "delete $image:$version"
                ((total_count++))
                if ! docker run --rm \
                        apecloud/remove-dockerhub-tag \
                        --user "$USER" \
                        --password "$PASSWORD" \
                        "$image:$version"; then
                    echo "error: failed to delete $image:$version" >&2
                    ((fail_count++))
                fi
            done
        ) &
    done
    wait

    if [[ $fail_count -gt 0 ]]; then
        echo "$(tput -T xterm setaf 1)$fail_count/$total_count deletions failed$(tput -T xterm sgr0)"
    else
        echo "$(tput -T xterm setaf 2)all $total_count images deleted$(tput -T xterm sgr0)"
    fi
}

delete_aliyun_images_generic() {
    local registry_domain=${1:-""}
    if [[ -z "$registry_domain" ]]; then
        echo "error: registry domain is required" >&2
        return 1
    fi

    local -a images=(
        "kubeblocks"
        "kubeblocks-tools"
        "kubeblocks-datascript"
        "kubeblocks-charts"
        "kubeblocks-dataprotection"
    )

    local -a versions
    IFS='|' read -r -a versions <<< "$TAG_NAME_TMP"

    local fail_count=0
    local total_count=0
    local max_concurrent=10
    local current_jobs=0

    for version in "${versions[@]}"; do
        (
            for image in "${images[@]}"; do
                echo "delete $registry_domain/apecloud/$image:$version"
                ((total_count++))
                if ! skopeo delete \
                        --creds "$USER:$PASSWORD" \
                        "docker://${registry_domain}/apecloud/${image}:${version}"; then
                    echo "error: failed to delete ${image}:${version}" >&2
                    ((fail_count++))
                fi
            done
        ) &
        ((current_jobs++))
        if [[ $current_jobs -ge $max_concurrent ]]; then
            wait -n
            ((current_jobs--))
        fi
    done
    wait

    if [[ $fail_count -gt 0 ]]; then
        echo "$(tput -T xterm setaf 1)$fail_count/$total_count deletions failed$(tput -T xterm sgr0)"
    else
        echo "$(tput -T xterm setaf 2)all $total_count images deleted$(tput -T xterm sgr0)"
    fi
}


delete_aliyun_images() {
    delete_aliyun_images_generic "apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com"
}

delete_aliyun_images_new() {
    delete_aliyun_images_generic "infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com"
}

#!/bin/bash

# ==================== Version comparison functions ====================
# Check if version $1 <= $2
version_le() { [ "$1" = "$2" ] || [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]; }
# Check if version $1 >= $2
version_ge() { [ "$1" = "$2" ] || [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]; }
# Check if version $1 < $2
version_lt() { [ "$1" != "$2" ] && [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]; }
# Check if version $1 > $2
version_gt() { [ "$1" != "$2" ] && [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]; }
# Check if $1 is within [$2, $3] (inclusive)
version_in_range() { version_ge "$1" "$2" && version_le "$1" "$3"; }

# ==================== kubeblocks-installer suffix mapping ====================
# Returns the middle suffix for kubeblocks-installer based on the version.
# The final tag is constructed as: ${version}${suffix}-offline
get_kubeblocks_installer_suffix() {
    local ver="$1"
    # v0.28.0-alpha.30 ~ v0.28.1-alpha.0
    if version_in_range "$ver" "v0.28.0-alpha.30" "v0.28.1-alpha.0"; then
        echo "-0.9.1-beta.18"
    # v0.29.0-alpha.0 ~ v0.29.0-alpha.58
    elif version_in_range "$ver" "v0.29.0-alpha.0" "v0.29.0-alpha.58"; then
        echo "-0.9.1"
    # v0.29.0-alpha.59 ~ v0.29.0-alpha.70
    elif version_in_range "$ver" "v0.29.0-alpha.59" "v0.29.0-alpha.70"; then
        echo "-0.9.2-beta.7"
    # v0.29.0-alpha.71 ~ v0.29.0-alpha.73
    elif version_in_range "$ver" "v0.29.0-alpha.71" "v0.29.0-alpha.73"; then
        echo "-0.9.2-beta.13"
    # v0.29.0-alpha.74 ~ v0.29.0-alpha.90
    elif version_in_range "$ver" "v0.29.0-alpha.74" "v0.29.0-alpha.90"; then
        echo "-0.9.2-beta.16"
    # v0.29.0-alpha.91 ~ v0.29.0-alpha.130
    elif version_in_range "$ver" "v0.29.0-alpha.91" "v0.29.0-alpha.130"; then
        echo "-0.9.2-beta.20"
    # v0.29.0-alpha.131 ~ v0.29.0-alpha.169
    elif version_in_range "$ver" "v0.29.0-alpha.131" "v0.29.0-alpha.169"; then
        echo "-0.9.2"
    # v0.30.0-alpha.0 ~ v0.30.0-alpha.86
    elif version_in_range "$ver" "v0.30.0-alpha.0" "v0.30.0-alpha.86"; then
        echo "-0.9.2"
    # v0.30.0-alpha.87 ~ v0.31.0-alpha.39
    elif version_in_range "$ver" "v0.30.0-alpha.87" "v0.31.0-alpha.39"; then
        echo "-0.9.3-beta.22"
    # v0.31.0-alpha.40 ~ v0.31.0-alpha.43
    elif version_in_range "$ver" "v0.31.0-alpha.40" "v0.31.0-alpha.43"; then
        echo "-0.9.3-beta.24"
    # v0.31.0-alpha.44 ~ v0.31.0-alpha.60
    elif version_in_range "$ver" "v0.31.0-alpha.44" "v0.31.0-alpha.60"; then
        echo "-0.9.3-beta.25"
    # v0.31.0-alpha.61 ~ v0.31.0-alpha.76
    elif version_in_range "$ver" "v0.31.0-alpha.61" "v0.31.0-alpha.76"; then
        echo "-0.9.3"
    # v0.31.0-alpha.77 ~ v0.31.0-alpha.80
    elif version_in_range "$ver" "v0.31.0-alpha.77" "v0.31.0-alpha.80"; then
        echo "-0.9.4-beta.1"
    # v0.31.0-alpha.81 ~ v0.31.0-alpha.99
    elif version_in_range "$ver" "v0.31.0-alpha.81" "v0.31.0-alpha.99"; then
        echo "-0.9.4-beta.2"
    # v0.31.0-alpha.100 ~ v0.31.0-alpha.102
    elif version_in_range "$ver" "v0.31.0-alpha.100" "v0.31.0-alpha.102"; then
        echo "-0.9.4-beta.3"
    # v0.31.0-alpha.103 ~ v0.31.0-alpha.107
    elif version_in_range "$ver" "v0.31.0-alpha.103" "v0.31.0-alpha.107"; then
        echo "-0.9.4-beta.4"
    # v0.31.0-alpha.108 ~ v0.31.0-alpha.112
    elif version_in_range "$ver" "v0.31.0-alpha.108" "v0.31.0-alpha.112"; then
        echo "-0.9.4-beta.5"
    # v0.31.0-alpha.114
    elif [ "$ver" = "v0.31.0-alpha.114" ]; then
        echo "-0.9.4-beta.6"
    # v0.31.0-alpha.115 ~ v0.31.0-alpha.127
    elif version_in_range "$ver" "v0.31.0-alpha.115" "v0.31.0-alpha.127"; then
        echo "-0.9.4-beta.7"
    # v0.31.0-alpha.128 ~ v0.31.0-alpha.134
    elif version_in_range "$ver" "v0.31.0-alpha.128" "v0.31.0-alpha.134"; then
        echo "-0.9.4-beta.10"
    # v0.31.0-alpha.135 ~ v0.31.0-alpha.146
    elif version_in_range "$ver" "v0.31.0-alpha.135" "v0.31.0-alpha.146"; then
        echo "-0.9.4-beta.11"
    # v0.31.0-alpha.147 ~ v0.31.0-alpha.152
    elif version_in_range "$ver" "v0.31.0-alpha.147" "v0.31.0-alpha.152"; then
        echo "-0.9.4-beta.13"
    # v1.1.0-alpha.0 ~ v1.1.0-alpha.14
    elif version_in_range "$ver" "v1.1.0-alpha.0" "v1.1.0-alpha.14"; then
        echo "-0.9.4-beta.14"
    # v1.1.0-alpha.15
    elif [ "$ver" = "v1.1.0-alpha.15" ]; then
        echo "-0.9.4-beta.16"
    # v1.1.0-alpha.16
    elif [ "$ver" = "v1.1.0-alpha.16" ]; then
        echo "-0.9.4-beta.17"
    # v1.1.0-alpha.17 ~ v1.1.0-alpha.21
    elif version_in_range "$ver" "v1.1.0-alpha.17" "v1.1.0-alpha.21"; then
        echo "-0.9.4-beta.18"
    # v1.1.0-alpha.22 ~ v1.1.0-alpha.39
    elif version_in_range "$ver" "v1.1.0-alpha.22" "v1.1.0-alpha.39"; then
        echo "-0.9.4-beta.19"
    # v1.1.0-alpha.40 ~ v1.1.0-alpha.41
    elif version_in_range "$ver" "v1.1.0-alpha.40" "v1.1.0-alpha.41"; then
        echo "-0.9.4-beta.23"
    # v1.1.0-alpha.42 ~ v1.1.0-alpha.47
    elif version_in_range "$ver" "v1.1.0-alpha.42" "v1.1.0-alpha.47"; then
        echo "-0.9.4-beta.26"
    # v1.1.0-alpha.48 ~ v1.1.0-alpha.71
    elif version_in_range "$ver" "v1.1.0-alpha.48" "v1.1.0-alpha.71"; then
        echo "-0.9.4-beta.27"
    # v1.2.0-alpha.0 ~ v1.2.0-alpha.12
    elif version_in_range "$ver" "v1.2.0-alpha.0" "v1.2.0-alpha.12"; then
        echo "-0.9.4-beta.27"
    # v1.2.0-alpha.13 ~ v1.2.0-alpha.18
    elif version_in_range "$ver" "v1.2.0-alpha.13" "v1.2.0-alpha.18"; then
        echo "-0.9.4-beta.31"
    # v1.2.0-alpha.19 ~ v1.2.0-alpha.62
    elif version_in_range "$ver" "v1.2.0-alpha.19" "v1.2.0-alpha.62"; then
        echo "-0.9.4-beta.32"
    # v1.2.0-alpha.63 ~ v1.2.0-alpha.89
    elif version_in_range "$ver" "v1.2.0-alpha.63" "v1.2.0-alpha.89"; then
        echo "-0.9.5-beta.2"
    # v1.2.0-alpha.90 ~ v1.2.0-alpha.94
    elif version_in_range "$ver" "v1.2.0-alpha.90" "v1.2.0-alpha.94"; then
        echo "-0.9.5-beta.4"
    # v1.2.0-alpha.95 ~ v1.2.0-alpha.104
    elif version_in_range "$ver" "v1.2.0-alpha.95" "v1.2.0-alpha.104"; then
        echo "-0.9.5-beta.5"
    # v1.2.0-alpha.105 ~ v1.2.0-alpha.118
    elif version_in_range "$ver" "v1.2.0-alpha.105" "v1.2.0-alpha.118"; then
        echo "-0.9.5-beta.6"
    # v1.2.0-alpha.119 ~ v1.2.0-alpha.123
    elif version_in_range "$ver" "v1.2.0-alpha.119" "v1.2.0-alpha.123"; then
        echo "-0.9.5-beta.8"
    # v1.2.0-alpha.124 and above (including v2.x series) - no extra suffix
    elif version_ge "$ver" "v1.2.0-alpha.124"; then
        echo ""
    else
        # Fallback: return empty suffix for unknown versions
        echo ""
    fi
}

# ==================== Docker Hub deletion function ====================
delete_docker_images_cloud() {
    local -a images=(
        "apecloud/openconsole"
        "apecloud/apiserver"
        "apecloud/task-manager"
        "apecloud/cubetran-front"
        "apecloud/cr4w"
        "apecloud/relay"
        "apecloud/sentry"
        "apecloud/sentry-init"
        "apecloud/apecloud-charts"
        "apecloud/kb-cloud-installer"
        "apecloud/kubeblocks-console"
        "apecloud/kb-cloud-hook"
        "apecloud/kb-cloud-docs"
        "apecloud/kubeblocks-installer"
    )

    local -a versions
    IFS='|' read -r -a versions <<< "$TAG_NAME"

    local fail_count=0
    local total_count=0
    local max_concurrent=5
    local current_jobs=0

    for version in "${versions[@]}"; do
        (
            for image in "${images[@]}"; do
                local short_name="${image#apecloud/}"
                local should_delete=false
                local -a extra_tags=()

                case "$short_name" in
                    "kb-cloud-installer")
                        if version_ge "$version" "v0.24.0-alpha.36"; then
                            should_delete=true
                        fi
                        ;;
                    "apecloud-charts")
                        if version_in_range "$version" "v0.12.0-alpha.0" "v0.30.0-alpha.26"; then
                            should_delete=true
                        fi
                        ;;
                    "sentry"|"sentry-init")
                        if version_in_range "$version" "v0.5.0-alpha.6" "v0.31.0-alpha.8"; then
                            should_delete=true
                        fi
                        ;;
                    "relay")
                        if version_in_range "$version" "v0.6.0-alpha.4" "v0.31.0-alpha.66"; then
                            should_delete=true
                        fi
                        ;;
                    "cr4w")
                        if version_ge "$version" "v0.21.0-alpha.6"; then
                            should_delete=true
                        fi
                        ;;
                    "cubetran-front")
                        if version_in_range "$version" "v0.5.6-alpha.1" "v2.2.0-alpha.195"; then
                            should_delete=true
                        fi
                        ;;
                    "task-manager")
                        if version_le "$version" "v0.31.0-alpha.8"; then
                            should_delete=true
                        fi
                        ;;
                    "apiserver")
                        should_delete=true
                        if version_in_range "$version" "v0.25.0-alpha.0" "v0.26.0-alpha.9"; then
                            extra_tags+=("${version}-jni")
                        fi
                        ;;
                    "openconsole")
                        if version_le "$version" "v0.9.0-alpha.3"; then
                            should_delete=false
                            extra_tags+=("default-${version}" "managed-${version}" "anywhere-${version}")
                        elif version_in_range "$version" "v0.31.0-alpha.23" "v2.3.0-alpha.1"; then
                            should_delete=true
                            extra_tags+=("${version}-admin" "${version}-console")
                        elif version_le "$version" "v0.31.0-alpha.23"; then
                            should_delete=true
                        else
                            should_delete=false
                        fi
                        ;;
                    "kubeblocks-console")
                        if version_ge "$version" "v2.2.0-alpha.76"; then
                            should_delete=true
                            if version_ge "$version" "v2.3.0-alpha.56"; then
                                extra_tags+=("${version}-rds")
                            fi
                        fi
                        ;;
                    "kb-cloud-hook")
                        if version_ge "$version" "v0.28.0-alpha.102"; then
                            should_delete=true
                        fi
                        ;;
                    "kb-cloud-docs")
                        if version_ge "$version" "v1.1.0-alpha.9"; then
                            should_delete=true
                        fi
                        ;;
                    "kubeblocks-installer")
                        # For Docker Hub, tags follow the same pattern as Alibaba Cloud.
                        if version_ge "$version" "v0.28.0-alpha.30"; then
                            suffix=$(get_kubeblocks_installer_suffix "$version")
                            if [[ -n "$suffix" ]]; then
                                full_tag="${version}${suffix}-offline"
                            else
                                full_tag="${version}-offline"
                            fi
                            echo "delete $image:$full_tag"
                            ((total_count++))
                            if ! docker run --rm \
                                    apecloud/remove-dockerhub-tag \
                                    --user "$USER" \
                                    --password "$PASSWORD" \
                                    "$image:$full_tag"; then
                                echo "error: failed to delete $image:$full_tag" >&2
                                ((fail_count++))
                            fi
                        fi
                        # Do not attempt to delete the plain ${version} tag
                        continue
                        ;;
                    *)
                        should_delete=true
                        ;;
                esac

                # Delete the primary tag if needed
                if $should_delete; then
                    echo "delete $image:$version"
                    ((total_count++))
                    if ! docker run --rm \
                            apecloud/remove-dockerhub-tag \
                            --user "$USER" \
                            --password "$PASSWORD" \
                            "$image:$version"; then
                        echo "error: failed to delete $image:$version" >&2
                        ((fail_count++))
                    fi
                fi

                # Delete any extra tags
                for extra_tag in "${extra_tags[@]}"; do
                    echo "delete $image:$extra_tag"
                    ((total_count++))
                    if ! docker run --rm \
                            apecloud/remove-dockerhub-tag \
                            --user "$USER" \
                            --password "$PASSWORD" \
                            "$image:$extra_tag"; then
                        echo "error: failed to delete $image:$extra_tag" >&2
                        ((fail_count++))
                    fi
                done
            done
        ) &
        ((current_jobs++))
        if [[ $current_jobs -ge $max_concurrent ]]; then
            wait -n
            ((current_jobs--))
        fi
    done
    wait

    if [[ $fail_count -gt 0 ]]; then
        echo "$(tput -T xterm setaf 1)$fail_count/$total_count deletions failed$(tput -T xterm sgr0)"
    else
        echo "$(tput -T xterm setaf 2)all $total_count images deleted$(tput -T xterm sgr0)"
    fi
}

# ==================== Alibaba Cloud deletion function ====================
delete_aliyun_images_generic_cloud() {
    local registry_domain=${1:-""}
    if [[ -z "$registry_domain" ]]; then
        echo "error: registry domain is required" >&2
        return 1
    fi

    local -a images=(
        "apecloud/openconsole"
        "apecloud/apiserver"
        "apecloud/task-manager"
        "apecloud/cubetran-front"
        "apecloud/cr4w"
        "apecloud/relay"
        "apecloud/sentry"
        "apecloud/sentry-init"
        "apecloud/apecloud-charts"
        "apecloud/kb-cloud-installer"
        "apecloud/kubeblocks-console"
        "apecloud/kb-cloud-hook"
        "apecloud/kb-cloud-docs"
        "apecloud/kubeblocks-installer"
    )

    local -a versions
    IFS='|' read -r -a versions <<< "$TAG_NAME"

    local fail_count=0
    local total_count=0
    local max_concurrent=10
    local current_jobs=0

    for version in "${versions[@]}"; do
        # Alibaba Cloud registry only contains images from v0.15.0-alpha.10 onward
        if version_lt "$version" "v0.15.0-alpha.10"; then
            echo "skip version $version (Alibaba Cloud images do not exist below v0.15.0-alpha.10)" >&2
            continue
        fi

        (
            for image in "${images[@]}"; do
                local short_name="${image#apecloud/}"
                local should_delete=false
                local -a extra_tags=()

                case "$short_name" in
                    "kb-cloud-installer")
                        if version_ge "$version" "v0.24.0-alpha.36"; then
                            should_delete=true
                        fi
                        ;;
                    "apecloud-charts")
                        if version_in_range "$version" "v0.12.0-alpha.0" "v0.30.0-alpha.26"; then
                            should_delete=true
                        fi
                        ;;
                    "sentry"|"sentry-init")
                        if version_in_range "$version" "v0.5.0-alpha.6" "v0.31.0-alpha.8"; then
                            should_delete=true
                        fi
                        ;;
                    "relay")
                        if version_in_range "$version" "v0.6.0-alpha.4" "v0.31.0-alpha.66"; then
                            should_delete=true
                        fi
                        ;;
                    "cr4w")
                        if version_ge "$version" "v0.21.0-alpha.6"; then
                            should_delete=true
                        fi
                        ;;
                    "cubetran-front")
                        if version_in_range "$version" "v0.5.6-alpha.1" "v2.2.0-alpha.195"; then
                            should_delete=true
                        fi
                        ;;
                    "task-manager")
                        if version_le "$version" "v0.31.0-alpha.8"; then
                            should_delete=true
                        fi
                        ;;
                    "apiserver")
                        should_delete=true
                        if version_in_range "$version" "v0.25.0-alpha.0" "v0.26.0-alpha.9"; then
                            extra_tags+=("${version}-jni")
                        fi
                        ;;
                    "openconsole")
                        if version_le "$version" "v0.9.0-alpha.3"; then
                            should_delete=false
                            extra_tags+=("default-${version}" "managed-${version}" "anywhere-${version}")
                        elif version_in_range "$version" "v0.31.0-alpha.23" "v2.3.0-alpha.1"; then
                            should_delete=true
                            extra_tags+=("${version}-admin" "${version}-console")
                        elif version_le "$version" "v0.31.0-alpha.23"; then
                            should_delete=true
                        else
                            should_delete=false
                        fi
                        ;;
                    "kubeblocks-console")
                        if version_ge "$version" "v2.2.0-alpha.76"; then
                            should_delete=true
                            if version_ge "$version" "v2.3.0-alpha.56"; then
                                extra_tags+=("${version}-rds")
                            fi
                        fi
                        ;;
                    "kb-cloud-hook")
                        if version_ge "$version" "v0.28.0-alpha.102"; then
                            should_delete=true
                        fi
                        ;;
                    "kb-cloud-docs")
                        if version_ge "$version" "v1.1.0-alpha.9"; then
                            should_delete=true
                        fi
                        ;;
                    "kubeblocks-installer")
                        # Tags are of the form ${version}${suffix}-offline. Use suffix mapping.
                        if version_ge "$version" "v0.28.0-alpha.30"; then
                            suffix=$(get_kubeblocks_installer_suffix "$version")
                            if [[ -n "$suffix" ]]; then
                                full_tag="${version}${suffix}-offline"
                            else
                                full_tag="${version}-offline"
                            fi
                            full_image="${registry_domain}/${image}:${full_tag}"
                            echo "delete $full_image"
                            ((total_count++))
                            if ! skopeo delete \
                                    --creds "$USER:$PASSWORD" \
                                    "docker://${full_image}"; then
                                echo "error: failed to delete ${image}:${full_tag}" >&2
                                ((fail_count++))
                            fi
                        fi
                        # Skip primary tag deletion (does not exist)
                        continue
                        ;;
                    *)
                        should_delete=true
                        ;;
                esac

                # Delete primary tag if needed
                if $should_delete; then
                    full_image="${registry_domain}/${image}:${version}"
                    echo "delete $full_image"
                    ((total_count++))
                    if ! skopeo delete \
                            --creds "$USER:$PASSWORD" \
                            "docker://${full_image}"; then
                        echo "error: failed to delete ${image}:${version}" >&2
                        ((fail_count++))
                    fi
                fi

                # Delete any extra tags
                for extra_tag in "${extra_tags[@]}"; do
                    extra_full_image="${registry_domain}/${image}:${extra_tag}"
                    echo "delete $extra_full_image"
                    ((total_count++))
                    if ! skopeo delete \
                            --creds "$USER:$PASSWORD" \
                            "docker://${extra_full_image}"; then
                        echo "error: failed to delete ${image}:${extra_tag}" >&2
                        ((fail_count++))
                    fi
                done
            done
        ) &
        ((current_jobs++))
        if [[ $current_jobs -ge $max_concurrent ]]; then
            wait -n
            ((current_jobs--))
        fi
    done
    wait

    if [[ $fail_count -gt 0 ]]; then
        echo "$(tput -T xterm setaf 1)$fail_count/$total_count deletions failed$(tput -T xterm sgr0)"
    else
        echo "$(tput -T xterm setaf 2)all $total_count images deleted$(tput -T xterm sgr0)"
    fi
}

delete_aliyun_images_cloud() {
    delete_aliyun_images_generic_cloud "apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com"
}

set_runs_jobs() {
    jobs_name=$1
    jobs_url=$2
    for test_ret in `echo "$TEST_RESULT" | sed 's/##/ /g'`; do
        test_type=${test_ret%%|*}
        if [[ "$jobs_name" == *"$test_type" && "$jobs_name" != *"-${test_type}" ]]; then
            TEST_RET=$TEST_RET"##$test_ret|$jobs_url"
        fi
    done
}

get_test_result() {
    for i in {1..2}; do
        jobs_url="$GITHUB_API/repos/$GITHUB_REPO/actions/runs/$RUN_ID/jobs?per_page=200&page=$i"
        jobs_list=$( gh_curl -s $jobs_url )
        total_count=$( echo "$jobs_list" | jq '.total_count' )
        if [[ "$total_count" == "null" || $(is_number "$total_count") == "false" ]]; then
            echo "total_count:${total_count}"
            break
        fi
        for i in $(seq 0 $total_count); do
            if [[ "$i" == "$total_count" ]]; then
                break
            fi
            jobs_name=$( echo "$jobs_list" | jq ".jobs[$i].name" --raw-output )
            jobs_url=$( echo "$jobs_list" | jq ".jobs[$i].html_url" --raw-output )
            set_runs_jobs "$jobs_name" "$jobs_url"
        done
    done
    echo "$TEST_RET"
}

set_e2e_runs_jobs() {
    jobs_name=$1
    jobs_url=$2
    for test_ret in `echo "$TEST_RESULT" | sed 's/##/ /g'`; do
        test_type=${test_ret%|*}
        if [[ "$jobs_name" == *"$test_type"* ]]; then
            TEST_RET=$TEST_RET"##$test_ret|$jobs_url"
        fi
    done
}

get_e2e_test_result() {
    for i in {1..2}; do
        jobs_url="$GITHUB_API/repos/$GITHUB_REPO/actions/runs/$RUN_ID/jobs?per_page=200&page=$i"
        jobs_list=$( gh_curl -s $jobs_url )
        total_count=$( echo "$jobs_list" | jq '.total_count' )
        if [[ "$total_count" == "null" || $(is_number "$total_count") == "false" ]]; then
            echo "total_count:${total_count}"
            break
        fi
        for i in $(seq 0 $total_count); do
            if [[ "$i" == "$total_count" ]]; then
                break
            fi
            jobs_name=$( echo "$jobs_list" | jq ".jobs[$i].steps[7].name" --raw-output )
            jobs_url=$( echo "$jobs_list" | jq ".jobs[$i].html_url" --raw-output )
            set_e2e_runs_jobs "$jobs_name" "$jobs_url"
        done
    done
    echo "$TEST_RET"
}

set_ginkgo_runs_jobs() {
    jobs_name=$1
    jobs_url=$2

    ginkgo_test=0
    if [[ "$TEST_RESULT" == *"SUCCESS!"*"--"* || "$TEST_RESULT" == *"FAIL!"*"--"* ]]; then
        TEST_RESULT="$(echo "${TEST_RESULT}" | sed 's/ /#/g')"
        ginkgo_test=1
    fi
    for test_ret in `echo "$TEST_RESULT" | sed 's/##/ /g'`; do
        test_type=${test_ret%%|*}

        if [[ "$jobs_name" == *"$test_type" && "$jobs_name" != *"-${test_type}" ]]; then
            if [[ $ginkgo_test -eq 1 ]]; then
                test_ret="$(echo "${test_ret}" | sed 's/#/ /g')"
            fi
            TEST_RET=$TEST_RET"##$test_ret|$jobs_url"
        fi
    done
}

get_ginkgo_test_result() {
    for i in {1..2}; do
        jobs_url="$GITHUB_API/repos/$GITHUB_REPO/actions/runs/$RUN_ID/jobs?per_page=200&page=$i"
        jobs_list=$( gh_curl -s $jobs_url )
        total_count=$( echo "$jobs_list" | jq '.total_count' )
        if [[ "$total_count" == "null" || $(is_number "$total_count") == "false" ]]; then
            echo "total_count:${total_count}"
            break
        fi
        for i in $(seq 0 $total_count); do
            if [[ "$i" == "$total_count" ]]; then
                break
            fi
            jobs_name=$( echo "$jobs_list" | jq ".jobs[$i].name" --raw-output )
            jobs_url=$( echo "$jobs_list" | jq ".jobs[$i].html_url" --raw-output )
            set_ginkgo_runs_jobs "$jobs_name" "$jobs_url"
        done
    done
    echo "$TEST_RET"
}

get_playwright_test_result() {
    local FINAL_RESULT="$TEST_RESULT"
    local jobs_url

    for i in {1..2}; do
        jobs_url_api="$GITHUB_API/repos/$GITHUB_REPO/actions/runs/$RUN_ID/jobs?per_page=200&page=$i"
        jobs_list=$( gh_curl -s "$jobs_url_api" )
        total_count=$( echo "$jobs_list" | jq '.total_count' )
        if [[ "$total_count" == "null" || $(is_number "$total_count") == "false" ]]; then
            echo "total_count:${total_count}"
            break
        fi

        for j in $(seq 0 $total_count); do
            if [[ "$j" == "$total_count" ]]; then
                break
            fi

            local jobs_name
            jobs_name=$( echo "$jobs_list" | jq ".jobs[$j].name" --raw-output )
            jobs_url=$( echo "$jobs_list" | jq ".jobs[$j].html_url" --raw-output )

            local job_keys=("$jobs_name")
            if [[ ${#jobs_name} -gt 3 ]]; then
                job_keys+=("${jobs_name:1}")
            fi

            local key_found=false

            for search_key in "${job_keys[@]}"; do

                local search_pattern="###${search_key}###"
                local replacement_pattern="###${search_key}###${jobs_url}###"

                if [[ "$FINAL_RESULT" == *"$search_pattern"* ]]; then
                    FINAL_RESULT=$(echo "$FINAL_RESULT" | sed "s|${search_pattern}|${replacement_pattern}|g")
                    key_found=true
                    break
                fi
            done

        done
    done

    echo "$FINAL_RESULT"
}

get_playwright_test_result_total() {
    local cleaned_data_block
    local TEST_RESULT_SAFE="$TEST_RESULT"
    echo "TEST_RESULT: $TEST_RESULT"

    cleaned_data_block=$(printf "%s" "$TEST_RESULT_SAFE" | \
        tr -d '\r\t\xa0' | \
        tr '\n' ' ' | \
        tr -s ' ' | \
        sed -E 's/.*RESULT[[:space:]]*//' | \
        sed -E 's/[[:space:]]*PLAYWRIGHT TEST (SUCCESS!|FAILED, CODE: [0-9]+)$//' | \
        xargs
    )

    if [[ -z "$cleaned_data_block" ]]; then
        return 0
    fi

    local engine_type
    engine_type=$(printf "%s" "$cleaned_data_block" | awk '{print $1}')

    if [[ -z "$engine_type" ]]; then
        return 0
    fi

    local accumulated_specs
    accumulated_specs=$(printf "%s" "$cleaned_data_block" | awk -v expected_engine="$engine_type" '
    {
        FS="[[:space:]]+"
        accumulated_specs = ""

        for (i = 1; i <= NF; i += 3) {

            if (i + 2 <= NF && $i == expected_engine) {
                spec = $(i + 1)
                result = $(i + 2)

                current_pair = spec "##" result

                if (accumulated_specs == "") {
                    accumulated_specs = current_pair
                } else {
                    accumulated_specs = accumulated_specs "##" current_pair
                }
            }
        }
    }

    END {
        printf "%s", accumulated_specs
    }')

    if [[ -n "$accumulated_specs" ]]; then
        echo "###$engine_type###$accumulated_specs"
    fi

}

set_cloud_test_runs_jobs() {
    jobs_name=$1
    jobs_url=$2
    for test_ret in `echo "$TEST_RESULT" | sed 's/##/ /g'`; do
        test_type=${test_ret%%|*}
        test_type2=${test_ret#*|}
        if [[ "$jobs_name" == *"$test_type" && "$jobs_name" != *"-${test_type}" ]]; then
            TEST_RET=$TEST_RET"##$test_type2|$jobs_url"
        fi
    done
}

get_cloud_test_result() {
    for i in {1..2}; do
        jobs_url="$GITHUB_API/repos/$GITHUB_REPO/actions/runs/$RUN_ID/jobs?per_page=200&page=$i"
        jobs_list=$( gh_curl -s $jobs_url )
        total_count=$( echo "$jobs_list" | jq '.total_count' )
        if [[ "$total_count" == "null" || $(is_number "$total_count") == "false" ]]; then
            echo "total_count:${total_count}"
            break
        fi
        for i in $(seq 0 $total_count); do
            if [[ "$i" == "$total_count" ]]; then
                break
            fi
            jobs_name=$( echo "$jobs_list" | jq ".jobs[$i].name" --raw-output )
            jobs_url=$( echo "$jobs_list" | jq ".jobs[$i].html_url" --raw-output )
            set_cloud_test_runs_jobs "$jobs_name" "$jobs_url"
        done
    done
    echo "$TEST_RET"
}

get_job_url() {
    JOB_URL=""
    jobs_url="$GITHUB_API/repos/$GITHUB_REPO/actions/runs/$RUN_ID/jobs?per_page=200&page=1"
    jobs_list=$( gh_curl -s $jobs_url )
    total_count=$( echo "$jobs_list" | jq '.total_count' )
    if [[ "$total_count" == "null" || $(is_number "$total_count") == "false" ]]; then
        echo "total_count:${total_count}"
        return
    fi
    for i in $(seq 0 $total_count); do
        job_name=$( echo "$jobs_list" | jq ".jobs[$i].name" --raw-output )
        if [[ "$job_name" == *"$JOB_NAME" ]]; then
            JOB_URL=$( echo "$jobs_list" | jq ".jobs[$i].html_url" --raw-output )
            break
        fi
    done
    echo "$JOB_URL"
}

helm_dep_update() {
    for chartPath in $(echo "$CHART_PATH" | sed 's/|/ /g'); do
        if [[ "$chartPath" == *"/"* ]]; then
            echo "helm dep update $chartPath"
            helm dep update $chartPath
        else
            echo "helm dep update deploy/$chartPath"
            helm dep update deploy/$chartPath
        fi
    done
}

set_delete_release(){
    if [[ -z "$TAG_NAME" ]]; then
        return
    fi
    if [[ -z "$DELETE_RELEASE" ]]; then
        DELETE_RELEASE="$TAG_NAME"
    else
        DELETE_RELEASE="$DELETE_RELEASE|$TAG_NAME"
    fi
}

get_delete_release() {
    release_list=$( gh release list --repo $GITHUB_REPO --limit 100 | (grep "Pre-release" || true) )
    for tag in $( echo "$release_list" ) ;do
        delete_flag=0

        if [[ "$tag" == *"0.6.0-beta.11"* || "$tag" == *"0.9.0-alpha.2"* || "$tag" == *"0.8.3-beta.9"* || "$tag" == *"0.8.4-beta.0"* ]]; then
            TAG_NAME=""
            continue
        fi

        if [[ "$tag" == "Pre-release" ]]; then
            TAG_NAME=""
            continue
        fi

        if [[ -z "$TAG_NAME" && "$tag" == "v"*"."*"."*"-"* ]]; then
            TAG_NAME=$tag
            continue
        fi

        if [[ -n "$TAG_NAME" ]]; then
            delete_flag=$( python3 apecloud-cd/.github/utils/parse_time.py --release-date "$tag" )
        fi

        if [[ "$delete_flag" == "1" ]]; then
            set_delete_release
        fi
    done
    echo "$DELETE_RELEASE"
}

get_cloud_delete_release() {
    release_list=$( gh release list --repo $GITHUB_REPO --limit 1000 --json tagName,publishedAt \
        | jq -r '.[] | select(.publishedAt < (now - 7*86400 | todateiso8601)) | .tagName' \
        | (grep -E "alpha|beta" || true) | sort -uV )
    for tag in $( echo "$release_list" ) ;do
        if [[ -z "$DELETE_RELEASE" ]]; then
            DELETE_RELEASE="$tag"
        else
            DELETE_RELEASE="$DELETE_RELEASE|$tag"
        fi
    done
    echo "$DELETE_RELEASE"
}

comment_issue() {
    echo "gh issue comment $ISSUE_NUMBER --body \"$ISSUE_COMMENT\" --repo $GITHUB_REPO"
    gh issue comment $ISSUE_NUMBER --body "$ISSUE_COMMENT" --repo $GITHUB_REPO
}

delete_runner() {
    runners_url=$GITHUB_API/repos/$GITHUB_REPO/actions/runners
    runners_list=$( gh_curl -s $runners_url )
    total_count=$( echo "$runners_list" | jq '.total_count' )
    echo "total_count":$total_count
    for i in $(seq 0 $total_count); do
        runner_name=$( echo "$runners_list" | jq ".runners[$i].name" --raw-output )
        runner_status=$( echo "$runners_list" | jq ".runners[$i].status" --raw-output )
        runner_busy=$( echo "$runners_list" | jq ".runners[$i].busy" --raw-output )
        runner_id=$( echo "$runners_list" | jq ".runners[$i].id" --raw-output )
        echo $runner_status
        if [[  "$runner_status" == "offline" && "$runner_busy" == "false" ]]; then
            echo "delete runner_name:"$runner_name
            gh_curl -L -X DELETE $runners_url/$runner_id
        fi
        if [[ "$runner_status" == "null" || -z "$runner_status" ]]; then
            remains=$(( $total_count - $i ))
            echo "remains:"$remains
            if [[ $remains -gt 10 ]]; then
                delete_runner
            else
                break
            fi
        fi
    done
}

delete_charts_index() {
    yq eval 'del(.entries.[].[]|select(.version|contains("'$TAG_NAME_TMP'")))' -i index.yaml
}

get_incremental_chart_package() {
    for filePath in $( git diff --name-only HEAD HEAD^ ); do
        if [[ "$filePath" == "upload-charts/"*".tgz" ]]; then
            if [[ -f "$filePath" ]]; then
                echo "cp $filePath .cr-release-packages"
                cp $filePath .cr-release-packages
            else
                echo "not found upload chart tgz $filePath"
            fi
        fi
    done
}

set_size_label() {
    pr_info=$( gh pr view $PR_NUMBER --repo $GITHUB_REPO --json "additions,deletions,labels" )
    pr_additions=$( echo "$pr_info" | jq -r '.additions' )
    pr_deletions=$( echo "$pr_info" | jq -r '.deletions' )
    total_changes=$(( $pr_additions + $pr_deletions ))
    size_label=""
    if [[ $total_changes -lt 10 ]]; then
        size_label="size/XS"
    elif [[ $total_changes -lt 30 ]]; then
        size_label="size/S"
    elif [[ $total_changes -lt 100 ]]; then
        size_label="size/M"
    elif [[ $total_changes -lt 500 ]]; then
        size_label="size/L"
    elif [[ $total_changes -lt 1000 ]]; then
        size_label="size/XL"
    else
        size_label="size/XXL"
    fi
    echo "size label:$size_label"
    label_list=$(  echo "$pr_info" | jq -r '.labels[].name' )
    remove_label=""
    add_label=true
    for label in $( echo "$label_list" ); do
        case $label in
            $size_label)
                add_label=false
                continue
            ;;
            size/*)
                if [[ -z "$remove_label" ]]; then
                    remove_label=$label
                else
                    remove_label="$label,$remove_label"
                fi
            ;;
        esac
    done

    if [[ -n "$remove_label" ]]; then
        echo "$(tput -T xterm setaf 3)remove $GITHUB_REPO $PR_NUMBER label:$remove_label$(tput -T xterm sgr0)"
        gh pr edit $PR_NUMBER --repo $GITHUB_REPO --remove-label "$remove_label"
    fi

    if [[ $add_label == true ]]; then
        echo "$(tput -T xterm setaf 2)add $GITHUB_REPO $PR_NUMBER label:$size_label$(tput -T xterm sgr0)"
        gh pr edit $PR_NUMBER --repo $GITHUB_REPO --add-label "$size_label"
    fi
}

set_label() {
    # check pr draft
    # draft_status=`gh_curl -s $GITHUB_API/repos/$GITHUB_REPO/pulls/$PR_NUMBER | jq -r '.draft'`
    # if [[ "$draft_status" == "true" ]]; then
    #    echo "$(tput -T xterm setaf 3)This is a draft pr, skip!$(tput -T xterm sgr0)"
    #    return
    # fi
    label_ops_tmp=$(echo "$LABEL_OPS" | tr '[:upper:]' '[:lower:]')
    if [[ "${label_ops_tmp}" == "add"  ]]; then
        gh pr edit $PR_NUMBER --repo $GITHUB_REPO --add-label "$LABEL_NAME"
    elif [[ "${label_ops_tmp}" == "remove"  ]]; then
        gh pr edit $PR_NUMBER --repo $GITHUB_REPO --remove-label "$LABEL_NAME"
    fi
}

get_latest_milestone_title() {
    milestone_title=$( gh_curl -s $GITHUB_API/repos/$GITHUB_REPO/milestones | jq -r '[.[] | select(.state == "open")][0].title')
    echo "$milestone_title"
}

get_latest_milestone_number() {
    milestone_number=$( gh_curl -s $GITHUB_API/repos/$GITHUB_REPO/milestones | jq -r '[.[] | select(.state == "open")][0].number')
    echo $milestone_number
}

set_pr_milestone() {
    latest_milestone_title=$( get_latest_milestone_title )
    pr_info=$( gh pr view $PR_NUMBER --repo $GITHUB_REPO --json "milestone" )
    pr_milestone=$( echo "$pr_info" | jq -r '.milestone' )
    if [[ "$pr_milestone" == "null" || -z "$pr_milestone" ]]; then
        echo "$(tput -T xterm setaf 2)set pr milestone:$latest_milestone_title$(tput -T xterm sgr0)"
        gh pr edit $PR_NUMBER --repo $GITHUB_REPO --milestone "$latest_milestone_title"
    fi
}

set_issue_milestone() {
    latest_milestone_title=$( get_latest_milestone_title )
    issue_info=$( gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --json "milestone" )
    issue_milestone=$( echo "$issue_info" | jq -r '.milestone' )
    if [[ "$issue_milestone" == "null" || -z "$issue_milestone" ]]; then
        echo "$(tput -T xterm setaf 2)set issue milestone:$latest_milestone_title$(tput -T xterm sgr0)"
        gh issue edit $ISSUE_NUMBER --repo $GITHUB_REPO --milestone "$latest_milestone_title"
    fi
}

move_pr_to_next_milestone() {
    next_milestone_number=${1:-""}
    next_milestone_title=${2:-""}
    LIMIT_NUMBER_TEMP=100
    if [[ -n "$LIMIT_NUMBER" ]]; then
        LIMIT_NUMBER_TEMP=$LIMIT_NUMBER
    fi
    pr_list=$( gh pr list --repo $GITHUB_REPO --limit $LIMIT_NUMBER_TEMP --json "number,milestone" )
    for i in $(seq 0 $LIMIT_NUMBER_TEMP); do
        pr_number=$( echo "$pr_list" | jq ".[$i].number" --raw-output )
        if [[ -z "$pr_number" || "$pr_number" == "null" ]]; then
            break
        fi
        pr_milestone_number=$( echo "$pr_list" | jq ".[$i].milestone.number" --raw-output )
        if [[ "$pr_milestone_number" == "null" || -z "$pr_milestone_number" ]]; then
            continue
        fi
        if [[ $pr_milestone_number -lt $next_milestone_number ]]; then
            echo "$(tput -T xterm setaf 3)set pr $pr_number milestone:$next_milestone_title$(tput -T xterm sgr0)"
            gh pr edit $pr_number --repo $GITHUB_REPO --milestone "$next_milestone_title"
        fi
    done
    echo "$(tput -T xterm setaf 2)move $GITHUB_REPO pr milestone done$(tput -T xterm sgr0)"
}

move_issue_to_next_milestone() {
    next_milestone_number=${1:-""}
    next_milestone_title=${2:-""}
    LIMIT_NUMBER_TEMP=500
    if [[ -n "$LIMIT_NUMBER" ]]; then
        LIMIT_NUMBER_TEMP=$LIMIT_NUMBER
    fi
    issue_list=$( gh issue list --repo $GITHUB_REPO --limit $LIMIT_NUMBER_TEMP --json "number,milestone" )
    for i in $(seq 0 $LIMIT_NUMBER_TEMP); do
        issue_number=$( echo "$issue_list" | jq ".[$i].number" --raw-output )
        if [[ -z "$issue_number" || "$issue_number" == "null" ]]; then
            break
        fi
        issue_milestone_number=$( echo "$issue_list" | jq ".[$i].milestone.number" --raw-output )
        if [[ "$issue_milestone_number" == "null" || -z "$issue_milestone_number" ]]; then
            continue
        fi
        if [[ $issue_milestone_number -lt $next_milestone_number ]]; then
            echo "$(tput -T xterm setaf 3)set issue $issue_number milestone:$next_milestone_title$(tput -T xterm sgr0)"
            gh issue edit $issue_number --repo $GITHUB_REPO --milestone "$next_milestone_title"
        fi
    done
    echo "$(tput -T xterm setaf 2)move $GITHUB_REPO issue milestone done$(tput -T xterm sgr0)"
}

move_pr_issue_to_next_milestone() {
    latest_milestone_number=$( get_latest_milestone_number )
    latest_milestone_title=$( get_latest_milestone_title )
    move_pr_to_next_milestone $latest_milestone_number "$latest_milestone_title"
    move_issue_to_next_milestone $latest_milestone_number "$latest_milestone_title"
}

remove_runner() {
    runners_url=$GITHUB_API/repos/$GITHUB_REPO/actions/runners
    runners_list=$( gh_curl -s $runners_url )
    total_count=$( echo "$runners_list" | jq '.total_count' )
    for i in $(seq 0 $total_count); do
        if [[ "$i" == "$total_count" ]]; then
            break
        fi
        runner_name=$( echo "$runners_list" | jq ".runners[$i].name" --raw-output )
        runner_status=$( echo "$runners_list" | jq ".runners[$i].status" --raw-output )
        runner_busy=$( echo "$runners_list" | jq ".runners[$i].busy" --raw-output )
        runner_id=$( echo "$runners_list" | jq ".runners[$i].id" --raw-output )
        for runnerName in $( echo "$RUNNER_NAME" | sed 's/|/ /g' ); do
            if [[ "$runner_name" == "$runnerName" && "$runner_status" == "online" && "$runner_busy" == "false"  ]]; then
                echo "runner_name:"$runner_name
                gh_curl -L -X DELETE $runners_url/$runner_id
                break
            fi
        done
    done
}

set_images_list() {
    rm -f $IMAGES_LIST
    touch $IMAGES_LIST

    for image in `echo "$IMAGES" | sed 's/|/ /g'`; do
       echo "$image" >> $IMAGES_LIST
    done
}

generate_image_yaml() {
    if [[ -z "$IMAGES" ]]; then
        echo "images name is empty"
        return
    fi
    image_sync_yaml="./image_sync_yaml.yml"
    rm -f $image_sync_yaml
    touch $image_sync_yaml
    for image in `echo "$IMAGES" | sed 's/|/ /g'`; do
        image_name=${image##*/}
        tee -a $image_sync_yaml << EOF
${REGISTRY}/${image}:
  - "infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/${image_name}"
  - "apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/${image_name}"
EOF
    done
}

generate_image_yaml_apecloud() {
    if [[ -z "$IMAGES" ]]; then
        echo "images name is empty"
        return
    fi
    image_sync_yaml="./image_sync_yaml_apecloud.yml"
    rm -f $image_sync_yaml
    touch $image_sync_yaml
    for image in `echo "$IMAGES" | sed 's/|/ /g'`; do
        image_name=${image##*/}
        tee -a $image_sync_yaml << EOF
${REGISTRY}/${image}:
  - "apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/${image_name}"
EOF
    done
}

get_release_branch() {
    BRANCH_NAME_TMP=""
    if [[ "$BRANCH_NAME" == "main" || "$BRANCH_NAME" == "release-"* ]]; then
        BRANCH_NAME_TMP="$BRANCH_NAME"
    else
        beta_tag="v"*"."*"."*"-beta."*
        rc_tag="v"*"."*"."*"-rc."*
        stable_tag="v"*"."*"."*
        not_stable_tag="v"*"."*"."*"-"*
        check_ret=$( eval "[[ ($VERSION == $stable_tag && $VERSION != $not_stable_tag) || $VERSION == $beta_tag || $VERSION == $rc_tag  ]] && echo true" )
        if [[ "$check_ret" == "true" ]]; then
            VERSION_TMP="${VERSION/v/}"
            VERSION_TMP=$(echo "$VERSION_TMP" | awk -F '.' '{print $1"."$2}')
            BRANCH_NAME_TMP="release-${VERSION_TMP}"
        else
            BRANCH_NAME_TMP="main"
        fi
    fi
    echo "$BRANCH_NAME_TMP"
}

delete_actions_cache() {
    gh extension install actions/gh-actions-cache --force
    gh actions-cache delete --repo $GITHUB_REPO $TAG_NAME --confirm
}

check_release_version(){
    if [[ "$TAG_NAME" == "latest" ]]; then
        echo "$TAG_NAME"
        return
    fi
    release_list=$( gh release list --repo $GITHUB_REPO --limit 100 )
    for tag in $( echo "$release_list"); do
        if [[ "$tag" == "$TAG_NAME" ]]; then
            echo "$TAG_NAME"
            break
        elif [[ "$tag" == "v$TAG_NAME" ]]; then
            echo "v$TAG_NAME"
            break
        fi
    done
}

bump_chart_version() {
    if [[ -z "${VERSION}" ]]; then
        echo "bump chart version is empty"
        return
    fi

    chart_name=""
    chart_version=""
    for chart_tmp in $(echo "$VERSION" | sed 's/-/ /g'); do
        if [[ -z "${chart_name}" && -z "${chart_version}" ]]; then
            chart_name="${chart_tmp}"
        elif [[ -n "${chart_version}" ]]; then
            chart_version="${chart_version}-${chart_tmp}"
        elif [[ "${chart_tmp}" == *"."*"."*"" ]]; then
            chart_version="${chart_tmp}"
        elif [[ -n "${chart_name}" ]]; then
            chart_name="${chart_name}-${chart_tmp}"
        fi
    done

    chart_file_dir="deploy"
    if [[ "$IMAGES" == *"apecloud-charts" || "$IMAGES" == *"apecloud-addon-charts" ]]; then
        chart_file_dir="addons"
    fi

    chart_file_dir="${chart_file_dir}/${chart_name}/Chart.yaml"

    if [[ ! -f "${chart_file_dir}" ]]; then
        echo "Not found Chart.yaml file: ${chart_file_dir}"
        return
    fi

    if [[ -z "${chart_version}" ]]; then
        echo "Chart version is empty"
        return
    fi

    if [[ "$UNAME" == "Darwin" ]]; then
        sed -i '' "s/^version:.*/version: ${chart_version}/" "${chart_file_dir}"
    else
        sed -i "s/^version:.*/version: ${chart_version}/" "${chart_file_dir}"
    fi
}

parse_test_result() {
    if [[ -z "${TEST_RESULT}" ]]; then
        return
    fi
    test_result_report_output_file_log="test-result-report-output.log"
    if [[ ! -f "${test_result_report_output_file_log}" ]]; then
        touch "${test_result_report_output_file_log}"
    fi

    PASSED_COUNT=0
    FAILED_COUNT=0
    SKIPPED_COUNT=0
    TEST_VERSION=""
    TEST_MODE=""
    FIRST_FAILED_OPS=""
    test_result_flag=0
    for test_ret_info in `echo "$TEST_RESULT" | sed 's/##/ /g'`; do
        if [[ $test_result_flag -eq 0 && "$test_ret_info" == *"#Test#Result--"* ]]; then
            test_result_flag=1
        fi

        test_ret=$( echo "$test_ret_info" | sed 's/#/ /g' )
        echo "$test_ret" >> "${test_result_report_output_file_log}"
        case $test_ret in
            *\[PASSED\]*)
                PASSED_COUNT=$(($PASSED_COUNT + 1))
            ;;
            *\[SKIPPED\]*)
                SKIPPED_COUNT=$(($SKIPPED_COUNT + 1))
            ;;
            *\[FAILED\]*)
                FAILED_COUNT=$(($FAILED_COUNT + 1))
            ;;
        esac

        # get test version and mode
        if [[ $test_result_flag -eq 1 && "$test_ret" == *"[Create]"* && -z "${TEST_VERSION}" ]]; then
            test_ret_index=0
            for test_ret_tmp in `echo "$test_ret_info" | sed 's/|/ /g'`; do
                test_ret_index=$(($test_ret_index + 1))
                if [[ $test_ret_index -eq 3 || "$test_ret_tmp" == *"ServiceVersion="* || "$test_ret_tmp" == *"Topology="* || "$test_ret_tmp" == *"ClusterVersion="* ]]; then
                    for test_ret_detail in `echo "$test_ret_tmp" | sed 's/;/ /g'`; do
                        if [[ ("$test_ret_detail" == *"ServiceVersion="*) || (-z "${TEST_VERSION}" && "$test_ret_detail" == *"ClusterVersion=") ]]; then
                            TEST_VERSION=$(echo "${test_ret_detail}" | (grep -o '[0-9].*' || true))
                        elif [[ "$test_ret_detail" == *"Topology="* ]]; then
                            test_ret_detail_tmp=${test_ret_detail/[/}
                            test_ret_detail_tmp=${test_ret_detail_tmp/Topology=/}
                            test_ret_detail_tmp=${test_ret_detail_tmp/]/}
                            TEST_MODE=${test_ret_detail_tmp}
                        fi
                    done
                    break
                fi
            done
        fi

        # get first failed ops
        if [[ $FAILED_COUNT -eq 1 && -z "${FIRST_FAILED_OPS}" ]]; then
            test_ret_index=0
            for test_ret_tmp in `echo "$test_ret_info" | sed 's/|/ /g'`; do
                test_ret_index=$(($test_ret_index + 1))
                if [[ $test_ret_index -eq 2 ]]; then
                    FIRST_FAILED_OPS=${test_ret_tmp//#/}
                    if [[ ! ("${FIRST_FAILED_OPS}" == "[Failover]" || "${FIRST_FAILED_OPS}" == "[NoFailover]" || "${FIRST_FAILED_OPS}" == "[Backup]" || "${FIRST_FAILED_OPS}" == "[Restore]") ]]; then
                        break
                    fi
                elif [[ $test_ret_index -eq 3 || "${FIRST_FAILED_OPS}" == "[Failover]" || "${FIRST_FAILED_OPS}" == "[NoFailover]" || "${FIRST_FAILED_OPS}" == "[Backup]" || "${FIRST_FAILED_OPS}" == "[Restore]" ]]; then
                    for test_ret_detail in `echo "$test_ret_tmp" | sed 's/;/ /g'`; do
                        if [[ "$test_ret_detail" == *"HA="* ]]; then
                            test_ret_detail_tmp=${test_ret_detail/[/}
                            test_ret_detail_tmp=${test_ret_detail_tmp/HA=/}
                            test_ret_detail_tmp=${test_ret_detail_tmp/]/}
                            FIRST_FAILED_OPS="${FIRST_FAILED_OPS}${test_ret_detail_tmp}"
                            break
                        elif [[ "$test_ret_detail" == *"BackupMethod="* ]]; then
                            test_ret_detail_tmp=${test_ret_detail/[/}
                            test_ret_detail_tmp=${test_ret_detail_tmp/BackupMethod=/}
                            test_ret_detail_tmp=${test_ret_detail_tmp/]/}
                            FIRST_FAILED_OPS="${FIRST_FAILED_OPS}${test_ret_detail_tmp}"
                            break
                        fi
                    done
                    break
                fi
            done
        fi
    done
    echo ""  >> ${test_result_report_output_file_log}
    echo "|${TEST_VERSION}|${TEST_MODE}|${PASSED_COUNT}|${FAILED_COUNT}|${SKIPPED_COUNT}|${FIRST_FAILED_OPS}"
}

update_k3d_coredns_cm() {
    kubectl get configmap -n kube-system coredns -oyaml
    COREDNS_CM_FILE="k3d-coredns-configmap.yaml"
    kubectl get configmap -n kube-system coredns -oyaml > ${COREDNS_CM_FILE}

    k3d_auth_ip=$(kubectl get configmap -n kube-system coredns -ojsonpath='{.data.NodeHosts}' | (grep "host.k3d.internal" || true) | awk 'NR==1{print $1}')
    echo "k3d auth ip:${k3d_auth_ip}"

    if [[ -z "$k3d_auth_ip" ]]; then
        k3d_auth_ip=$(kubectl get configmap -n kube-system coredns -ojsonpath='{.data.NodeHosts}' | awk 'NR==1{print $1}')
        k3d_auth_ip="${k3d_auth_ip%.*}.1"
        k3d_server_lb_ip="${k3d_auth_ip%.*}.6"
        if [[ "$UNAME" == "Darwin" ]]; then
            sed -i '' "s/^  NodeHosts: |/  NodeHosts: |\n    $k3d_auth_ip host.k3d.internal\n    $k3d_auth_ip auth.mytest.kubeblocks.com\n    $k3d_server_lb_ip k3d-kbcloud-serverlb/" $COREDNS_CM_FILE
        else
            sed -i "s/^  NodeHosts: |/  NodeHosts: |\n    $k3d_auth_ip host.k3d.internal\n    $k3d_auth_ip auth.mytest.kubeblocks.com\n    $k3d_server_lb_ip k3d-kbcloud-serverlb/" $COREDNS_CM_FILE
        fi
    else
        if [[ "$UNAME" == "Darwin" ]]; then
            sed -i '' "s/^    $k3d_auth_ip host.k3d.internal/    $k3d_auth_ip host.k3d.internal\n    $k3d_auth_ip auth.mytest.kubeblocks.com/" $COREDNS_CM_FILE
        else
            sed -i  "s/^    $k3d_auth_ip host.k3d.internal/    $k3d_auth_ip host.k3d.internal\n    $k3d_auth_ip auth.mytest.kubeblocks.com/" $COREDNS_CM_FILE
        fi
    fi

    kubectl apply -f $COREDNS_CM_FILE

    rm -rf $COREDNS_CM_FILE

    kubectl get configmap -n kube-system coredns -ojsonpath='{.data.NodeHosts}'

    # delete coredns pod
    coredns_pod_name=$(kubectl get pods -n kube-system -l k8s-app=kube-dns| sed '1d'| awk '{print $1}')
    kubectl delete pod -n kube-system "${coredns_pod_name}"

    echo "K3d coredns configmap NodeHosts updated successfully."
}

get_cloud_pre_version() {
    if [[ -z "$VERSION" ]]; then
        # get latest version
        LATEST_VERSIONS=$(gh release list --repo $GITHUB_REPO)
        for latest_version in $(echo "$LATEST_VERSIONS"); do
            if [[ "$latest_version" == "v"*"."*"."* ]]; then
                VERSION="$latest_version"
                break
            fi
        done
    fi

    if [[ -z "$VERSION" ]]; then
        return
    fi

    # get pre version
    FIRST_VERSION="${VERSION%%.*}"
    SECOND_VERSION="${VERSION#*.}"
    SECOND_VERSION="${SECOND_VERSION%%.*}"
    PRE_VERSIONS=""
    if [[ "$SECOND_VERSION" == "0" ]]; then
        head_version="${FIRST_VERSION}.${SECOND_VERSION}"
        if [[ "${VERSION}" == "v1.0."* ]]; then
            head_version="v0.28"
            PRE_VERSIONS=$( gh release list --repo $GITHUB_REPO --limit 1000 | (grep "${head_version}" || true))
        elif [[ "${VERSION}" == "v2.0."* ]]; then
            head_version="v1.1"
            PRE_VERSIONS=$( gh release list --repo $GITHUB_REPO --limit 1000 | (grep "${head_version}" || true))
        else
            PRE_VERSIONS=$( gh release list --repo $GITHUB_REPO --limit 1000 | (grep -v "${head_version}" || true))
        fi
    else
        SECOND_VERSION=$(( $SECOND_VERSION - 1 ))
        if [[ "${VERSION}" == "v0.30."* ]]; then
            SECOND_VERSION=$(( $SECOND_VERSION - 1 ))
        fi
        head_version="${FIRST_VERSION}.${SECOND_VERSION}"
        if [[ "${VERSION}" == "v1.0."* ]]; then
            head_version="v0.28"
        fi
        PRE_VERSIONS=$( gh release list --repo $GITHUB_REPO --limit 1000 | (grep "${head_version}" || true))
    fi
    PRE_VERSION=""
    for pre_version in $(echo "$PRE_VERSIONS"); do
        if [[ "$pre_version" == "v"*"."*"."* ]]; then
            PRE_VERSION="$pre_version"
            break
        fi
    done
    if [[ -z "$PRE_VERSION" ]]; then
        case "$VERSION" in
            v1.1.*)
                PRE_VERSION="v1.0.101"
            ;;
        esac
    fi
    echo "$PRE_VERSION"
}

get_ginkgo_test_result_total() {
    if [[ -z "${TEST_RESULT}" ]]; then
        return
    fi
    total_passed=0
    total_failed=0
    total_pending=0
    total_skipped=0
    for test_result in $(echo "${TEST_RESULT}"); do
        case $test_result in
            Passed)
                total_passed=$(($total_passed + $test_result_tmp))
                ;;
            Failed)
                total_failed=$(($total_failed + $test_result_tmp))
                ;;
            Pending)
                total_pending=$(($total_pending + $test_result_tmp))
                ;;
            Skipped)
                total_skipped=$(($total_skipped + $test_result_tmp))
                ;;
            *)
                test_result_tmp=$test_result
                ;;
        esac
    done

    if [ $total_failed -gt 0 ]; then
        echo "FAIL! -- ${total_passed} Passed | ${total_failed} Failed | ${total_pending} Pending | ${total_skipped} Skipped"
    else
        echo "SUCCESS! -- ${total_passed} Passed | ${total_failed} Failed | ${total_pending} Pending | ${total_skipped} Skipped"
    fi
}

set_api_coverage_result_url() {
    TEST_RESULT="$(echo "${TEST_RESULT}" | sed 's/ /#/g')"
    COVERAGE_RESULT_TEMP=""
    for coverage_result in $(echo "$COVERAGE_RESULT" | sed 's/##/ /g'); do
        api_type=${coverage_result%%|*}
        for test_result in `echo "$TEST_RESULT" | sed 's/##/ /g'`; do
            test_type=${test_result%%-*}
            job_url=${test_result##*|}
            if [[ "$test_type" == "$api_type" ]]; then
                COVERAGE_RESULT_TEMP="${COVERAGE_RESULT_TEMP}##${coverage_result}|${job_url}"
                break
            fi
        done
    done
    echo "$COVERAGE_RESULT_TEMP"
}

set_engine_summary_result_url() {
    TEST_RESULT="$(echo "${TEST_RESULT}" | sed 's/ /#/g')"
    job_url="null"
    for test_result in `echo "$TEST_RESULT" | sed 's/##/ /g'`; do
        test_type=${test_result%%-*}
        if [[ "$test_type" == "engine" ]]; then
            job_url=${test_result##*|}
        fi
    done
    ENGINE_SUMMARY_RESULT_TEMP=""
    for coverage_result in $(echo "$COVERAGE_RESULT" | sed 's/##/ /g'); do
        coverage_result=${coverage_result/\#/ }
        ENGINE_SUMMARY_RESULT_TEMP="${ENGINE_SUMMARY_RESULT_TEMP}##${coverage_result}|${REPORT_URL}|${job_url}"
    done
    echo "$ENGINE_SUMMARY_RESULT_TEMP"
}

set_engine_summary_result_url_2() {
     TEST_RESULT="$(echo "${TEST_RESULT}" | sed 's/ /#/g')"
     ENGINE_SUMMARY_RESULT_TEMP=""
     for coverage_result in $(echo "$COVERAGE_RESULT" | sed 's/##/ /g'); do
         engine_name=${coverage_result%%|*}
         job_url="null"
         for test_result in `echo "$TEST_RESULT" | sed 's/##/ /g'`; do
             test_types=${test_result%%|*}
             for test_type in `echo "$test_types" | sed 's/,/ /g'`; do
                if [[ "$test_type" == "$engine_name" ]]; then
                    job_url=${test_result##*|}
                    break
                fi
             done
             if [[ "${job_url}" != "null" ]]; then
                break
             fi
         done

         coverage_result=${coverage_result/\#/ }
         ENGINE_SUMMARY_RESULT_TEMP="${ENGINE_SUMMARY_RESULT_TEMP}##${coverage_result}|${REPORT_URL}|${job_url}"
     done
     echo "$ENGINE_SUMMARY_RESULT_TEMP"
 }

get_gh_job_url() {
    gh_job_url="https://github.com/$GITHUB_REPO/actions/runs/$RUN_ID"
    for i in {1..2}; do
        jobs_url="$GITHUB_API/repos/$GITHUB_REPO/actions/runs/$RUN_ID/jobs?per_page=200&page=$i"
        jobs_list=$( gh_curl -s $jobs_url )
        total_count=$( echo "$jobs_list" | jq '.total_count' )
        if [[ "$total_count" == "null" || $(is_number "$total_count") == "false" ]]; then
            echo "total_count:${total_count}"
            break
        fi
        for i in $(seq 0 $total_count); do
            if [[ "$i" == "$total_count" ]]; then
                break
            fi
            jobs_name=$( echo "$jobs_list" | jq ".jobs[$i].name" --raw-output )
            if [[ "$jobs_name" == *"${TEST_RESULT}" && "$jobs_name" != *"-${TEST_RESULT}" ]]; then
                jobs_url=$( echo "$jobs_list" | jq ".jobs[$i].html_url" --raw-output )
                gh_job_url="${jobs_url}"
            fi
        done
    done
    echo "${gh_job_url}"
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
            -tn|--tag-name)
                if [[ -n "${2:-}" ]]; then
                    TAG_NAME="$2"
                    shift
                fi
            ;;
            -gr|--github-repo)
                if [[ -n "${2:-}" ]]; then
                    GITHUB_REPO="$2"
                    shift
                fi
            ;;
            -gt|--github-token)
                if [[ -n "${2:-}" ]]; then
                    GITHUB_TOKEN="$2"
                    shift
                fi
            ;;
            -bn|--branch-name)
                if [[ -n "${2:-}" ]]; then
                    BRANCH_NAME="$2"
                    shift
                fi
            ;;
            -wi|--workflow-id)
                if [[ -n "${2:-}" ]]; then
                    WORKFLOW_ID="$2"
                    shift
                fi
            ;;
            -v|--version)
                if [[ -n "${2:-}" ]]; then
                    VERSION="$2"
                    shift
                fi
            ;;
            -u|--user)
                if [[ -n "${2:-}" ]]; then
                    USER="$2"
                    shift
                fi
            ;;
            -p|--password)
                if [[ -n "${2:-}" ]]; then
                    PASSWORD="$2"
                    shift
                fi
            ;;
            -df|--delete-force)
                if [[ -n "${2:-}" ]]; then
                    DELETE_FORCE="$2"
                    shift
                fi
            ;;
            -ri|--run-id)
                if [[ -n "${2:-}" ]]; then
                    RUN_ID="$2"
                    shift
                fi
            ;;
            -tr|--test-result)
                if [[ -n "${2:-}" ]]; then
                    TEST_RESULT="$2"
                    shift
                fi
            ;;
            -cr|--coverage-result)
                if [[ -n "${2:-}" ]]; then
                    COVERAGE_RESULT="$2"
                    shift
                fi
            ;;
            -cp|--chart-path)
                if [[ -n "${2:-}" ]]; then
                    CHART_PATH="$2"
                    shift
                fi
            ;;
            -in|--issue-number)
                if [[ -n "${2:-}" ]]; then
                    ISSUE_NUMBER="$2"
                    shift
                fi
            ;;
            -ic|--issue-comment)
                if [[ -n "${2:-}" ]]; then
                    ISSUE_COMMENT="$2"
                    shift
                fi
            ;;
            -jn|--job-name)
                if [[ -n "${2:-}" ]]; then
                    JOB_NAME="$2"
                    shift
                fi
            ;;
            -pn|--pr-number)
                if [[ -n "${2:-}" ]]; then
                    PR_NUMBER="$2"
                    shift
                fi
            ;;
            -ln|--limit-number)
                if [[ -n "${2:-}" ]]; then
                    LIMIT_NUMBER="$2"
                    shift
                fi
            ;;
            -rn|--runner-name)
                if [[ -n "${2:-}" ]]; then
                    RUNNER_NAME="$2"
                    shift
                fi
            ;;
            -i|--images)
                IMAGES="$2"
                shift
            ;;
            -il|--images-list)
                IMAGES_LIST="$2"
                shift
            ;;
            -ea|--extra-args)
                EXTRA_ARGS="$2"
                shift
            ;;
            -r|--registry)
                REGISTRY="$2"
                shift
            ;;
            -lb|--label-name)
                LABEL_NAME="$2"
                shift
            ;;
            -lo|--label-ops)
                LABEL_OPS="$2"
                shift
            ;;
            -ru|--report-url)
                REPORT_URL="$2"
                shift
            ;;
            -tt|--test-type)
                TEST_TYPE="$2"
                shift
            ;;
            *)
                break
            ;;
        esac

        shift
    done
}

main() {
    local TYPE=""
    local TAG_NAME=""
    local GITHUB_REPO="$DEFAULT_GITHUB_REPO"
    local GITHUB_TOKEN=""
    local TRIGGER_MODE=""
    local BRANCH_NAME="main"
    local WORKFLOW_ID=""
    local VERSION=""
    local USER=""
    local PASSWORD=""
    local STABLE_RET
    local DELETE_FORCE=$DEFAULT_DELETE_FORCE
    local RUN_ID=""
    local TEST_RESULT=""
    local COVERAGE_RESULT=""
    local TEST_RET=""
    local CHART_PATH=""
    local DELETE_RELEASE=""
    local ISSUE_NUMBER=""
    local ISSUE_COMMENT=""
    local JOB_NAME=""
    local PR_NUMBER=""
    local LIMIT_NUMBER=""
    local RUNNER_NAME=""
    local IMAGES=""
    local IMAGES_LIST=""
    local EXTRA_ARGS=""
    local REGISTRY=$REGISTRY_DEFAULT
    local LABEL_NAME=""
    local LABEL_OPS=""
    local REPORT_URL=""
    local UNAME="$(uname -s)"
    local TEST_TYPE=""

    parse_command_line "$@"

    local TAG_NAME_TMP=${TAG_NAME/v/}
    if [[ "${TAG_NAME}" == *"|"* ]]; then
        # Strip leading 'v' from all tag versions in the pipe-separated list
        local TAG_NAME_TMP=$(echo "$TAG_NAME" | sed 's/^v//;s/|v/|/g')
    fi

    case $TYPE in
        8|9|10|11)
            STABLE_RET=$( check_stable_release )
            if [[ -z "$TAG_NAME" || ("$STABLE_RET" == "1" && "$DELETE_FORCE" == "false") ]]; then
                echo "skip delete stable release $TAG_NAME"
                return
            fi
        ;;
    esac
    case $TYPE in
        1)
            echo "${TAG_NAME/v/}"
        ;;
        2)
            echo "${TAG_NAME/-/.}"
        ;;
        3)
            get_upload_url
        ;;
        4)
            get_latest_tag
        ;;
        5)
            update_release_latest
        ;;
        6)
            get_trigger_mode
        ;;
        7)
            trigger_repo_workflow
        ;;
        8)
            delete_release_versions_all
        ;;
        9)
            delete_kubeblocks_release_charts_all
        ;;
        10)
            delete_docker_images
        ;;
        11)
            delete_aliyun_images
        ;;
        12)
            get_test_result
        ;;
        13)
            helm_dep_update
        ;;
        14)
            get_delete_release
        ;;
        15)
            comment_issue
        ;;
        16)
            delete_runner
        ;;
        17)
            get_job_url
        ;;
        18)
            delete_aliyun_images_new
        ;;
        19)
            delete_charts_index
        ;;
        20)
            get_incremental_chart_package
        ;;
        21)
            set_size_label
        ;;
        22)
            set_pr_milestone
        ;;
        23)
            set_issue_milestone
        ;;
        24)
            move_pr_issue_to_next_milestone
        ;;
        25)
            remove_runner
        ;;
        26)
            set_images_list
        ;;
        27)
            generate_image_yaml
        ;;
        28)
            get_release_branch
        ;;
        29)
            delete_tag
        ;;
        30)
            delete_actions_cache
        ;;
        31)
            check_release_version
        ;;
        32)
            generate_image_yaml_apecloud
        ;;
        33)
            set_label
        ;;
        34)
            get_e2e_test_result
        ;;
        35)
            bump_chart_version
        ;;
        36)
            parse_test_result
        ;;
        37)
            update_k3d_coredns_cm
        ;;
        38)
            get_cloud_test_result
        ;;
        39)
            get_cloud_pre_version
        ;;
        40)
            get_ginkgo_test_result
        ;;
        41)
            get_ginkgo_test_result_total
        ;;
        42)
            set_api_coverage_result_url
        ;;
        43)
            set_engine_summary_result_url
        ;;
        44)
            get_gh_job_url
        ;;
        45)
            set_engine_summary_result_url_2
        ;;
        46)
            get_playwright_test_result
        ;;
        47)
            get_playwright_test_result_total
        ;;
        48)
            get_cloud_delete_release
        ;;
        49)
            delete_release_charts_all
        ;;
        50)
            delete_docker_images_cloud
        ;;
        51)
            delete_aliyun_images_cloud
        ;;
    esac
}

main "$@"
