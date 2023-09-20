#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_PACKAGE_NAME=kubeblocks
DEFAULT_CHANNEL=stable
API_URL=https://jihulab.com/api/v4/projects
DEFAULT_DELETE_FORCE="false"
DEFAULT_HELM_CHARTS_PROJECT_ID=85949
DEFAULT_ADDONS_PROJECT_ID=150246
DEFAULT_PLUGINS_PROJECT_ID=150247
DEFAULT_TOOLS_PROJECT_ID=150248
DEFAULT_HELM_CHARTS_LIST="kubeblocks|kubeblocks-cloud"
DEFAULT_ADDONS_LIST="prometheus"
DEFAULT_PLUGINS_LIST="load-balancer|ingress|cloud-provider|metalb|csi-|esdk-k8s-plugin|openebs|cert-manager"
DEFAULT_CHARTS_DIR="../helm-charts/deploy"

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help                Display help
    -t, --type                Release operation type
                                1) create release
                                2) upload release asset
                                3) release helm chart
                                4) update release latest
                                5) delete release
                                6) delete helm chart
    -tn, --tag-name           Release tag name
    -pi, --project-id         Gitlab repo project id or "group%2Fproject"
    -at, --access-token       Gitlab access token
    -au, --access-user        Gitlab access username
    -ap, --asset-path         Upload asset file path
    -an, --asset-name         Upload asset file name
    -pn, --package-name       Gitlab package name (default: $DEFAULT_PACKAGE_NAME)
    -c, --channel             Gitlab helm channel name (default: DEFAULT_CHANNEL)
    -df, --delete-force       Force to delete stable release (default: DEFAULT_DELETE_FORCE)
    -cd, --charts-dir         The dir of helm-charts (default: DEFAULT_CHARTS_DIR)
EOF
}

main() {
    local PACKAGE_NAME=$DEFAULT_PACKAGE_NAME
    local CHANNEL=$DEFAULT_CHANNEL
    local TAG_NAME=""
    local PROJECT_ID=""
    local ACCESS_TOKEN=""
    local ACCESS_USER=""
    local ASSET_PATH=""
    local ASSET_NAME=""
    local STABLE_RET=""
    local DELETE_FORCE=$DEFAULT_DELETE_FORCE
    local PROJECT_ID_TMP=""
    local HELM_CHARTS_PROJECT_ID=$DEFAULT_HELM_CHARTS_PROJECT_ID
    local ADDONS_PROJECT_ID=$DEFAULT_ADDONS_PROJECT_ID
    local PLUGINS_PROJECT_ID=$DEFAULT_PLUGINS_PROJECT_ID
    local TOOLS_PROJECT_ID=$DEFAULT_TOOLS_PROJECT_ID
    local HELM_CHARTS_LIST=$DEFAULT_HELM_CHARTS_LIST
    local ADDONS_LIST=$DEFAULT_ADDONS_LIST
    local PLUGINS_LIST=$DEFAULT_PLUGINS_LIST
    local CHARTS_DIR=$DEFAULT_CHARTS_DIR

    parse_command_line "$@"

    local TAG_NAME_TMP=${TAG_NAME/v/}

    case $TYPE in
        5|6)
            STABLE_RET=$( check_stable_release )
            if [[ -z "$TAG_NAME" || ("$STABLE_RET" == "1" && "$DELETE_FORCE" == "false") ]]; then
                echo "skip delete stable release"
                return
            fi
        ;;
    esac

    case $TYPE in
        1)
            create_release
        ;;
        2)
            upload_asset
            update_release_asset
        ;;
        3)
            release_helm
        ;;
        4)
            update_release_latest
        ;;
        5)
            delete_release
        ;;
        6)
            delete_helm_chart
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
            -t|--tag-name)
                if [[ -n "${2:-}" ]]; then
                    TAG_NAME="$2"
                    shift
                fi
                ;;
            -pi|--project-id)
                if [[ -n "${2:-}" ]]; then
                    PROJECT_ID="$2"
                    shift
                fi
                ;;
            -at|--access-token)
                if [[ -n "${2:-}" ]]; then
                    ACCESS_TOKEN="$2"
                    shift
                fi
                ;;
            -au|--access-user)
                if [[ -n "${2:-}" ]]; then
                    ACCESS_USER="$2"
                    shift
                fi
                ;;
            -ap|--asset-path)
                if [[ -n "${2:-}" ]]; then
                    ASSET_PATH="$2"
                    shift
                fi
                ;;
            -an|--asset-name)
                if [[ -n "${2:-}" ]]; then
                    ASSET_NAME="$2"
                    shift
                fi
                ;;
            -pn|--package-name)
                if [[ -n "${2:-}" ]]; then
                    PACKAGE_NAME="$2"
                    shift
                fi
                ;;
            -c|--channel)
                if [[ -n "${2:-}" ]]; then
                    CHANNEL="$2"
                    shift
                fi
                ;;
            -df|--delete-force)
                if [[ -n "${2:-}" ]]; then
                    DELETE_FORCE="$2"
                    shift
                fi
                ;;
            -cd|--charts-dir)
                if [[ -n "${2:-}" ]]; then
                    CHARTS_DIR="$2"
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

gitlab_api_curl() {
    curl --header "Authorization: Bearer $ACCESS_TOKEN" \
      --header 'Content-Type: application/json' \
      $@
}

create_release() {
    request_type=POST
    request_url=$API_URL/$PROJECT_ID/releases
    request_data='{"ref":"main","name":"KubeBlocks\t'$TAG_NAME'","tag_name":"'$TAG_NAME'"}'

    gitlab_api_curl --request $request_type $request_url --data $request_data
}

upload_asset() {
    request_url=$API_URL/$PROJECT_ID/packages/generic/$PACKAGE_NAME/$TAG_NAME/

    gitlab_api_curl $request_url --upload-file $ASSET_PATH
}

update_release_asset() {
    request_type=POST
    request_url=$API_URL/$PROJECT_ID/releases/$TAG_NAME/assets/links
    asset_url=$API_URL/$PROJECT_ID/packages/generic/$PACKAGE_NAME/$TAG_NAME/$ASSET_NAME
    request_data='{"url":"'$asset_url'","name":"'$ASSET_NAME'","link_type":"package"}'

    gitlab_api_curl --request $request_type $request_url --data $request_data
}

get_addons_list() {
    if [[ ! -d "$CHARTS_DIR" ]]; then
        echo "not found helm-charts dir"
        return
    fi
    for chart in $( ls -1 $CHARTS_DIR ); do
        chart_dir=$CHARTS_DIR/$chart
        if [[ -d "$chart_dir" ]]; then
            chart_file="$chart_dir/Chart.yaml"
            if [[ -f "$chart_file" ]]; then
                chart_name=$(cat $chart_file | grep "name:"|awk 'NR==1{print $2}')
                chart_name=$(echo "$chart_name" | tr '[:upper:]' '[:lower:]')
                if [[ "$chart_name" == *"-cluster" ]]; then
                    ADDONS_LIST="$ADDONS_LIST|${chart_name%*-cluster}"
                fi
            fi
        fi
    done
}

get_project_id() {
    chart_package_name=${1:-""}
    chart_ops=${2:-""}
    PROJECT_ID_TMP=""
    if [[ -n "$PROJECT_ID" ]]; then
        PROJECT_ID_TMP=$(echo "$PROJECT_ID" | tr '[:upper:]' '[:lower:]')
        case $PROJECT_ID_TMP in
            *kubeblock*)
                PROJECT_ID_TMP=$HELM_CHARTS_PROJECT_ID
            ;;
            *addon*)
                PROJECT_ID_TMP=$HELM_CHARTS_PROJECT_ID
            ;;
            *plugin*)
                PROJECT_ID_TMP=$PLUGINS_PROJECT_ID
            ;;
            *tool*)
                PROJECT_ID_TMP=$TOOLS_PROJECT_ID
            ;;
        esac
        return
    fi
    # get chart package name
    chart_name="$chart_package_name"
    if [[ -z "$chart_ops" ]]; then
        chart_name="$( helm show chart $chart_package_name | yq eval '.name' - )"
    fi
    chart_name=$(echo "$chart_name" | tr '[:upper:]' '[:lower:]')
    echo "chart name:$chart_name"
    if [[ "$chart_name" == "kblib" ]]; then
        echo "skip chart $chart_name"
        return
    fi
    # check kubeblocks charts
    for helm_charts in $(echo "$HELM_CHARTS_LIST" | sed 's/|/ /g'); do
        if [[ "$chart_name" == *"$helm_charts"* ]]; then
            PROJECT_ID_TMP=$HELM_CHARTS_PROJECT_ID
            break
        fi
    done
    if [[ -n "$PROJECT_ID_TMP" ]]; then
        return
    fi
    # check addons charts
    for addons in $(echo "$ADDONS_LIST" | sed 's/|/ /g'); do
        if [[ "$chart_name" == "${addons}" || "$chart_name" == "${addons}-cluster" ]]; then
            PROJECT_ID_TMP=$ADDONS_PROJECT_ID
            break
        fi
    done
    if [[ -n "$PROJECT_ID_TMP" ]]; then
        return
    fi
    # check plugins charts
    for plugins in $(echo "$PLUGINS_LIST" | sed 's/|/ /g'); do
        if [[ "$chart_name" == *"${plugins}"*  ]]; then
            PROJECT_ID_TMP=$PLUGINS_PROJECT_ID
            break
        fi
    done
    if [[ -n "$PROJECT_ID_TMP" ]]; then
        return
    fi
    # check tools charts
    PROJECT_ID_TMP=$TOOLS_PROJECT_ID
}

upload_chart() {
    request_type=${1:-""}
    request_url=${2:-""}
    chart=${3:-""}
    upload_flag=0
    upload_cmd="curl --request $request_type $request_url --form 'chart=@'$chart --user $ACCESS_USER:$ACCESS_TOKEN"
    for i in {1..10}; do
        ret_msg=$(eval $upload_cmd)
        echo "return message:$ret_msg"
        if [[ "$ret_msg" == *"201 Created"* ]]; then
            echo "$(tput -T xterm setaf 2)$ret_msg$(tput -T xterm sgr0)"
            upload_flag=1
            break
        fi
        sleep 1
    done
    if [[ $upload_flag -eq 0 ]]; then
        echo "$(tput -T xterm setaf 1)upload chart $chart error$(tput -T xterm sgr0)"
        exit 1
    fi
}

release_helm() {
    get_addons_list
    request_type=POST
    ASSET_PATHS=()
    if [[ -d "$ASSET_PATH" ]]; then
        for asset_path in $ASSET_PATH/*; do
            ASSET_PATHS[${#ASSET_PATHS[@]}]=`basename $asset_path`
        done
    elif [[ -f "$ASSET_PATH" ]]; then
        ASSET_PATHS[${#ASSET_PATHS[@]}]=`basename $ASSET_PATH`
    fi
    if [[ ${#ASSET_PATHS[@]} -eq 0 ]]; then
        echo "not found helm-charts $ASSET_PATH"
        return
    fi
    for chart in ${ASSET_PATHS[@]}; do
        get_project_id "$chart"
        echo "chart package name:$chart"
        echo "PROJECT_ID:$PROJECT_ID_TMP"
        if [[ -z "$PROJECT_ID_TMP" ]]; then
            continue
        fi
        request_url=$API_URL/$PROJECT_ID_TMP/packages/helm/api/$CHANNEL/charts
        upload_chart $request_type $request_url $chart
    done
}

update_release_latest() {
    request_type=DELETE
    request_url=$API_URL/$PROJECT_ID/repository/tags
    gitlab_api_curl --request $request_type $request_url/latest

    request_type=POST
    request_data='{"tag_name":"latest","ref":"main","message":"'$TAG_NAME'"}'
    gitlab_api_curl --request $request_type $request_url --data $request_data
}

check_stable_release() {
    release_tag="v"*"."*"."*
    not_stable_release_tag="v"*"."*"."*"-"*
    if [[ "$TAG_NAME" == $release_tag && "$TAG_NAME" != $not_stable_release_tag ]]; then
        echo "1"
    else
        echo "0"
    fi
}

delete_release_packages() {
    delete_name=${1:-""}
    project_id=${2:-""}
    request_type=DELETE
    page_num=1
    found_flag=0
    request_url=""
    while true; do
        request_url="$API_URL/$project_id/packages?page=$page_num&per_page=100"
        packages_info=$( gitlab_api_curl -s $request_url )
        length=$( echo "$packages_info" | jq length )
        if [[ $length -eq 0 ]]; then
            break
        fi
        for i in {0..99}; do
            package_version=$( echo "$packages_info" | jq '.['$i'].version' )
            package_name=$( echo "$packages_info" | jq '.['$i'].name' )
            if [[ "$package_version" == "\"$TAG_NAME\"" && "$package_name" == "\"$delete_name\"" ]]; then
                package_id=$( echo "$packages_info" | jq '.['$i'].id' )
                echo "package_id:$package_id"
                echo "delete packages $package_name $package_version"
                request_url=$API_URL/$project_id/packages/$package_id
                gitlab_api_curl --request $request_type $request_url
                found_flag=1
                break
            fi
        done
        if [[ $found_flag -eq 1 ]]; then
            break
        fi
        page_num=$(( $page_num + 1 ))
    done
}

delete_release() {
    delete_release_packages "kubeblocks" "$PROJECT_ID"
    echo "delete release $TAG_NAME"
    request_url=$API_URL/$PROJECT_ID/repository/tags/$TAG_NAME
    gitlab_api_curl --request $request_type $request_url
}

filter_charts() {
    while read -r chart; do
        [[ ! -d "$charts_dir/$chart" ]] && continue
        local file="$charts_dir/$chart/Chart.yaml"
        if [[ -f "$file" ]]; then
            chart_name=$(cat $file | grep "name:"|awk 'NR==1{print $2}')
            echo "delete helm_chart $chart_name $TAG_NAME_TMP"
            get_project_id "$chart_name" "delete"
            if [[ -n "$PROJECT_ID_TMP" ]]; then
                delete_release_packages "$chart_name" "$PROJECT_ID_TMP" &
            fi
        fi
    done
    wait
}

delete_helm_chart() {
    TAG_NAME="$TAG_NAME_TMP"
    get_addons_list
    local charts_dir=deploy
    charts_files=$( ls -1 $charts_dir )
    echo "$charts_files" | filter_charts
}

main "$@"
