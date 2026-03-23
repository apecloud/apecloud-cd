#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help                Display help
    -t, --type                Operation type
                                1) release message
                                2) send message
                                3) get release version
                                4) get kbcli branch
                                5) send cherry-pick message
                                6) send message without link
                                7) trigger release
    -gr, --github-repo        Github repo
    -gt, --github-token       Github token
    -v, --version             The release version
    -c, --content             The trigger request content
    -bw, --bot-webhook        The bot webhook
    -ru, --run-url            The workflow run url
    -cv, --current-version    The current release version
    -pn, --pr-number          The pull request number
    -pa, --pr-author          The pull request author
EOF
}

GITHUB_API="https://api.github.com"

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

check_numeric() {
    input=${1:-""}
    if [[ $input =~ ^[0-9]+$ ]]; then
        echo $(( ${input} ))
    else
        echo "no"
    fi
}

get_next_available_tag() {
    tag_type="$1"
    tag_limit="${2:-100}"
    index=""
    release_list=$( gh release list --repo $GITHUB_REPO --limit ${tag_limit} )
    for tag in $( echo "$release_list" | (grep "$tag_type" || true) ) ;do
        if [[ "$tag" != "$tag_type"* ]]; then
            continue
        fi
        tmp=${tag#*$tag_type}
        numeric=$( check_numeric "$tmp" )
        if [[ "$numeric" == "no" ]]; then
            continue
        fi
        if [[ $numeric -gt $index || -z "$index" ]]; then
            index=$numeric
        fi
    done

    if [[ -z "$index" ]];then
        index=0
    else
        index=$(( $index + 1 ))
    fi

    RELEASE_VERSION="${tag_type}${index}"
}

check_release_version(){
    if [[ -n "$CUR_VERSION" ]]; then
        VERSION="$CUR_VERSION"
        return
    fi
    latest_release_url=$GITHUB_API/repos/$GITHUB_REPO/releases/latest
    latest_version=$(gh_curl -s $latest_release_url | jq -r '.tag_name')
    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        VERSION="v0.1"
    else
        VERSION=$(echo "$latest_version" | awk -F '.' '{print $1"."$2}')
    fi
}

check_release_version_2(){
    TMP_TAG_NAME=""
    for content in $(echo "$CONTENT"); do
        if [[ "$content" == "v"*"."* || "$content" == "release-"*"."* || "$content" == *"."* ]]; then
            TMP_TAG_NAME=$content
        fi
        if [[ -n "$TMP_TAG_NAME" ]]; then
            if [[ "$TMP_TAG_NAME" == "release-"*"."* ]]; then
                TMP_BRANCH_NAME="${TMP_TAG_NAME}"
                TMP_TAG_NAME="${TMP_TAG_NAME#release-}"
            else
                TMP_BRANCH_NAME="release-${TMP_TAG_NAME/v/}"
            fi
            branch_url=$GITHUB_API/repos/$GITHUB_REPO/branches/$TMP_BRANCH_NAME
            branch_info=$( gh_curl -s $branch_url | (grep  $TMP_BRANCH_NAME || true) )
            if [[ -n "$branch_info" ]]; then
                BRANCH_NAME=$TMP_BRANCH_NAME
                TAG_NAME=$TMP_TAG_NAME
                echo "BRANCH_NAME:$BRANCH_NAME"
                echo "TAG_NAME:$TAG_NAME"
            fi
            break
        fi
    done
}

release_next_available_tag() {
    check_release_version
    v_major_minor="$VERSION"
    if [[ "$VERSION" != "v"* ]]; then
        v_major_minor="v$VERSION"
    fi
    stable_type="$v_major_minor."
    get_next_available_tag $stable_type
    v_number=$RELEASE_VERSION
    alpha_type="$v_number-alpha."
    beta_type="$v_number-beta."
    rc_type="$v_number-rc."
    case "$CONTENT" in
        *alpha*)
            get_next_available_tag "$alpha_type"
        ;;
        *beta*)
            get_next_available_tag "$beta_type"
        ;;
        *rc*)
            get_next_available_tag "$rc_type"
        ;;
    esac

    if [[ -n "$RELEASE_VERSION" ]];then
        echo "$RELEASE_VERSION"
    fi
}

release_next_available_tag_2() {
    check_release_version_2
    dispatches_url=$1
    v_major_minor="$TAG_NAME"
    if [[ "$TAG_NAME" != "v"* ]]; then
        v_major_minor="v$TAG_NAME"
    fi
    release_limit=100
    if [[ "${GITHUB_REPO}" == "apecloud/apecloud" && "${v_major_minor}" == "v2.1" ]]; then
        release_limit=100
    elif [[ "${GITHUB_REPO}" == "apecloud/apecloud" && "${v_major_minor}" == "v2.0" ]]; then
        release_limit=200
    elif [[ "${GITHUB_REPO}" == "apecloud/apecloud" && "${v_major_minor}" == "v1.1" ]]; then
        release_limit=500
    elif [[ "${GITHUB_REPO}" == "apecloud/apecloud" && "${v_major_minor}" == "v1.0" ]]; then
        release_limit=2000
    fi
    echo "release_limit:${release_limit}"
    stable_type="$v_major_minor."
    get_next_available_tag "$stable_type" ${release_limit}
    v_number=$RELEASE_VERSION
    alpha_type="$v_number-alpha."
    beta_type="$v_number-beta."
    rc_type="$v_number-rc."
    case "$CONTENT" in
        *alpha*)
            get_next_available_tag "$alpha_type" ${release_limit}
        ;;
        *beta*)
            get_next_available_tag "$beta_type" ${release_limit}
        ;;
        *rc*)
            get_next_available_tag "$rc_type" ${release_limit}
        ;;
    esac

    if [[ -n "$RELEASE_VERSION" ]];then
        gh_curl -X POST $dispatches_url -d '{"ref":"'$BRANCH_NAME'","inputs":{"release_version":"'$RELEASE_VERSION'"}}'
    fi
}

usage_message() {
    curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
        -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Usage:","content":[[{"tag":"text","text":"please enter the correct format\n"},{"tag":"text","text":"1. do <alpha|beta|rc> release\n"},{"tag":"text","text":"2. {\"ref\":\"<ref_branch>\",\"inputs\":{\"release_version\":\"<release_version>\"}}"}]]}}}}'
}

usage_message_2() {
    curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
        -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Usage:","content":[[{"tag":"text","text":"please enter the correct format\n"},{"tag":"text","text":"do [v*.*|release-*.*] [alpha|beta|rc] release\n"}]]}}}}'
}

get_release_version() {
    if [[ -n "$VERSION" ]]; then
        echo "$VERSION"
        return
    fi
    if [[ "$CONTENT" == "do"*"release"* ]]; then
        release_next_available_tag
    else
        usage_message
    fi
}

get_kbcli_branch() {
    kbcli_branch="main"
    kbcli_flag=0
    for content in $(echo "$CONTENT"); do
        if [[ $kbcli_flag -eq 1 ]]; then
            kbcli_branch="$content"
            break
        fi
        if [[ "$content" == "kbcli" ]]; then
            kbcli_flag=1
        fi
    done
    echo "$kbcli_branch"
}

cover_space() {
    CONTENT_TMP=$(echo "$CONTENT" | tr '[:upper:]' '[:lower:]')
    CONTENT=${CONTENT// /${R_SPACE}}
}

release_message() {
    if [[ "$VERSION" == "apecloud/wesql-server:"* ]]; then
        VERSION_TAG="$VERSION"
        VERSION_TAG="${VERSION_TAG#*:}"
        curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
            -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Release:","content":[[{"tag":"text","text":"yes master, release "},{"tag":"a","text":"['$VERSION']","href":"https://hub.docker.com/r/apecloud/wesql-server/tags/?name='$VERSION_TAG'"},{"tag":"text","text":" is on its way..."}]]}}}}'
    else
        curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
            -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Release:","content":[[{"tag":"text","text":"yes master, release "},{"tag":"a","text":"['$VERSION']","href":"https://github.com/'$GITHUB_REPO'/releases/tag/'$VERSION'"},{"tag":"text","text":" is on its way..."}]]}}}}'
    fi

}

send_message() {
    if [[ "$CONTENT_TMP" == *"success"* ]]; then
        curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
            -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Success:","content":[[{"tag":"text","text":"'$CONTENT'"}]]}}}}'
    elif [[ -n "${PR_AUTHOR}" ]]; then
        curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
            -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Error:","content":[[{"tag":"text","text":" Author:'${PR_AUTHOR}' "},{"tag":"a","text":"'$CONTENT'","href":"'$RUN_URL'"}]]}}}}'
    else
        curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
            -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Error:","content":[[{"tag":"a","text":"'$CONTENT'","href":"'$RUN_URL'"}]]}}}}'
    fi
}

send_message_without_link() {
    curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
        -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Release Branch Created:","content":[[{"tag":"text","text":"'$CONTENT'"}]]}}}}'
}

send_cherry_pick_message() {
    PR_NUMBER_TMP="#${PR_NUMBER}"
    PR_URL="https://github.com/${GITHUB_REPO}/pull/${PR_NUMBER}"
    if [[ -n "${PR_AUTHOR}" ]]; then
        curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
            -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Cherry Pick '${PR_NUMBER_TMP}' Error:","content":[[{"tag":"a","text":"['${PR_NUMBER_TMP}']","href":"'$PR_URL'"},{"tag":"text","text":" Author:'${PR_AUTHOR}' "},{"tag":"a","text":"'$CONTENT'","href":"'$RUN_URL'"}]]}}}}'
    else
        curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
            -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Cherry Pick '${PR_NUMBER_TMP}' Error:","content":[[{"tag":"a","text":"['${PR_NUMBER_TMP}']","href":"'$PR_URL'"},{"tag":"a","text":"'$CONTENT'","href":"'$RUN_URL'"}]]}}}}'
    fi
}

trigger_release() {
    echo "CONTENT:$CONTENT"
    dispatches_url=$GITHUB_API/repos/$GITHUB_REPO/actions/workflows/release-version.yml/dispatches

    if [[ "$CONTENT" == "do"*"release" ]]; then
        release_next_available_tag_2 "$dispatches_url"
    else
        usage_message_2
    fi
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

            -v|--version)
                if [[ -n "${2:-}" ]]; then
                    VERSION="$2"
                    shift
                fi
                ;;
            -c|--content)
                if [[ -n "${2:-}" ]]; then
                    CONTENT="$2"
                    shift
                fi
                ;;
            -bw|--bot-webhook)
                if [[ -n "${2:-}" ]]; then
                    BOT_WEBHOOK="$2"
                    shift
                fi
                ;;
            -ru|--run-url)
                if [[ -n "${2:-}" ]]; then
                    RUN_URL="$2"
                    shift
                fi
                ;;
            -cv|--current-version)
                if [[ -n "${2:-}" ]]; then
                    CUR_VERSION="$2"
                    shift
                fi
                ;;
            -pn|--pr-number)
                if [[ -n "${2:-}" ]]; then
                    PR_NUMBER="$2"
                    shift
                fi
                ;;
            -pa|--pr-author)
                if [[ -n "${2:-}" ]]; then
                    PR_AUTHOR="$2"
                    shift
                fi
            ;;
            -bn|--branch-name)
                if [[ -n "${2:-}" ]]; then
                    BRANCH_NAME="$2"
                    shift
                fi
            ;;
            -tn|--tag-name)
                if [[ -n "${2:-}" ]]; then
                    TAG_NAME="$2"
                    shift
                fi
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
    local GITHUB_REPO=""
    local GITHUB_TOKEN=""
    local VERSION=""
    local CONTENT_TMP=""
    local CONTENT=""
    local BOT_WEBHOOK=""
    local RELEASE_VERSION=""
    local RUN_URL=""
    local R_SPACE='\u00a0'
    local CUR_VERSION=""
    local PR_NUMBER=""
    local PR_AUTHOR=""
    local BRANCH_NAME=""
    local TAG_NAME=""

    parse_command_line "$@"

    case $TYPE in
        1)
            release_message
        ;;
        2)
            cover_space
            send_message
        ;;
        3)
            get_release_version
        ;;
        4)
            get_kbcli_branch
        ;;
        5)
            cover_space
            send_cherry_pick_message
        ;;
        6)
            cover_space
            send_message_without_link
        ;;
        7)
            trigger_release
        ;;
    esac
}

main "$@"
