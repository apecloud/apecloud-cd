#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_DELETE_FORCE="false"

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
    -tn, --tag-name           Release tag name
    -gr, --github-repo        Github Repo
    -gt, --github-token       Github token
    -bn, --branch-name        The branch name that triggers the workflow
    -wi, --workflow-id        The workflow id that triggers the workflow
    -v, --version             Release version
    -u, --user                The docker registry user
    -p, --password            The docker registry password
    -df, --delete-force       Force to delete stable release (default: DEFAULT_DELETE_FORCE)
    -ri, --run-id             The  run id
    -tr, --test-result        The test result
    -cp, --chart-path         The chart path
    -in, --issue-number       The issue number
    -in, --issue-comment       The issue comment
EOF
}

GITHUB_API="https://api.github.com"
LATEST_REPO=apecloud/kubeblocks

main() {
    local TYPE=""
    local TAG_NAME=""
    local GITHUB_REPO=""
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
    local TEST_RET=""
    local CHART_PATH=""
    local DELETE_RELEASE=""
    local ISSUE_NUMBER=""
    local ISSUE_COMMENT=""

    parse_command_line "$@"

    local TAG_NAME_TMP=${TAG_NAME/v/}

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
            delete_release_version
        ;;
        9)
            delete_release_charts
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
    esac
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
            -cp|--chart-path)
                if [[ -n "${2:-}" ]]; then
                    CHART_PATH="$2"
                fi
                ;;
            -in|--issue-number)
                if [[ -n "${2:-}" ]]; then
                    ISSUE_NUMBER="$2"
                fi
                ;;
            -ic|--issue-comment)
                if [[ -n "${2:-}" ]]; then
                    ISSUE_COMMENT="$2"
                fi
                ;;
            *)
                break
                ;;
        esac

        shift
    done
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
    latest_release_tag=`gh_curl -s $GITHUB_API/repos/$LATEST_REPO/releases/latest | jq -r '.tag_name'`
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
    if [[ ! -z "$VERSION" ]]; then
        data='{"ref":"main","inputs":{"VERSION":"'$VERSION'"}}'
    fi
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

delete_release_version() {
    release_id=$( gh_curl -s $GITHUB_API/repos/$GITHUB_REPO/releases/tags/$TAG_NAME | jq -r '.id' )
    if [[ -n "$release_id" && "$release_id" != "null" ]]; then
        echo "delete $GITHUB_REPO release $TAG_NAME"
        gh_curl -s -X DELETE $GITHUB_API/repos/$GITHUB_REPO/releases/$release_id
    fi
    echo "delete $GITHUB_REPO tag $TAG_NAME"
    gh_curl -s -X DELETE  $GITHUB_API/repos/$GITHUB_REPO/git/refs/tags/$TAG_NAME
}

filter_charts() {
    while read -r chart; do
        [[ ! -d "$charts_dir/$chart" ]] && continue
        local file="$charts_dir/$chart/Chart.yaml"
        if [[ -f "$file" ]]; then
            chart_name=$(cat $file | grep "name:"|awk 'NR==1{print $2}')
            echo "delete chart $chart_name-$TAG_NAME_TMP"
            TAG_NAME="$chart_name-$TAG_NAME_TMP"
            delete_release_version &
        fi
    done
    wait
}

delete_release_charts() {
    local charts_dir=deploy
    charts_files=$( ls -1 $charts_dir )
    echo "$charts_files" | filter_charts
}

delete_docker_images() {
    echo "delete kubeblocks image $TAG_NAME_TMP"
    docker run --rm -it apecloud/remove-dockerhub-tag \
        --user "$USER" --password "$PASSWORD" \
        apecloud/kubeblocks:$TAG_NAME_TMP

    echo "delete kubeblocks-tools image $TAG_NAME_TMP"
    docker run --rm -it apecloud/remove-dockerhub-tag \
        --user "$USER" --password "$PASSWORD" \
        apecloud/kubeblocks-tools:$TAG_NAME_TMP
}

delete_aliyun_images() {
    echo "delete kubeblocks image $TAG_NAME_TMP"
    skopeo delete docker://registry.cn-hangzhou.aliyuncs.com/apecloud/kubeblocks:$TAG_NAME_TMP \
        --creds "$USER:$PASSWORD"

    echo "delete kubeblocks-tools image $TAG_NAME_TMP"
    skopeo delete docker://registry.cn-hangzhou.aliyuncs.com/apecloud/kubeblocks-tools:$TAG_NAME_TMP \
        --creds "$USER:$PASSWORD"
}

set_runs_jobs() {
    jobs_name=$1
    jobs_url=$2
    for test_ret in `echo "$TEST_RESULT" | sed 's/##/ /g'`; do
        test_type=${test_ret%|*}
        case $test_type in
            install)
                if [[ "$jobs_name" == *"$test_type"* ]]; then
                    TEST_RET="$test_ret|$jobs_url"
                fi
            ;;
            *)
                if [[ "$jobs_name" == *"$test_type" ]]; then
                    TEST_RET=$TEST_RET"##$test_ret|$jobs_url"
                fi
            ;;
        esac
    done
}

get_test_result() {
    jobs_url=$GITHUB_API/repos/$LATEST_REPO/actions/runs/$RUN_ID/jobs
    jobs_list=$( gh_curl -s $jobs_url )
    total_count=$( echo "$jobs_list" | jq '.total_count' )
    for i in $(seq 0 $total_count); do
        if [[ "$i" == "$total_count" ]]; then
            break
        fi
        jobs_name=$( echo "$jobs_list" | jq ".jobs[$i].name" --raw-output )
        jobs_url=$( echo "$jobs_list" | jq ".jobs[$i].html_url" --raw-output )
        set_runs_jobs "$jobs_name" "$jobs_url"
    done
    echo "$TEST_RET"
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
    release_list=$( gh release list --repo $LATEST_REPO --limit 100 | grep "Pre-release" )
    for tag in $( echo "$release_list" ) ;do
        delete_flag=0
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

comment_issue() {
    gh issue comment --repo $GITHUB_REPO $ISSUE_NUMBER --body "$ISSUE_COMMENT"
}

main "$@"
