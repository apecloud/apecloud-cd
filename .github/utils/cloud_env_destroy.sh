#!/usr/bin/env bash
# Clean click test leftovers, run kbecli uninstall to clean up cloud, then clean up env.
# Supports both release-2.3 (kb-cloud-installer) and legacy release-2.2 (Zalando postgresql-operator).
# Explicitly cleans:
#   - click test pods and their kubeconfig/OSS secrets
#   - pg-cluster-values ConfigMap
#   - postgres-operator namespaced resources
#   - Zalando CRDs (operatorconfigurations.acid.zalan.do, postgresqls.acid.zalan.do, postgresteams.acid.zalan.do)
# to avoid Helm "invalid ownership metadata" errors on kb-cloud-installer v2.3+ reinstall.
# Before kubeblocks uninstall, every Cluster and Backup must already be gone.
set -u

KB_NS="${KB_NS:-kb-system}"
CLOUD_NS="${CLOUD_NS:-kubeblocks-cloud-ns}"
KBE_NS="${KBE_NS:-kb-cloud}"
WAIT_SECONDS="${WAIT_SECONDS:-600}"

log() { printf '==> %s\n' "$*"; }

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing $1" >&2; exit 1; }
}

ensure_cli() {
  local name=$1 version=$2 url=$3
  export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"
  if command -v "$name" >/dev/null 2>&1; then
    log "$name present: $(command -v "$name")"
    return 0
  fi
  log "install $name $version"
  curl -fsSL "$url" | bash -s "$version" || return 1
  hash -r
  command -v "$name" >/dev/null 2>&1 || { echo "missing $name after install" >&2; return 1; }
}

release_exists() {
  helm status -n "$1" "$2" >/dev/null 2>&1
}

uninstall_release() {
  local ns=$1 name=$2
  if release_exists "$ns" "$name"; then
    helm uninstall -n "$ns" "$name"
  else
    log "skip $ns/$name, not installed"
  fi
  if release_exists "$ns" "$name"; then
    echo "still installed: $ns/$name" >&2
    return 1
  fi
}

list_kind() {
  local kind=$1 ns=$2
  local out
  # jsonpath stays empty when the list is empty. Do not merge a human-readable
  # "No resources found" line into the name list.
  if ! out=$(kubectl get "$kind" -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>&1); then
    kind_missing "$out" && return 0
    printf '%s\n' "$out" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

kind_missing() {
  printf '%s\n' "$1" | grep -Eq "doesn't have a resource type|could not find the requested resource"
}

wait_empty() {
  local kind=$1 ns=$2
  local deadline=$((SECONDS + WAIT_SECONDS)) left
  while true; do
    left=$(list_kind "$kind" "$ns") || return 1
    if [ -z "$left" ]; then
      log "$ns/$kind gone"
      return 0
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "still present: $ns/$kind" >&2
      printf '%s\n' "$left" >&2
      return 1
    fi
    sleep 10
  done
}

wipe_clusters() {
  local ns=$1 names name
  names=$(list_kind cluster "$ns") || return 1
  if [ -z "$names" ]; then
    log "skip $ns clusters, none"
    return 0
  fi
  for name in $names; do
    log "WipeOut $ns/$name"
    kbcli cluster update --termination-policy=WipeOut -n "$ns" "$name" || return 1
  done
  # shellcheck disable=SC2086
  kbcli cluster delete -n "$ns" $names --auto-approve || return 1
  wait_empty cluster "$ns"
}

list_all() {
  local kind=$1 out
  if ! out=$(kubectl get "$kind" -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>&1); then
    kind_missing "$out" && return 0
    printf '%s\n' "$out" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

delete_backups() {
  local ns=$1 names name
  names=$(list_kind backup "$ns") || return 1
  if [ -z "$names" ]; then
    log "skip $ns backups, none"
    return 0
  fi
  for name in $names; do
    kubectl delete backup "$name" -n "$ns" --force --grace-period=0 --wait=false || true
  done
  sleep 2
  names=$(list_kind backup "$ns") || return 1
  for name in $names; do
    [ -n "$name" ] || continue
    log "strip backup finalizers $ns/$name"
    kubectl patch backup "$name" -n "$ns" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
  done
  wait_empty backup "$ns"
}

namespaces_with() {
  local kind=$1 rows
  rows=$(list_all "$kind") || return 1
  printf '%s\n' "$rows" | awk 'NF {print $1}' | sort -u
}

delete_all_backups() {
  local ns nss
  nss=$(namespaces_with backup) || return 1
  if [ -z "$nss" ]; then
    log "skip backups, none"
    return 0
  fi
  for ns in $nss; do
    delete_backups "$ns" || return 1
  done
}

click_test_pod_names() {
  local ns=$1 names labeled name
  names=$(list_kind pod "$ns") || return 1
  if ! labeled=$(kubectl get pod -n "$ns" -l click-tests/helper \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>&1); then
    printf '%s\n' "$labeled" >&2
    return 1
  fi
  {
    # Older helpers did not have labels, so also match their stable name prefixes.
    printf '%s\n' "$names" | while IFS= read -r name; do
      [ -n "$name" ] || continue
      case "$name" in
        cloud-e2e-web-test-click-*|click-helper-*|click-dbc-*|click-kafka-ssl-*) printf '%s\n' "$name" ;;
      esac
    done
    # The label also catches helpers whose names were truncated or otherwise changed.
    printf '%s\n' "$labeled" | while IFS= read -r name; do
      [ -n "$name" ] || continue
      printf '%s\n' "$name"
    done
  } | sort -u
}

cleanup_click_test_resources() {
  local ns=$CLOUD_NS names name deadline left namespace_error
  if ! namespace_error=$(kubectl get namespace "$ns" 2>&1); then
    case "$namespace_error" in
      *NotFound*|*"not found"*)
        log "skip $ns click test resources, namespace not found"
        return 0
        ;;
      *)
        printf '%s\n' "$namespace_error" >&2
        return 1
        ;;
    esac
  fi

  names=$(click_test_pod_names "$ns") || return 1
  if [ -z "$names" ]; then
    log "skip $ns click test pods, none"
  else
    for name in $names; do
      log "delete click test pod $ns/$name"
      kubectl delete pod "$name" -n "$ns" --force --grace-period=0 --ignore-not-found || return 1
    done
    deadline=$((SECONDS + WAIT_SECONDS))
    while true; do
      left=$(click_test_pod_names "$ns") || return 1
      if [ -z "$left" ]; then
        log "$ns click test pods gone"
        break
      fi
      if [ "$SECONDS" -ge "$deadline" ]; then
        echo "still present: $ns click test pods" >&2
        printf '%s\n' "$left" >&2
        return 1
      fi
      sleep 5
    done
  fi

  # The launcher leaves one kubeconfig Secret per test pod, even after the pod is gone.
  # Older web click tests also created an OSS credentials Secret next to the pod.
  names=$(list_kind secret "$ns") || return 1
  for name in $names; do
    case "$name" in
      cloud-e2e-web-test-click-*-kube|cloud-e2e-web-test-click-*-oss)
        log "delete click test secret $ns/$name"
        kubectl delete secret "$name" -n "$ns" --ignore-not-found || return 1
        ;;
    esac
  done
}

wipe_all_clusters() {
  local ns nss
  nss=$(namespaces_with cluster) || return 1
  if [ -z "$nss" ]; then
    log "skip clusters, none"
    return 0
  fi
  for ns in $nss; do
    wipe_clusters "$ns" || return 1
  done
}

ensure_cleared() {
  local kind left
  for kind in backup cluster; do
    left=$(list_all "$kind") || return 1
    if [ -n "$left" ]; then
      echo "still present: $kind" >&2
      printf '%s\n' "$left" >&2
      return 1
    fi
    log "$kind gone"
  done
}

main() {
  need kubectl
  need helm
  ensure_cli kbcli v1.0.2 https://kubeblocks.io/installer/install_cli.sh || exit 1
  ensure_cli kbecli v0.1.39 https://kubeblocks.io/installer/install_kbecli.sh || exit 1

  log "context $(kubectl config current-context)"

  log "0. cleanup click test resources"
  cleanup_click_test_resources || exit 1

  log "1. kbecli uninstall"
  kbecli uninstall --yes -n "$KBE_NS" || exit 1
  for name in kb-cloud casdoor installer; do
    if release_exists "$KBE_NS" "$name"; then
      echo "still installed: $KBE_NS/$name" >&2
      exit 1
    fi
  done

  # Cleanup legacy postgresql-operator (Zalando acid.zalan.do) resources from release-2.2
  # These leave ConfigMaps (pg-cluster-values) + cluster-scoped CRDs with stale Helm metadata,
  # causing "invalid ownership metadata" errors on kb-cloud-installer v2.3+ install.
  log "1.1. cleanup postgresql-operator (release-2.2 compatibility)"
  for old_name in postgresql-operator postgres-operator pg-operator; do
    uninstall_release "$KBE_NS" "$old_name" || true
  done
  kubectl delete configmap pg-cluster-values -n "$KBE_NS" --ignore-not-found || true
  for kind in deployment statefulset daemonset job pod service configmap secret; do
    kubectl delete "$kind" --ignore-not-found -n "$KBE_NS" \
      -l app=postgres-operator || true
    kubectl delete "$kind" --ignore-not-found -n "$KBE_NS" \
      -l app.kubernetes.io/name=postgres-operator || true
  done

  # Clean Zalando PostgreSQL Operator CRDs (cluster-scoped)
  log "1.2. cleanup zalando CRDs (acid.zalan.do)"
  kubectl delete postgresql,postgresteam,operatorconfiguration \
    --all --all-namespaces --ignore-not-found || true
  for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'acid\.zalan\.do' || true); do
    kubectl delete "$crd" --ignore-not-found || true
  done

  log "delete leftover jobs in $KBE_NS"
  kubectl delete job --all -n "$KBE_NS" --ignore-not-found || exit 1
  left=$(list_kind job "$KBE_NS") || exit 1
  if [ -n "$left" ]; then
    echo "still present: $KBE_NS/job" >&2
    printf '%s\n' "$left" >&2
    exit 1
  fi

  log "2. uninstall kb-monitor"
  uninstall_release "$KB_NS" kb-monitor || exit 1

  log "3. wipe clusters"
  wipe_all_clusters || exit 1

  log "4. delete backups"
  delete_all_backups || exit 1

  log "5. uninstall gemini"
  kubectl delete job -n "$KB_NS" -l app.kubernetes.io/instance=gemini --ignore-not-found || exit 1
  uninstall_release "$KB_NS" gemini || exit 1

  log "6. uninstall bootstrapper"
  uninstall_release "$KB_NS" bootstrapper || exit 1

  log "7. uninstall kubeblocks"
  ensure_cleared || exit 1
  if release_exists "$KB_NS" kubeblocks; then
    kbcli kubeblocks uninstall --auto-approve --remove-namespace=false --remove-pvcs=true --timeout=10m0s --wait=true
  else
    log "skip kubeblocks, not installed"
  fi
  if release_exists "$KB_NS" kubeblocks; then
    echo "still installed: $KB_NS/kubeblocks" >&2
    exit 1
  fi
  log "done"
}

main "$@"
