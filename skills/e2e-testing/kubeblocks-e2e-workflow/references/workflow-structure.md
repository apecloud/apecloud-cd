# KubeBlocks E2E Test Workflow Structure Reference

## Table of Contents
- [Engine Catalog](#engine-catalog)
- [Dependency Waves](#dependency-waves)
- [Send-Message Job Coverage](#send-message-job-coverage)
- [Version Naming Conventions](#version-naming-conventions)

## Engine Catalog

### Wave 1 (after test-kubeblocks)
| Job ID Pattern | test-type | Versions in Workflow | Versions (full) |
|----------------|-----------|----------------------|-----------------|
| `test-postgresql-<V>` | 2 | 18, 17, 16, 15, 14, 12 | 18.1.0, 17.5.0, 16.9.0, 16.4.0, 15.13.0, 15.7.0, 14.18.0, 14.8.0, 14.7.2, 12.22.0, 12.15.0, 12.14.1, 12.14.0 |

### Wave 2 (after postgresql)
| Job ID Pattern | test-type | Versions in Workflow | Versions (full) |
|----------------|-----------|----------------------|-----------------|
| `test-redis-<M>-<m>` | 5 | 8.4, 8.2, 8.0, 7.4, 7.2, 7.0, 6.2 | 8.6.3, 8.4.3, 8.4.0, 8.2.6, 8.2.3, 8.2.2, 8.2.1, 8.0.5, 8.0.4, 8.0.3, 8.0.1, 7.4.9, 7.4.7, 7.4.6, 7.4.5, 7.4.2, 7.2.14, 7.2.12, 7.2.11, 7.2.10, 7.2.7, 7.2.4, 7.0.6, 6.2.22, 6.2.19, 6.2.18, 6.2.17, 6.2.14, 5.0.12 |
| `test-redis-cluster-<M>-<m>` | 48 | 8.4, 8.2, 8.0, 7.4, 7.2, 7.0 | (same as redis) |

### Wave 3 (after redis-cluster)
| Job ID Pattern | test-type | Versions in Workflow | Versions (full) |
|----------------|-----------|----------------------|-----------------|
| `test-mongodb-<M>` | 6 | 8, 7, 6, 5, 4 | 8.0.17, 7.0.28, 6.0.27, 5.0.29, 4.4.29, 4.0.28 |
| `test-mongodb-shard-<M>` | 67 | 8, 7, 6, 5, 4 | (same as mongodb) |

### Wave 4 (independent, after test-kubeblocks)
| Job ID Pattern | test-type | Versions in Workflow | Notes |
|----------------|-----------|----------------------|-------|
| `test-clickhouse-<YY>` | 29 | 25, 24, 22 | Full versions: 25.9.7, 25.4.4, 24.12.2, 24.8.3, 24.7.2, 22.9.4, 22.8.21, 22.3.20, 22.3.18 |
| `test-elasticsearch-<M>` | 25 | 8, 7, 6 | Full versions: 8.15.5, 8.8.2, 8.1.3, 7.10.2, 7.10.1, 7.8.1, 7.7.1, 6.8.23 |
| `test-etcd-<M>-<m>` | 15 | 3.6, 3.5 | 3.6.1, 3.5.15, 3.5.6 |
| `test-hive-<M>-<m>` | 69 | 4.0, 3.1 | 4.0.1, 3.1.3, 3.1.2 |
| `test-kafka-combined` | 7 | 3 | topology: `combined_monitor` |
| `test-kafka-separated` | 7 | 3 | topology: `separated_monitor` |
| `test-kingbase-<M>` | 58 | 9, 8 | 9.3.15, 9.1.10, 8.6.8 |
| `test-milvus-<M>-<m>` | 28 | 2.5, v2.3 | 2.5.13, v2.3.2 |
| `test-minio-<YYYY>` | 51 | 2025, 2024 | 2025.10.15, 2024.6.29 |
| `test-nacos-<M>-<m>` | 71 | 3.1, 2.4 | 3.1.1, 2.4.3 |
| `test-nebula-<M>-<m>` | 12 | v3.8, v3.5 | v3.8.0, v3.5.0 |
| `test-oceanbase-ent-distribution` | 44 | 4.2 | topology: `distribution`, replicas: 3 |
| `test-oceanbase-ent-replication` | 44 | 4.2 | topology: `replication`, replicas: 2 |
| `test-asmysql-<M>-<m>` | 21 | 8.4, 8.0, 5.7 | 8.4.7, 8.4.3, 8.4.2, 8.4.1, 8.4.0, 8.0.44, 8.0.41, 8.0.39, 8.0.38, 8.0.37, 8.0.36, 8.0.35, 8.0.34, 8.0.33, 5.7.44 |
| `test-starrocks-ent-<M>-<m>` | 45 | 3.4, 3.3, 3.2 | 3.4.2, 3.4.1, 3.3.3, 3.3.2, 3.3.0, 3.2.2 |
| `test-tdengine-<M>-<m>-<p>` | 27 | 3.3.8, 3.3.7, 3.3.6 | 3.3.8-8, 3.3.7-5, 3.3.6-13, 3.3.6-9 |
| `test-tidb-<M>` | 34 | 8, 7, 6 | 8.4.0, 7.5.2, 7.1.5, 6.5.12 |
| `test-zookeeper-<M>-<m>` | 32 | 3.9, 3.8, 3.7, 3.6, 3.4 | 3.9.4, 3.9.2, 3.8.4, 3.7.2, 3.6.4 |

### Wave 5 (late, after Wave 4 quick jobs)
| Job ID Pattern | test-type | Versions in Workflow | Versions (full) |
|----------------|-----------|----------------------|-----------------|
| `test-rabbitmq-<M>-<m>` | 53 | 4.2, 4.1, 4.0, 3.13, 3.12, 3.11, 3.10, 3.9, 3.8 | 4.2.1, 4.1.6, 4.0.9, 3.13.7, 3.12.14, 3.11.28, 3.10.25, 3.9.29, 3.8.34 |

**Dependency list for Wave 5**: `test-nebula-3-8`, `test-nebula-3-5`, `test-etcd-3-6`, `test-etcd-3-5`, `test-elasticsearch-8`, `test-elasticsearch-7`, `test-elasticsearch-6`, `test-milvus-2-5`, `test-milvus-2-3`, `test-clickhouse-25`, `test-clickhouse-24`, `test-clickhouse-22`, `test-tidb-8`, `test-tidb-7`, `test-tidb-6`, `test-minio-2025`, `test-minio-2024`.

### Missing Engines (not yet in workflow)
The following engines are defined in the version manifest but have **no jobs** in the workflow yet:

- `doris`: 4.0.5, 2.1.6
- `hadoop`: 3.3.6, 3.3.1
- `kafka-broker`: 3.9.0, 3.8.1, 3.7.1, 3.3.2, 2.8.2, 2.7.0
- `kafka-controller`: 3.9.0, 3.8.1, 3.7.1, 3.3.2
- `mongos`: 8.0.17, 7.0.28, 6.0.27, 5.0.29, 4.4.29, 4.0.28
- `mysql`: 8.4.7, 8.4.3, 8.4.2, 8.4.1, 8.4.0, 8.0.44, 8.0.41, 8.0.39, 8.0.38, 8.0.37, 8.0.36, 8.0.35, 8.0.34, 8.0.33, 5.7.44
- `oracle`: 23.6.0, 12.2.0
- `pulsar`: 4.0.6, 3.0.2, 2.11.2
- `qdrant`: 1.15.4, 1.13.4, 1.10.0, 1.8.4, 1.8.1, 1.7.3, 1.5.0

## Send-Message Job Coverage

| send-message job | Test jobs needed | Condition filter |
|------------------|------------------|------------------|
| `send-message` | 42 jobs (Wave 4) | `inputs.TEST_TYPE == ''` or matches any Wave 4 engine |
| `send-message-redis` | 13 jobs (redis + redis-cluster) | `inputs.TEST_TYPE == ''` or contains `redis` |
| `send-message-mongodb` | 10 jobs (mongodb + mongodb-shard) | `inputs.TEST_TYPE == ''` or contains `mongodb`/`mongodb-shard` |
| `send-message-zookeeper-rabbitmq` | 14 jobs (zookeeper + rabbitmq) | `inputs.TEST_TYPE == ''` or contains `rabbitmq`/`zookeeper` |

## Version Naming Conventions

- Job IDs: dots → hyphens. `3.3.6` → `test-tdengine-3-3-6`.
- `test-type-name`: keep dots. `tdengine-3.3.6`.
- `--service-version`: keep original version string. `3.3.6` or `v2.3`.
- For year-based versions (minio): `2025` in job ID, `2025` in service-version.
- Major-only abbreviations: `elasticsearch-8` uses `--service-version 8`, not the full patch version. This is a workflow convention because kbcli-test resolves the latest patch internally.
