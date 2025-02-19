#!/usr/bin/env bash
CHART_PATH=${1:-".cr-release-packages"}
CHART_NAME=${2:-"kubeblocks"}
CHECK_DOCKERHUB=${3:-"true"}
SKIP_CHECK_IMAGES=${4:-""}

main() {
    touch exit_result
    checked_images_list=""
    echo 0 > exit_result
    for chart in $CHART_PATH/*; do
        if [[ "$chart" == *"loadbalancer"* || "$chart" == *"kblib-"*".tgz"* ]]; then
            continue
        fi
        images=$( helm template $chart | egrep 'image:|repository:|tag:|docker.io/|apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/|infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com/|ghcr.io/|quay.io/' | awk '{print $2}' | sed 's/"//g' )
        repository=""
        for image in $( echo "$images" ); do
            skip_flag=0
            for chartName in $(echo "${CHART_NAME}" | sed 's/|/ /g'); do
                if [[ "$image" == *"apecloud/${chartName}"* ]]; then
                    skip_flag=1
                    break
                fi
            done

            if [[ $skip_flag -eq 1 || "$image" == *"apecloud/$CHART_NAME"* || "$image" == *"apecloud/chatgpt-retrieval-plugin"*  ]]; then
                continue
            fi

            skipCheckFlag=0
            if [[ -n "$SKIP_CHECK_IMAGES" ]]; then
                for skipCheckImage in $(echo "${SKIP_CHECK_IMAGES}" | sed 's/|/ /g'); do
                    if [[ "$image" == *"${skipCheckImage}"* ]]; then
                        skipCheckFlag=1
                        break
                    fi
                done
            fi

#            if [[ $skipCheckFlag -eq 1 ]]; then
#                continue
#            fi

            if [[ $image == *":"* ]]; then
                repository=$image
            elif [[ -z "$repository" ]]; then
                repository=$image
                continue
            else
                repository=$repository:$image
            fi

            if [[ ("$repository" == "docker.io/apecloud/"* || "$repository" == "apecloud/"*) && "$CHECK_DOCKERHUB" == "false" ]]; then
                repository=""
                continue
            fi

            if [[ -z "$repository" || "$repository" == "image:" || "$repository" == *':$('*')' || "$repository" == *'--'* || "$repository" == *'='* ]]; then
                repository=""
                continue
            fi

            checked_flag=0
            for checked_image in $(echo "${checked_images_list}" | sed 's/|/ /g'); do
                if [[ "$repository" == "$checked_image" ]]; then
                    checked_flag=1
                    break
                fi
            done

            if [[ $checked_flag -eq 1 ]]; then
                echo "$(tput -T xterm setaf 7)$repository already checked$(tput -T xterm sgr0)"
                repository=""
                continue
            else
                checked_images_list="${checked_images_list}|$repository"
            fi

#            if [[ "$repository" == "docker.io/"* || "$repository" == "apecloud/"* ]]; then
#                sleep 1
#            fi

            if [[ "$repository" == "'"*"'" ]]; then
                repository=${repository//\'/}
            fi

            echo "check image: $repository"
            check_image "$repository" $skipCheckFlag &
            repository=""
        done
    done
    wait
    cat exit_result
    exit $(cat exit_result)
}

check_image() {
    image=$1
    skipFlag=$2
    case $image in
        quay.io/*)
            echo "$(tput -T xterm setaf 3)Use the quay.io repository image:$image, which should be replaced.$(tput -T xterm sgr0)"
            check_image_exists "$image" "1"
            # echo 1 > exit_result
        ;;
        docker.io/apecloud/*|\
        apecloud/*|\
        apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/*|\
        infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/*)
            check_image_exists "$image" $skipFlag
        ;;
        *)
            check_image_exists "$image" "1"
        ;;
    esac
}

check_image_exists() {
    image=$1
    skipArm=$2
    tag=${image##*:}
    for i in {1..5}; do
        case $tag in
            *arm64*|*amd64*|*arm*|*amd*)
                architecture=$( docker buildx imagetools inspect "$image" |  grep Digest )
            ;;
            *)
                if [[ $skipArm -eq 1 ]]; then
                    architecture=$( docker buildx imagetools inspect "$image" |  grep Digest )
                else
                    architecture=$( docker buildx imagetools inspect "$image" | grep Platform )
                fi
            ;;
        esac
        if [[ -z "$architecture" ]]; then
            if [[ $i -lt 5 ]]; then
                sleep 1
                continue
            fi
        else
            case $tag in
                *arm64*|*amd64*|*arm*|*amd*)
                    echo "$(tput -T xterm setaf 2)$image found $tag architecture$(tput -T xterm sgr0)"
                    break
                ;;
            esac

            if [[ $skipArm -eq 1 ]]; then
                echo "$(tput -T xterm setaf 2)$image found $tag architecture$(tput -T xterm sgr0)"
                break
            fi

            if [[ "$architecture" != *"amd64"* ]];then
                echo "$(tput -T xterm setaf 1)::error title=Missing Amd64 Arch::$image missing amd64 architecture$(tput -T xterm sgr0)"
                echo 1 > exit_result
            elif [[ "$architecture" != *"arm64"* ]]; then
                echo "$(tput -T xterm setaf 1)::error title=Missing Arm64 Arch::$image missing arm64 architecture$(tput -T xterm sgr0)"
                echo 1 > exit_result
            else
                echo "$(tput -T xterm setaf 2)$image found amd64/arm64 architecture$(tput -T xterm sgr0)"
            fi
            break
        fi
        echo "$(tput -T xterm setaf 1)$image is not exists.$(tput -T xterm sgr0)"
        echo 1 > exit_result
    done
}

main "$@"
