---
name: kubeblocks-e2e-workflow
description: >
  Maintain the KubeBlocks all-version E2E workflow kubeblocks-e2e-test.yml.
  Engine matrix covers postgresql, redis, mongodb, clickhouse, elasticsearch, kafka, and 20+ engines.
  Use when adding/removing engine versions, updating send-message summary jobs,
  or checking consistency between test jobs, send-message jobs, and terraform-destroy-k8s needs.
---

# KubeBlocks E2E Workflow Maintainer

## Workflow Architecture

The workflow [`kubeblocks-e2e-test.yml`](../../../.github/workflows/kubeblocks-e2e-test.yml) has 5 phases:

1. **Infrastructure**: `terraform-init-k8s` creates the cluster.
2. **Base Install**: `test-kubeblocks` installs KubeBlocks (test-type `0`).
3. **Engine Tests**: Parallel jobs per engine/version calling `kbcli-test.yml`.
4. **Result Aggregation**: `send-message-*` jobs collect outputs and notify.
5. **Cleanup**: `terraform-destroy-k8s` tears down the cluster (`if: always()`).

### Dependency Waves

Engines are organized into waves. Jobs inside a wave run in parallel. Waves run sequentially:

| Wave | Engines | Depends On |
|------|---------|------------|
| 0 (base) | `test-kubeblocks` | `terraform-init-k8s` |
| 1 | postgresql-* | `test-kubeblocks` |
| 2 | redis-*, redis-cluster-* | Wave 1 (`postgresql-*`) |
| 3 | mongodb-*, mongodb-shard-* | Wave 2 (`redis-cluster-*`) |
| 4 (independent) | clickhouse, elasticsearch, etcd, milvus, nebula, tidb, minio, starrocks, tdengine, nacos, kingbase, hive, kafka-*, oceanbase-ent-*, asmysql-* | `test-kubeblocks` |
| 5 (late) | rabbitmq-*, zookeeper-* | Wave 4 (all independent quick jobs) |

**Rule of thumb**: If an engine test is fast/safe, put it in Wave 4. If it must wait for resources or has side-effects, place it after its prerequisite wave.

### Send-Message Grouping

Each `send-message-*` job aggregates outputs from a specific set of engine families. Its `needs` must list **every** test job in those families.

| send-message job | Engine families covered |
|------------------|------------------------|
| `send-message` | postgresql, clickhouse, elasticsearch, etcd, milvus, nebula, tidb, minio, starrocks-ent, tdengine, asmysql, kingbase, hive, nacos, doris, kafka-combined, kafka-separated, oceanbase-ent-distribution, oceanbase-ent-replication |
| `send-message-redis` | redis, redis-cluster |
| `send-message-mongodb` | mongodb, mongodb-shard |
| `send-message-zookeeper-rabbitmq` | rabbitmq, zookeeper |


## Cross-File Impact

> **Modifying `kbcli-test.yml` affects every engine job.** This reusable workflow is called by
> `kubeblocks-e2e-test.yml`, `kbcli-test-k8s.yml`, `cloud-e2e-engine.yml`, and all
> `cloud-e2e-schedule-*.yml` workflows. Any new input/output must be propagated to all callers.

> **Modifying `terraform-init.yml` affects downstream job inputs.** Its output
> `k8s-cluster-name` is consumed by every engine job. Adding a new output or changing existing
> outputs requires corresponding updates in `kubeblocks-e2e-test.yml` and `kbcli-test-k8s.yml`.

> **Modifying `terraform-destroy-k8s.needs` is mandatory for new send-message jobs.** If you add
> a new `send-message-*` job, it must be listed in `terraform-destroy-k8s.needs` so cleanup waits
> for it.

## Job YAML Template

### Test Job Template

```yaml
  test-<engine>-<version-sanitized>:
    if: ${{ needs.terraform-init-k8s.result == 'success' && always() && (inputs.TEST_TYPE == '' || contains(inputs.TEST_TYPE, '<engine>|') || endsWith(inputs.TEST_TYPE, '<engine>')) && ! contains(inputs.TEST_TYPE, '-<engine>') }}
    needs: [ terraform-init-k8s, test-kubeblocks ]
    uses: ./.github/workflows/kbcli-test.yml
    with:
      cloud-provider: ${{ inputs.CLOUD_PROVIDER }}
      region: ${{ inputs.REGION }}
      release-version: "${{ inputs.KB_VERSION }}"
      test-type: "<TEST_TYPE_NUMBER>"
      test-type-name: "<engine>-<version-sanitized>"
      test-args: "--service-version <VERSION> ${{ inputs.ARGS }}"
      k8s-cluster-name: ${{ needs.terraform-init-k8s.outputs.k8s-cluster-name }}
      artifact-name: cicd-${{ inputs.CLOUD_PROVIDER }}-${{ github.sha }}
      branch-name: ${{ inputs.BRANCH_NAME }}
      random-suffix: ${{ needs.test-kubeblocks.outputs.random-suffix }}
    secrets: inherit
```

**Notes**:
- `<version-sanitized>`: dots replaced with hyphens (e.g. `3.3.6` → `3-3-6`).
- `needs` for Wave 2+ jobs must include the prerequisite wave jobs. See examples in the file.
- `if` condition for engine groups with multiple job families (e.g. `mongodb|mongodb-shard`) should include both.

### Topology Variants

Some engines expose `--topology <name>` in `test-args`:

```yaml
      test-args: "--service-version <VERSION> --topology <TOPOLOGY> --replicas <N> ${{ inputs.ARGS }}"
```

Examples: `kafka-combined` (`combined_monitor`), `kafka-separated` (`separated_monitor`), `oceanbase-ent-distribution` (`distribution`), `oceanbase-ent-replication` (`replication`).

### Send-Message Steps Template

Each send-message job has three steps:
1. **send message** (kbcli) - aggregates `needs.<job>.outputs.test-result` and `test-result-report` using `utils.sh --type 36`.
2. **Setup ossutil** + **Upload test result log to oss** - downloads existing log, appends current results, uploads back.
3. **send message** (report) - sends the OSS URL to `REPORT_BOT_WEBHOOK`.

When adding a new send-message job, copy the pattern from `send-message-mongodb` and replace the engine names.

## Engine Quick Reference

Use this table when adding, removing, or modifying an engine/version. It is derived from the actual `kubeblocks-e2e-test.yml` workflow.

| Engine family | test-type | Job ID pattern | Send-message job(s) | Notes |
|---|---|---|---|---|
| `asmysql` | `21` | `test-asmysql-<V>` | `send-message` | - |
| `clickhouse` | `29` | `test-clickhouse-<V>` | `send-message` | - |
| `doris` | `41` | `test-doris-<V>` | `send-message` | - |
| `elasticsearch` | `25` | `test-elasticsearch-<V>` | `send-message` | - |
| `etcd` | `15` | `test-etcd-<V>` | `send-message` | - |
| `hive` | `69` | `test-hive-<V>` | `send-message` | - |
| `kafka-combined` | `7` | `test-kafka-combined` | `send-message` | topology: combined_monitor |
| `kafka-separated` | `7` | `test-kafka-separated` | `send-message` | topology: separated_monitor |
| `kingbase` | `58` | `test-kingbase-<V>` | `send-message` | - |
| `milvus` | `28` | `test-milvus-<V>` | `send-message` | - |
| `minio` | `51` | `test-minio-<V>` | `send-message` | - |
| `nacos` | `71` | `test-nacos-<V>` | `send-message` | - |
| `nebula` | `12` | `test-nebula-<V>` | `send-message` | - |
| `oceanbase-ent-distribution` | `44` | `test-oceanbase-ent-distribution` | `send-message` | replicas: 3; topology: distribution |
| `oceanbase-ent-replication` | `44` | `test-oceanbase-ent-replication` | `send-message` | replicas: 2; topology: replication |
| `postgresql` | `2` | `test-postgresql-<V>` | `send-message` | - |
| `starrocks-ent` | `45` | `test-starrocks-ent-<V>` | `send-message` | - |
| `tdengine` | `27` | `test-tdengine-<V>` | `send-message` | - |
| `tidb` | `34` | `test-tidb-<V>` | `send-message` | - |
| `redis` | `5` | `test-redis-<V>` | `send-message-redis` | - |
| `redis-cluster` | `48` | `test-redis-cluster-<V>` | `send-message-redis` | - |
| `mongodb` | `6` | `test-mongodb-<V>` | `send-message-mongodb` | - |
| `mongodb-shard` | `67` | `test-mongodb-shard-<V>` | `send-message-mongodb` | - |
| `rabbitmq` | `53` | `test-rabbitmq-<V>` | `send-message-zookeeper-rabbitmq` | - |
| `zookeeper` | `32` | `test-zookeeper-<V>` | `send-message-zookeeper-rabbitmq` | - |

### Legend

- `<V>`: version placeholder. Dots are replaced with hyphens in job IDs (`3.3.6` → `3-3-6`).
- Major-only abbreviations like `elasticsearch-8` use `--service-version 8`; kbcli-test resolves the patch internally.

For historical version matrices and dependency-wave background, see [`references/workflow-structure.md`](references/workflow-structure.md). The quick reference above is regenerated from the real `kubeblocks-e2e-test.yml`.


## Maintenance Procedures

Use this checklist for any change to the engine matrix. Always finish by running
`scripts/check_workflow.py`.

### Add a new engine, e.g. `doris`

1. Pick a `test-type` number from kbcli-test.yml or ask the team.
2. Choose the dependency wave:
   - Fast/no side effects → **Wave 4** (independent, after `test-kubeblocks`).
   - Needs resource isolation or has prerequisites → place after its prerequisite wave.
3. Generate job stubs (or copy a Wave 4 engine job):
   ```bash
   python3 skills/e2e-testing/kubeblocks-e2e-workflow/scripts/generate_engine_jobs.py \
       doris 99 2.1.6,4.0.5
   ```
4. Paste the generated YAML into `kubeblocks-e2e-test.yml` in the correct wave section.
5. Add the new jobs to the appropriate `send-message-*` job's `needs`, or create a new
   `send-message-<engine>` job.
6. Add that send-message job to `terraform-destroy-k8s.needs`.
7. Run validation:
   ```bash
   python3 skills/e2e-testing/kubeblocks-e2e-workflow/scripts/check_workflow.py \
       .github/workflows/kubeblocks-e2e-test.yml
   ```

### Add a new version to an existing engine, e.g. PostgreSQL 19

1. Find the latest version job for that engine (e.g. `test-postgresql-18`).
2. Copy the entire job block.
3. Replace the job ID suffix: `test-postgresql-18` → `test-postgresql-19`.
4. Update `test-type-name`: `postgresql-18` → `postgresql-19`.
5. Update `--service-version`: `18` → `19`.
6. Add `test-postgresql-19` to the `needs` list of the matching `send-message-*` job.
7. Run `scripts/check_workflow.py`.

### Remove an engine or version

1. Delete the corresponding `test-*` job block(s).
2. Remove the deleted job ID from **every** `needs` array referencing it
   (downstream test jobs, send-message jobs, `terraform-destroy-k8s`).
3. Remove the deleted job ID from every `send-message-*` step body that aggregates outputs.
4. Run `scripts/check_workflow.py`.

### Fix `terraform-destroy-k8s` running too early

If cleanup starts before a send-message job finishes, the omitted send-message job is missing
from `terraform-destroy-k8s.needs`. Add it, then re-run `check_workflow.py`.

## Automated Helpers

- **`scripts/generate_engine_jobs.py`** - Generate test job YAML snippets for a new engine/version set.
- **`scripts/check_workflow.py`** - Validate that every test job is referenced in a send-message job, check for orphaned jobs, and verify `terraform-destroy-k8s.needs` completeness.

## Common Patterns

### `if` Condition Variants

All test jobs:
```yaml
if: ${{ needs.terraform-init-k8s.result == 'success' && always() && (inputs.TEST_TYPE == '' || contains(inputs.TEST_TYPE, '<engine>|') || endsWith(inputs.TEST_TYPE, '<engine>')) && ! contains(inputs.TEST_TYPE, '-<engine>') }}
```

For engines with sub-variants (e.g. `mongodb` + `mongodb-shard`):
```yaml
if: ${{ needs.terraform-init-k8s.result == 'success' && always() && (inputs.TEST_TYPE == '' || contains(inputs.TEST_TYPE, 'mongodb|') || endsWith(inputs.TEST_TYPE, 'mongodb') || contains(inputs.TEST_TYPE, 'mongodb-shard|') || endsWith(inputs.TEST_TYPE, 'mongodb-shard')) && ! contains(inputs.TEST_TYPE, '-mongodb') }}
```

For engines with prefix filters (e.g. `redis` without `redis-cluster`):
```yaml
if: ${{ needs.terraform-init-k8s.result == 'success' && always() && (inputs.TEST_TYPE == '' || contains(inputs.TEST_TYPE, 'redis|') || endsWith(inputs.TEST_TYPE, 'redis')) }}
```

Send-message `if` mirrors the test job conditions plus `always()`:
```yaml
if: ${{ always() && (inputs.TEST_TYPE == '' || contains(inputs.TEST_TYPE, '<engine>|') || endsWith(inputs.TEST_TYPE, '<engine>')) }}
```
