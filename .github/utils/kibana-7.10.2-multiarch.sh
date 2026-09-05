#!/usr/bin/env bash
set -euo pipefail

AMD64=sha256:b5a72f8d1ded65f1542034595a5e0862df1619e0059ada6bb081a717aec13056
ARM64=sha256:f79802f5ba6d6f1636b559b2c2d68f2ff057cb04bbd0ead0cb521c15f37b5030
HUB=docker.io/apecloud/kibana
ALI=apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/kibana
AUTH_FILE="${HOME}/.docker/config.json"

raw() { skopeo inspect --authfile "$AUTH_FILE" --raw "docker://$1"; }
digest() { raw "$1" | sha256sum | awk '{print "sha256:" $1}'; }
copy() { skopeo copy --authfile "$AUTH_FILE" --all --preserve-digests --retry-times 3 "docker://$1" "docker://$2"; }
check_config() {
    skopeo inspect --authfile "$AUTH_FILE" --config "docker://$1" |
        jq -e --arg arch "$2" '.os == "linux" and .architecture == $arch' >/dev/null
}
check_index() {
    raw "$1" | jq -e --arg amd "$AMD64" --arg arm "$ARM64" '
      (.manifests | length) == 2 and
      ([.manifests[] | {digest, os: .platform.os, arch: .platform.architecture}] | sort_by(.arch)) ==
      [{digest: $amd, os: "linux", arch: "amd64"}, {digest: $arm, os: "linux", arch: "arm64"}]' >/dev/null
}

prepare() {
    check_config "$ALI@$AMD64" amd64
    check_config "docker.io/jamesgarside/kibana@$ARM64" arm64
    # Existing releases must still be the previously inspected AMD64 image.
    for repo in "$HUB" "$ALI"; do
        old=$(digest "$repo:7.10.2")
        echo "Existing $repo:7.10.2 = $old" | tee -a "$GITHUB_STEP_SUMMARY"
        [[ "$old" == "$AMD64" ]] || { echo 'Unexpected existing release; stopping before publication'; exit 1; }
    done
    for repo in "$HUB" "$ALI"; do
        copy "$ALI@$AMD64" "$repo:7.10.2-amd64"
        copy "docker.io/jamesgarside/kibana@$ARM64" "$repo:7.10.2-arm64"
        [[ $(digest "$repo:7.10.2-amd64") == "$AMD64" ]]
        [[ $(digest "$repo:7.10.2-arm64") == "$ARM64" ]]
    done
    docker buildx imagetools create --tag "$HUB:7.10.2-multiarch" "$HUB@$AMD64" "$HUB@$ARM64"
    index=$(digest "$HUB:7.10.2-multiarch")
    check_index "$HUB@$index"
    copy "$HUB@$index" "$ALI:7.10.2-multiarch"
    [[ $(digest "$ALI:7.10.2-multiarch") == "$index" ]]
    check_index "$ALI@$index"
    echo "index_digest=$index" >> "$GITHUB_OUTPUT"
    echo "Candidate index in both registries: $index" >> "$GITHUB_STEP_SUMMARY"
}

smoke() {
    [[ "$TEST_ARCH" == amd64 || "$TEST_ARCH" == arm64 ]]
    [[ "$INDEX_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]
    cleanup() {
        result=$?
        if [[ $result -ne 0 ]]; then
            docker logs kibana-test 2>&1 | tail -n 100 || true
            docker logs elasticsearch-test 2>&1 | tail -n 50 || true
        fi
        docker rm -f kibana-test elasticsearch-test >/dev/null 2>&1 || true
        docker network rm kibana-test >/dev/null 2>&1 || true
    }
    trap cleanup EXIT
    sudo sysctl -w vm.max_map_count=262144
    docker network create kibana-test
    docker run -d --name elasticsearch-test --network kibana-test --network-alias elasticsearch \
        -p 127.0.0.1:9200:9200 -e discovery.type=single-node -e xpack.security.enabled=false \
        -e ES_JAVA_OPTS='-Xms512m -Xmx512m' docker.elastic.co/elasticsearch/elasticsearch:7.10.2
    ready=false
    for ((i=0; i<90; i++)); do
        if curl -fsS 'http://127.0.0.1:9200/_cluster/health?wait_for_status=yellow&timeout=1s' | jq -e '.status == "yellow" or .status == "green"' >/dev/null; then ready=true; break; fi
        sleep 2
    done
    [[ "$ready" == true ]]
    curl -fsS http://127.0.0.1:9200 | jq -e '.version.number == "7.10.2"'
    image="$HUB@$INDEX_DIGEST"
    docker pull --platform "linux/$TEST_ARCH" "$image"
    expected_arch=$TEST_ARCH
    [[ "$TEST_ARCH" != amd64 ]] || expected_arch=x64
    docker run --rm --platform "linux/$TEST_ARCH" --entrypoint /usr/share/kibana/node/bin/node "$image" \
        -e "const p=require('/usr/share/kibana/package.json'); console.log(JSON.stringify({version:p.version,arch:process.arch})); if(p.version!=='7.10.2'||process.arch!=='$expected_arch')process.exit(1)"
    docker run -d --platform "linux/$TEST_ARCH" --name kibana-test --network kibana-test \
        -p 127.0.0.1:5601:5601 -e ELASTICSEARCH_HOSTS='["http://elasticsearch:9200"]' \
        -e SERVER_HOST=0.0.0.0 "$image"
    ready=false
    for ((i=0; i<180; i++)); do
        if curl -fsS http://127.0.0.1:5601/api/status -o /tmp/kibana-status.json &&
            jq -e '.version.number == "7.10.2" and .status.overall.state == "green"' /tmp/kibana-status.json >/dev/null; then ready=true; break; fi
        [[ $(docker inspect -f '{{.State.Running}}' kibana-test) == true ]] || break
        sleep 5
    done
    [[ "$ready" == true ]]
    jq '{version: .version.number, status: .status.overall.state}' /tmp/kibana-status.json
    curl -fsSL http://127.0.0.1:5601/app/home -o /tmp/kibana-home.html
    test -s /tmp/kibana-home.html
    echo "linux/$TEST_ARCH: package version, Node architecture, Elasticsearch connection, /api/status green, /app/home passed. ARM64 runs under QEMU on AMD64." >> "$GITHUB_STEP_SUMMARY"
}

promote() {
    [[ "$INDEX_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]
    # Recheck both repositories before changing either release tag.
    for repo in "$HUB" "$ALI"; do
        check_index "$repo@$INDEX_DIGEST"
        [[ $(digest "$repo:7.10.2-amd64") == "$AMD64" ]]
        [[ $(digest "$repo:7.10.2-arm64") == "$ARM64" ]]
        old=$(digest "$repo:7.10.2")
        [[ "$old" == "$AMD64" || "$old" == "$INDEX_DIGEST" ]]
    done
    for repo in "$HUB" "$ALI"; do
        copy "$repo@$INDEX_DIGEST" "$repo:7.10.2"
        [[ $(digest "$repo:7.10.2") == "$INDEX_DIGEST" ]]
        check_index "$repo:7.10.2"
        echo "Published $repo:7.10.2@$INDEX_DIGEST; rollback image: $repo@$AMD64" | tee -a "$GITHUB_STEP_SUMMARY"
    done
}

case "${1:-}" in
    prepare) prepare ;;
    smoke) smoke ;;
    promote) promote ;;
    *) echo 'Expected prepare, smoke, or promote' >&2; exit 2 ;;
esac
