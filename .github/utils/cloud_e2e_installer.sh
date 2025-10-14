#!/usr/bin/env bash

set +e
set -o nounset

patch_kb_monitor_metrics_collector_resources() {
    echo "Patch kb-monitor-metrics-collector resources"
    kubectl patch deployment kb-monitor-metrics-collector -n kb-system --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources",
    "value": {
      "requests": {
        "memory": "128Mi",
        "cpu": "100m"
      },
      "limits": {
        "memory": "2Gi",
        "cpu": "1"
      }
    }
  }
]'
}

patch_kb_monitor_resources() {
    echo "Patch kb-monitor resources"
    kubectl patch daemonset kb-monitor -n kb-system --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources",
    "value": {
      "requests": {
        "memory": "128Mi",
        "cpu": "100m"
      },
      "limits": {
        "memory": "2Gi",
        "cpu": "2"
      }
    }
  }
]'
}

check_kb_monitor_metrics_collector_resources() {
    kb_monitor_metrics_collector_resources=$(kubectl get deployment kb-monitor-metrics-collector -n kb-system -o json | jq '.spec.template.spec.containers[0].resources')
    kb_monitor_metrics_collector_request_cpu=$(echo "${kb_monitor_metrics_collector_resources}" | jq -r '.requests.cpu')
    kb_monitor_metrics_collector_request_memory=$(echo "${kb_monitor_metrics_collector_resources}" | jq -r '.requests.memory')
    if [[ ! ("${kb_monitor_metrics_collector_request_cpu}" == "100m" || "${kb_monitor_metrics_collector_request_memory}" == "128Mi") ]]; then
        echo "kb_monitor_metrics_collector_resources:${kb_monitor_metrics_collector_resources}"
        patch_kb_monitor_metrics_collector_resources
    fi

}

check_kb_monitor_resources() {
    kb_monitor_resources=$(kubectl get daemonset kb-monitor -n kb-system -o json | jq '.spec.template.spec.containers[0].resources')
    kb_monitor_request_cpu=$(echo "${kb_monitor_resources}" | jq -r '.requests.cpu')
    kb_monitor_request_memory=$(echo "${kb_monitor_resources}" | jq -r '.requests.memory')
    if [[ ! ("${kb_monitor_request_cpu}" == "100m" || "${kb_monitor_request_memory}" == "128Mi") ]]; then
        echo "kb_monitor_resources:${kb_monitor_resources}"
        patch_kb_monitor_resources
    fi
}

check_kb_monitor() {
    patch_times=1
    patch_flag=0
    while true; do
        gemini_monitor_deploy=$(helm list -n kb-system | (grep "gemini-monitor" | grep "deployed" || true))
        if [[ -z "${gemini_monitor_deploy}" ]]; then
            echo "Waiting for Gemini monitor to be ready..."
            sleep 10
            continue
        fi

        kb_monitor_metrics_collector_deployment=$(kubectl get deployment -n kb-system | (grep "kb-monitor-metrics-collector" || true ))
        if [[ -n "${kb_monitor_metrics_collector_deployment}" ]]; then
            check_kb_monitor_metrics_collector_resources
            patch_flag=1
        fi

        kb_monitor_daemonset=$(kubectl get daemonset -n kb-system | (grep "kb-monitor" || true ))
        if [[ -n "${kb_monitor_daemonset}" ]]; then
            check_kb_monitor_resources
            patch_flag=1
        fi

        if [[ $patch_flag -eq 1 ]]; then
            patch_times=$(( $patch_times + 1 ))
            patch_flag=0
        fi

        if [[ $patch_times -gt 5 ]]; then
            echo "Patch kb-monitor resources done"
            break
        fi

        sleep 5
    done
}

check_kb_monitor