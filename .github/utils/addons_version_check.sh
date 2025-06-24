#!/bin/bash

ADDON_NAME=${1:-""}
IMAGE_NAME=${2:-""}

# Function to get latest versions for a Docker image
get_latest_versions() {
    local repo_path=${1:-"$IMAGE_NAME"}
    local image=${2-"$ADDON_NAME"}
    limits=100
    pattern="^v?[0-9]+\.[0-9]+(\.[0-9]+)?$"
    # if image = RabbitMQ, then match version like 3.12.0-management
    if [ "$image" == "rabbitmq" ]; then
        pattern="^v?[0-9]+\.[0-9]+(\.[0-9]+)?-management$"
    fi
    # if image = Redis, then match version like 7.2.0-v14
    if [ "$image" == "redis" ]; then
        pattern="^v?[0-9]+\.[0-9]+(\.[0-9]+)?(-v[0-9]+)?$"
    fi

    # echo "=== Checking $image ==="
    page=1
    results=()
    while true; do
        resp=$(curl -s "https://registry.hub.docker.com/v2/repositories/$repo_path/tags?page_size=$limits&page=$page")
        names=$(echo "$resp" | jq -r '.results[].name')
        if [ -z "$names" ]; then
            break
        fi
        # 过滤版本
        filtered=$(echo "$names" | grep -E "${pattern}")
        if [ "$image" == "rabbitmq" ]; then
            filtered=$(echo "$filtered" | sed 's/-management$//')
        fi
        results+=("$filtered")
        # 如果已经有匹配结果，可以 break（可选：如需所有页则注释掉）
        if [ -n "$filtered" ]; then
            break
        fi
        # 检查是否还有下一页
        next=$(echo "$resp" | jq -r '.next')
        if [ "$next" == "null" ]; then
            break
        fi
        page=$((page+1))
    done
    # 合并所有结果，排序、去重、分组取最大
    printf "%s\n" "${results[@]}" \
    | sort -V \
    | awk -F. '{
        key = $1"."$2;
        version = $0;
        version_tmp = $0;
        if (version_tmp ~ /-v/) {
            sub(/-v/, ".", version_tmp);
        }
        if (!max[key] || version_tmp > max[key] ) {
            max[key] = version;
        }
    }
    END {
        for (k in max) print max[k];
    }' \
    | sort -Vr
}

if [ -z "$ADDON_NAME" ]; then
    echo "Usage: $0 <addon_name> [<image_name>]"
    return
fi

if [ -z "$IMAGE_NAME" ]; then
    case "$ADDON_NAME" in
        mysql)
            IMAGE_NAME="library/mysql"
        ;;
        postgresql)
            IMAGE_NAME="library/postgres"
        ;;
        redis)
            IMAGE_NAME="redis/redis-stack-server"
        ;;
        mongodb)
            IMAGE_NAME="library/mongo"
        ;;
        kafka)
            IMAGE_NAME="bitnami/kafka"
        ;;
        qdrant)
            IMAGE_NAME="qdrant/qdrant"
        ;;
        rabbitmq)
            IMAGE_NAME="library/rabbitmq"
        ;;
        milvus)
            IMAGE_NAME="milvusdb/milvus"
        ;;
        elasticsearch)
            IMAGE_NAME="library/elasticsearch"
        ;;
    esac
fi

get_latest_versions "${IMAGE_NAME}"
