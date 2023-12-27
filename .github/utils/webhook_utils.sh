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
    -gr, --github-repo        Github repo
    -gt, --github-token       Github token
    -v, --version             The release version
    -c, --content             The trigger request content
    -bw, --bot-webhook        The bot webhook
    -ru, --run-url            The workflow run url
    -cv, --current-version    The current release version
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
    index=""
    release_list=$( gh release list --repo $GITHUB_REPO --limit 100 )
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

    if [[ ! -z "$RELEASE_VERSION" ]];then
        echo "$RELEASE_VERSION"
    fi
}

usage_message() {
    curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
        -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Usage:","content":[[{"tag":"text","text":"please enter the correct format\n"},{"tag":"text","text":"1. do <alpha|beta|rc> release\n"},{"tag":"text","text":"2. {\"ref\":\"<ref_branch>\",\"inputs\":{\"release_version\":\"<release_version>\"}}"}]]}}}}'
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
    curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
        -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Release:","content":[[{"tag":"text","text":"yes master, release "},{"tag":"a","text":"['$VERSION']","href":"https://github.com/'$GITHUB_REPO'/releases/tag/'$VERSION'"},{"tag":"text","text":" is on its way..."}]]}}}}'
}

send_message() {
    if [[ "$CONTENT_TMP" == *"success"* ]]; then
        curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
            -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Success:","content":[[{"tag":"text","text":"'$CONTENT'"}]]}}}}'
    else
        curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
            -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Error:","content":[[{"tag":"a","text":"'$CONTENT'","href":"'$RUN_URL'"}]]}}}}'
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
    esac
}

main "$@"
