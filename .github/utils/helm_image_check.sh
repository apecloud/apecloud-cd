#!/usr/bin/env bash
CHART_PATH=${1:-".cr-release-packages"}
CHART_NAME=${2:-"kubeblocks"}
CHECK_DOCKERHUB=${3:-"true"}

main() {
    touch exit_result
    echo 0 > exit_result
    for chart in $CHART_PATH/*; do
        if [[ "$chart" == *"loadbalancer"* || "$chart" == *"etcd"* ]]; then
            continue
        fi
        images=`helm template $chart | egrep 'image:|repository:|tag:' | awk '{print $2}' | sed 's/"//g'`
        repository=""
        for image in $images; do
            if [[ "$image" == *"apecloud/$CHART_NAME"* || "$image" == *"apecloud/chatgpt-retrieval-plugin"*  ]]; then
                continue
            fi

            if [[ $image == *":"* ]]; then
                repository=$image
            elif [[ -z "$repository" ]]; then
                repository=$image
                continue
            else
                repository=$repository:$image
            fi

            if [[ "$repository" == "apecloud/"* ]]; then
                repository="registry.cn-hangzhou.aliyuncs.com/"$repository
            fi

            if [[ ("$image" == "docker.io/apecloud/"* || "$image" == "apecloud/"*) && "$CHECK_DOCKERHUB" == "false" ]]; then
                continue
            fi

            echo "check image: $repository"
            check_image "$repository" &
            repository=""
        done
    done
    wait
    cat exit_result
    exit `cat exit_result`
}

check_image() {
    image=$1
    case $image in
        quay.io/*)
            echo "$(tput -T xterm setaf 1)Use the quay.io repository image:$image, which should be replaced.$(tput -T xterm sgr0)"
            echo 1 > exit_result
        ;;
        docker.io/apecloud/*|registry.cn-hangzhou.aliyuncs.com/apecloud/*|apecloud/*)
            check_image_exists "$image"
        ;;
    esac
}

check_image_exists() {
    image=$1
    tag=${image##*:}
    for i in {1..5}; do
        case $tag in
            *arm64*|*amd64*)
                architecture=$( docker manifest inspect "$image" | grep digest )
            ;;
            *)
                architecture=$( docker manifest inspect "$image" | grep architecture )
            ;;
        esac
        if [[ -z "$architecture" ]]; then
            if [[ $i -lt 5 ]]; then
                sleep 1
                continue
            fi
        else
            case $tag in
                *arm64*|*amd64*)
                    echo "$(tput -T xterm setaf 2)$image found $tag architecture$(tput -T xterm sgr0)"
                    break
                ;;
            esac

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
