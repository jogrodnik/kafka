# Technical Design: 2+2+1 KRaft Controller Quorum
## DC1 Hong Kong + DC2 Hong Kong + GKE asia-east2

**Status:** Revised technical design  
**Scope:** Confluent Platform 8.3.x / Apache Kafka 4.3.x KRaft control plane  
**Deployment model:** Custom container image + Helm/StatefulSet; no Confluent for Kubernetes (CFK)  
**GKE role:** One controller-only KRaft voter; no Kafka broker and no Kafka data plane

---

## 1. Purpose and Design Goal

The target is a five-voter KRaft controller quorum distributed across three independent infrastructure locations:

| Site | Role | KRaft voters | Kafka brokers |
|---|---|---:|---|
| DC1 Hong Kong | Full Kafka site | 2 | Yes |
| DC2 Hong Kong | Full Kafka site | 2 | Yes |
| GKE `asia-east2` Hong Kong | Controller-only site ("0.5 DC") | 1 | No |

Total KRaft voters: **5**.  
Required majority: **3**.

The purpose of the GKE site is only to preserve the KRaft majority after complete loss of either DC1 or DC2.

This document covers the **Kafka/KRaft control plane only**. Broker topic-replication design, RF, `min.insync.replicas`, ISR/ELR, producer acknowledgements, and application DR are separate data-plane topics.

---

## 2. Quorum Topology

Recommended controller identities:

```text
DC1:
  C101
  C102

DC2:
  C201
  C202

GKE asia-east2:
  C301
```

Logical quorum:

```text
                5-voter KRaft quorum

          DC1                     DC2
      +-----------+           +-----------+
      | C101      |           | C201      |
      | C102      |           | C202      |
      +-----+-----+           +-----+-----+
            \                       /
             \                     /
              \                   /
               +------ C301 ------+
                   GKE asia-east2
```

Quorum majority:

```text
N = 5
majority = floor(N / 2) + 1 = 3
```

The fifth GKE node is a **normal KRaft voter**, not a special witness protocol role. It stores and replicates the KRaft metadata log and participates in elections.

---

## 3. Failure Behaviour

| Failure | Controllers remaining | Result |
|---|---:|---|
| No failure | 5/5 | Quorum available |
| One controller fails | 4/5 | Quorum available |
| GKE/C301 fails | 4/5 | Quorum available |
| Entire DC1 fails | C201 + C202 + C301 = 3/5 | Quorum available |
| Entire DC2 fails | C101 + C102 + C301 = 3/5 | Quorum available |
| DC1 + GKE fail | 2/5 | Quorum lost |
| DC2 + GKE fail | 2/5 | Quorum lost |
| Any 3 voters are mutually connected | 3/5 | Quorum can operate |
| Network partition leaves only 2 mutually connected voters | 2/5 | No leader can be elected |

The key improvement over the earlier 3+2 two-DC design is:

```text
old:
DC1 = 3
DC2 = 2

loss DC1 -> 2/5 -> quorum lost

new:
DC1 = 2
DC2 = 2
GKE = 1

loss DC1 -> 3/5 -> quorum survives
loss DC2 -> 3/5 -> quorum survives
```

Normal single-site failure therefore must **not** require `force-standalone` or manual quorum reconstruction.

---

## 4. Kafka / KRaft Version Model

Target platform:

```text
Confluent Platform 8.3.x
Apache Kafka 4.3.x
Java 21 recommended by Confluent for CP 8.3.x
```

For Confluent Platform 8.3.x, use the dynamic KRaft quorum model.

Required feature:

```text
kraft.version = 1
```

Verify:

```bash
kafka-features.sh \
  --bootstrap-controller c101.kafka.internal:9093 \
  describe
```

Expected:

```text
Feature: kraft.version
FinalizedVersionLevel: 1
```

For a dynamic controller quorum:

```properties
controller.quorum.bootstrap.servers=c101.kafka.internal:9093,c102.kafka.internal:9093,c201.kafka.internal:9093,c202.kafka.internal:9093,c301.kafka.internal:9093
```

Do **not** configure:

```properties
controller.quorum.voters=...
```

after the cluster has been converted/formatted for dynamic quorum.

`controller.quorum.bootstrap.servers` is a discovery seed list. It does not define the authoritative current voter membership; membership is stored in the KRaft metadata state.

---

## 5. Network Architecture

### 5.1 Required reachability

Every controller must be able to establish TCP connectivity to every other controller endpoint.

Required logical mesh:

```text
C101 <-> C102
C101 <-> C201
C101 <-> C202
C101 <-> C301

C102 <-> C201
C102 <-> C202
C102 <-> C301

C201 <-> C202
C201 <-> C301

C202 <-> C301
```

Broker nodes in DC1 and DC2 must also be able to reach sufficient controller bootstrap endpoints.

The controller listener port is a deployment choice. Example used in this design:

```text
TCP 9093
```

There is no Kafka requirement that the port be `9074`; use the same explicit controller listener port consistently in Helm, firewall policy, DNS and TLS configuration.

### 5.2 Private routing

Required design:

```text
DC1 <------ private routed network ------> DC2
 |                                      |
 |                                      |
 +------- private connectivity ---------+
                 to GCP
                  |
             Cloud Router
                  |
              GKE VPC
                  |
                C301
```

Production traffic between the on-premises DCs and GKE should use dedicated/private hybrid connectivity such as Cloud Interconnect or an equivalent private WAN path.

Avoid putting KRaft controller communication over the public Internet.

BGP and route propagation must provide bidirectional reachability between:

```text
DC1 controller subnet
DC2 controller subnet
GKE node / service endpoint subnet used by C301
```

Avoid overlapping CIDRs across the three environments.

---

## 6. Latency, Jitter and Packet Loss

Confluent's multi-region guidance treats stable, low-latency connectivity as a prerequisite and identifies approximately 100 ms as a practical upper boundary for stretched-cluster designs.

For this Hong Kong / Hong Kong / GCP Hong Kong architecture, the engineering target should be much tighter:

| Path | Recommended engineering target |
|---|---:|
| DC1 ↔ DC2 RTT average | < 10 ms |
| DC1 ↔ C301 RTT average | < 10–15 ms |
| DC2 ↔ C301 RTT average | < 10–15 ms |
| p95 | < 20 ms |
| p99 | < 25–30 ms |
| Packet loss under normal operation | effectively 0%; target < 0.01% |
| Sustained packet loss | unacceptable |
| Long latency spikes / route flapping | unacceptable |

These are **design targets**, not Kafka protocol hard limits.

For KRaft, stable tail latency is more important than a low average with large spikes.

---

## 7. Bandwidth

C301 carries no Kafka topic partitions.

Traffic to the GKE site consists primarily of:

```text
KRaft heartbeats
Raft fetch/replication
__cluster_metadata-0 records
metadata snapshots / controller catch-up
administrative controller traffic
TLS overhead
monitoring
```

Therefore bandwidth requirements for the GKE leg are normally low compared with broker replication.

DC1 ↔ DC2 is different because that path may also carry broker replica traffic and must be sized independently from the KRaft control-plane requirement.

---

## 8. GKE Controller Design

### 8.1 Location

Use:

```text
GCP region: asia-east2
Location: Hong Kong
```

### 8.2 Workload

Run exactly one Kafka process with:

```properties
process.roles=controller
node.id=301
```

Do not run on C301:

```text
broker role
Kafka topic replicas
Schema Registry
Kafka Connect
ksqlDB
Control Center
application workloads
```

### 8.3 Kubernetes deployment

Use a StatefulSet managed by the existing custom Helm deployment model.

Example:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kraft-controller-gke
spec:
  replicas: 1
  serviceName: kraft-controller-gke
  selector:
    matchLabels:
      app: kraft-controller-gke
  template:
    metadata:
      labels:
        app: kraft-controller-gke
    spec:
      terminationGracePeriodSeconds: 120
      containers:
        - name: controller
          image: <approved-confluent-8.3.x-image>
          volumeMounts:
            - name: metadata
              mountPath: /var/lib/kafka/metadata
  volumeClaimTemplates:
    - metadata:
        name: metadata
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: premium-rwo
        resources:
          requests:
            storage: 20Gi
```

The exact disk size must be selected from observed metadata growth and retention requirements.

### 8.4 Compute and availability

C301 does not need broker-scale compute.

Use non-Spot compute. Do not place the only third-site voter on Spot/Preemptible nodes.

Prefer a regional GKE control plane with non-Spot capacity available in more than one zone. C301 remains one Kafka voter; Kubernetes HA is only used to restart that voter after infrastructure failure.

Do not run two simultaneous C301 replicas with the same `node.id` and metadata directory.

---

## 9. Persistent Metadata Storage

C301 must use persistent block storage for the KRaft metadata directory.

Recommended GKE CSI class:

```text
premium-rwo
```

which uses SSD Persistent Disk.

A zonal Persistent Disk survives Pod and node restart but remains tied to its zone. If recovery after a zone failure is required, evaluate Regional Persistent Disk or an equivalent multi-zone persistence design.

Required properties:

```text
PVC survives Pod recreation
PVC is not automatically deleted during normal StatefulSet operations
single writer only
filesystem ownership remains stable
metadata directory is not reformatted on every Pod start
```

The startup script must distinguish an empty metadata volume from an already-formatted KRaft metadata volume.

Never run unconditional `kafka-storage.sh format` on Pod startup.

---

## 10. Stable Network Identity and DNS

Do not use an ephemeral Pod IP as the long-term identity of C301.

Define a stable private DNS endpoint, for example:

```text
c301.kafka.internal
```

All controllers and brokers must resolve the controller names consistently:

```text
c101.kafka.internal
c102.kafka.internal
c201.kafka.internal
c202.kafka.internal
c301.kafka.internal
```

The GKE endpoint must remain private and reachable through the routed hybrid network.

Preserve one-to-one identity:

```text
c301.kafka.internal -> C301 only
```

Do not use a single virtual address that load-balances Raft peer connections across different controller IDs.

---

## 11. TLS and Firewalling

Controller-to-controller communication should use TLS.

Example:

```properties
process.roles=controller
node.id=301
controller.listener.names=CONTROLLER
listeners=CONTROLLER://0.0.0.0:9093
listener.security.protocol.map=CONTROLLER:SSL
```

The certificate presented by C301 must match the stable endpoint, for example:

```text
SAN: DNS:c301.kafka.internal
```

The same CA trust model must be available in DC1, DC2 and GKE.

Firewall rules should allow only required controller and broker source networks to the controller listener.

Do not expose the controller listener publicly.

---

## 12. MTU and TCP Path Validation

Verify path MTU end-to-end from real controller hosts/pods.

Test all paths:

```text
DC1 -> DC2
DC1 -> C301
DC2 -> C301
C301 -> DC1
C301 -> DC2
```

Avoid fragmentation and PMTU black holes.

Validate TCP reachability against the real controller listener and test long-lived connections, not only ICMP ping.

---

## 13. C301 Controller Configuration

Example controller-only configuration:

```properties
process.roles=controller
node.id=301

controller.listener.names=CONTROLLER
listeners=CONTROLLER://0.0.0.0:9093
listener.security.protocol.map=CONTROLLER:SSL

controller.quorum.bootstrap.servers=c101.kafka.internal:9093,c102.kafka.internal:9093,c201.kafka.internal:9093,c202.kafka.internal:9093,c301.kafka.internal:9093

metadata.log.dir=/var/lib/kafka/metadata
```

Important:

```text
controller.quorum.bootstrap.servers != voter membership
```

The current voter set is maintained by KRaft metadata.

---

## 14. Adding C301 to an Existing Dynamic Quorum

For an existing healthy dynamic quorum, add C301 using the normal dynamic membership procedure.

### 14.1 Format new C301 storage

Use the existing Kafka cluster ID:

```bash
kafka-storage.sh format \
  --cluster-id <EXISTING_CLUSTER_ID> \
  --no-initial-controllers \
  --config /etc/kafka/controller.properties
```

Do not use `--standalone` when adding C301 to an existing quorum.

### 14.2 Start C301

Start C301 and allow it to catch up with the current metadata log.

### 14.3 Verify replication

```bash
kafka-metadata-quorum.sh \
  --bootstrap-controller c101.kafka.internal:9093 \
  describe --replication
```

Verify that C301 is caught up before voter promotion.

### 14.4 Add C301 to the voter set

Use Kafka 4.3 `add-controller` against the healthy quorum, with the command executed using the configuration/identity of the controller being added.

Example:

```bash
kafka-metadata-quorum.sh \
  --command-config /etc/kafka/admin.properties \
  --bootstrap-controller c101.kafka.internal:9093 \
  add-controller
```

### 14.5 Validate

```bash
kafka-metadata-quorum.sh \
  --bootstrap-controller c101.kafka.internal:9093 \
  describe --status
```

Target state:

```text
5 voters
1 leader
4 followers
healthy High Watermark progression
no persistent controller replication lag
```

---

## 15. Monitoring Requirements

Monitor:

```text
KRaft leader
voter membership
controller epoch
High Watermark
Log End Offset
controller follower lag
last fetch timestamp
last caught-up timestamp
leader-election frequency
controller restart count
JVM CPU / GC / memory
metadata disk latency and free space
TCP retransmissions
packet loss
DC1-GKE RTT
DC2-GKE RTT
hybrid routing/BGP status
DNS resolution
TLS certificate expiry
```

Alert on:

```text
C301 unavailable
C301 persistently lagging
one full DC unavailable
only 3 healthy voters remaining
frequent elections
hybrid link flapping
```

A 3/5 state is functional but has no additional voter-loss tolerance and should be treated as a high-severity degraded condition.

---

## 16. Pre-Production Acceptance Tests

| Test | Expected result |
|---|---|
| `kraft.version` | `FinalizedVersionLevel=1` |
| Normal voter count | 5 voters |
| Stop C301 | quorum remains 4/5 |
| Complete loss of DC1 | DC2 + C301 = 3/5; quorum remains available |
| Complete loss of DC2 | DC1 + C301 = 3/5; quorum remains available |
| Break DC1↔GKE only | no unexpected quorum loss |
| Break DC2↔GKE only | no unexpected quorum loss |
| Restart C301 Pod | same metadata PVC reused, no reformat |
| Kill node hosting C301 | controller recovers according to GKE/storage design |
| DNS validation | all five controller names resolve correctly |
| TLS validation | mutual connectivity and hostname verification succeed |
| RTT/p95/p99 | inside agreed engineering limits |
| Packet loss | effectively zero under normal conditions |
| PMTU | no fragmentation/black-hole issue |
| Hybrid path failover | routing converges without prolonged KRaft instability |

The mandatory DR tests are complete loss of DC1, complete loss of DC2 and independent loss of C301.

During every test observe leader election, High Watermark, metadata replication lag and time to stable quorum.

---

## 17. Technical Risks

### Common-mode network failure

The GKE voter improves quorum resilience only if the path to GKE is sufficiently independent from the infrastructure whose failure can remove DC1 or DC2.

A shared router, firewall, WAN edge, carrier or route reflector can become the real common-mode failure.

### GKE zone dependency

A single C301 Pod using a zonal disk can be temporarily unavailable after a zone-level failure. If this overlaps with complete loss of one DC, quorum can fall from 3/5 to 2/5.

### DNS dependency

DNS needed for controller endpoints must remain available during DR.

### Storage formatting risk

Accidental formatting of an existing metadata directory destroys the local KRaft metadata copy and identity.

### Version consistency

Keep controller binaries on the same approved Confluent Platform/Kafka patch level unless Confluent explicitly confirms a mixed build is supported.

---

## 18. Final Technical Recommendation

Use:

```text
DC1 HK
  C101
  C102

DC2 HK
  C201
  C202

GKE asia-east2 HK
  C301
  controller only
```

with:

```text
5 dynamic KRaft voters
majority = 3
kraft.version = 1
Confluent Platform 8.3.x / Apache Kafka 4.3.x
private routed connectivity
stable private DNS
TLS controller listener
persistent metadata storage
non-Spot GKE compute
custom Helm + StatefulSet
no CFK
```

The architecture is technically strong because complete loss of either DC1 or DC2 leaves a legal KRaft majority without `force-standalone` or manual quorum reconstruction.

Production approval should depend on measured DC1↔DC2↔GKE latency, p99 jitter, packet loss, MTU, hybrid-routing failover, DNS, TLS and full-site-loss tests.

---

## Official References

1. Confluent Platform 8.3 Release Notes  
   https://docs.confluent.io/platform/current/release-notes/

2. Confluent Platform Supported Versions and Interoperability  
   https://docs.confluent.io/platform/current/installation/versions-interoperability.html

3. Confluent — Configure and Monitor KRaft  
   https://docs.confluent.io/platform/current/kafka-metadata/config-kraft.html

4. Apache Kafka — KRaft  
   https://kafka.apache.org/42/operations/kraft/

5. Google Cloud — GKE Storage Overview  
   https://cloud.google.com/kubernetes-engine/docs/concepts/storage-overview

6. Google Cloud — Persistent Disk CSI Driver for GKE  
   https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/gce-pd-csi-driver

7. Google Cloud — Cloud Interconnect  
   https://cloud.google.com/network-connectivity/docs/interconnect
