#!/usr/bin/env bash
CHART_REGISTRY=${1:-"docker.io"}
CHART_DIR=${2:-"addons"}

main() {
    if [[ -z "${CHART_REGISTRY}" ]]; then
        CHART_REGISTRY="docker.io"
    fi
    if [[ ! -d "${CHART_DIR}" ]]; then
        echo "not found chart dir: $addon_dir"
        return
    fi
        
    values_registry="registry: "
    values_repository="repository: "
  
    for addon in $(ls $CHART_DIR); do
        values_file="$CHART_DIR/$addon/values.yaml"
        if [ ! -f "$values_file" ]; then
            echo "not found values file: $values_file"
            continue 
        fi
        echo "set values file: $values_file"
        tempFile=$(mktemp)
        echo "" >> "$values_file"
        lineno=1
        while IFS= read -r lineValue; do
            if [[ "$lineValue" == *"${values_registry}"* && "$lineValue" != *"${values_registry}"'""'* ]]; then
                echo "set $lineValue to registry:${CHART_REGISTRY}"
                set_text_head=${lineValue%registry: *}
                set_text="${set_text_head}${values_registry}${CHART_REGISTRY}"
                echo "$set_text" >> "$tempFile"
            elif [[ "$lineValue" == *"${values_repository}"* && "$lineValue" != *"${values_repository}"'""'* ]]; then
                echo "set $lineValue to repository:apecloud"
                set_text_head=${lineValue%repository: *}
                set_text_end=${lineValue#*repository: }
                case $set_text_end in
                    *"/"*)
                        set_text=${set_text_end#*/}
                    ;;
                    *)
                        set_text=${set_text_end}
                    ;;
                esac
                set_text="${set_text_head}${values_repository}apecloud/${set_text}"
                echo "$set_text" >> "$tempFile"
            else
                echo "$lineValue" >> "$tempFile"
            fi
            ((lineno++))
        done < "$values_file"
        if [[ $lineno -gt 2 ]]; then
            mv "$tempFile" "$values_file"
        fi
        echo "set values file: $values_file successfully."
    done
}

main "$@"
