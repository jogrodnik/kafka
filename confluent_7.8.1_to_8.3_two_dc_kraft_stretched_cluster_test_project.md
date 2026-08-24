# Confluent Platform 7.8.1 → 8.3 Two-Data-Center KRaft Stretched Cluster Test Project

**Document type:** Architecture and validation test plan  
**Status:** Draft for laboratory / pre-production testing  
**Validated against Confluent documentation:** 2026-08-20  
**Scope:** Confluent Platform 7.8.1 to 8.3.x, KRaft, two physical data centers, stretched Kafka cluster  
**Current topology:** 3 brokers + 3 dedicated KRaft controllers per data center  
**Proposed constrained topology:** 3 brokers per data center; 3 KRaft voters in preferred DC1 and 2 KRaft voters in DC2

---

## 1. Executive Summary

The current cluster is a single stretched Confluent Platform cluster deployed across two data centers:

```text
DC1                                      DC2
----------------------------------       ----------------------------------
3 Kafka brokers                          3 Kafka brokers
3 dedicated KRaft controllers            3 dedicated KRaft controllers

Total brokers:      6
Total controllers:  6
KRaft voters:       6
Required quorum:    4
```

A `3 + 3` controller layout is symmetric, but it does **not** survive the complete loss of either data center at the KRaft metadata-quorum level.

With six voters:

```text
quorum = floor(6 / 2) + 1 = 4
```

After loss of either DC, only three controllers remain:

```text
3 remaining voters < 4 required voters
=> KRaft quorum is lost
```

Because a third data center or witness site is not available, this project proposes testing a deliberately **asymmetric, preferred-data-center architecture**:

```text
DC1 - PRIMARY / PREFERRED                 DC2 - SECONDARY
----------------------------------        ----------------------------------
3 Kafka brokers                           3 Kafka brokers
3 KRaft controllers                       2 KRaft controllers

Total KRaft voters: 5
Required quorum:    3
```

This produces deterministic behavior during a site failure or inter-DC network partition:

- Loss of **DC2**: DC1 retains `3/5` voters and the metadata quorum remains available.
- Loss of **DC1**: DC2 retains `2/5` voters and the metadata quorum is unavailable.
- Network partition between DC1 and DC2: DC1 has quorum (`3/5`), DC2 does not (`2/5`), avoiding two independently active metadata quorums.

This is **not symmetric two-site HA**. It is a constrained two-DC design with an explicitly preferred DC. The test must therefore validate both the automatic survival case (loss of DC2) and the disaster-recovery case (loss of DC1).

Confluent documentation recommends three or more data centers for stretched-cluster HA. Confluent Platform 7.8 documentation nevertheless explicitly describes a two-DC deployment as possible when one DC is preferred, using an example such as three KRaft nodes in one DC and two in the other, or when manual quorum reconfiguration is accepted.

---

## 2. Objectives

The project has the following objectives:

1. Validate the existing Confluent Platform 7.8.1 KRaft cluster before any topology change.
2. Validate client compatibility before moving from Kafka 3.8-era protocol support to Confluent Platform 8.3 / Kafka 4.3.
3. Perform a controlled rolling upgrade from Confluent Platform 7.8.1 to 8.3.x.
4. Preserve the existing broker placement of three brokers in each DC.
5. Migrate the KRaft controller configuration to a dynamic quorum on Confluent Platform 8.3.
6. Reduce controller voters from `3 + 3` to `3 + 2`.
7. Designate DC1 as the preferred site.
8. Validate broker, partition, producer, consumer, controller, and metadata behavior under controlled failures.
9. Measure RPO, RTO, latency, ISR behavior, and operational recovery.
10. Produce evidence sufficient to decide whether this two-DC design is acceptable for production.

---

## 3. Non-Goals

This project does not claim to provide:

- symmetric site-level HA;
- automatic survival of the preferred DC1 being completely lost;
- the same resilience as Confluent's recommended three-DC or 2.5-DC architecture;
- a substitute for a third KRaft voting location;
- a production rollout procedure without environment-specific validation;
- automatic zero-RTO disaster recovery after loss of DC1.

A separate DR procedure is required for complete loss of DC1.

---

## 4. Current Architecture

### 4.1 Logical topology

```text
                              ONE KAFKA CLUSTER
              =================================================

              DC1                                  DC2
      ----------------------               ----------------------
      Broker B1                             Broker B4
      Broker B2                             Broker B5
      Broker B3                             Broker B6

      Controller C1                         Controller C4
      Controller C2                         Controller C5
      Controller C3                         Controller C6

                  <------ inter-DC network ------->
```

### 4.2 Current KRaft quorum

Assumption to verify during baseline testing:

```text
CurrentVoters:
C1, C2, C3, C4, C5, C6
```

For six voters:

```text
majority = 4
```

Failure tolerance of a six-member Raft quorum:

```text
maximum simultaneous voter failures while retaining quorum = 2
```

A complete DC failure removes three voters and therefore exceeds this limit.

---

## 5. Proposed Test Architecture

### 5.1 Recommended constrained two-DC layout

```text
                        KRaft Dynamic Quorum
                     5 voters, majority = 3

             DC1 - PREFERRED                 DC2 - SECONDARY
        --------------------------       --------------------------
        Controller C1   VOTER             Controller C4   VOTER
        Controller C2   VOTER             Controller C5   VOTER
        Controller C3   VOTER

        Broker B1                         Broker B4
        Broker B2                         Broker B5
        Broker B3                         Broker B6
```

The sixth controller host in DC2 may be:

- decommissioned as a Kafka controller;
- retained as unused warm infrastructure;
- repurposed;
- retained for future DR operations but **not** kept as a voter in the normal five-voter quorum.

Do not assume that merely running a sixth controller process provides useful HA. The key property is **voter membership**, not the number of controller machines that exist.

### 5.2 Why five voters instead of six

For five voters:

```text
quorum = floor(5 / 2) + 1 = 3
```

With placement `3 + 2`:

| Event | DC1 voters | DC2 voters | Available | Required | Result |
|---|---:|---:|---:|---:|---|
| Normal | 3 | 2 | 5 | 3 | PASS |
| One controller failure | 2-3 | 1-2 | 4 | 3 | PASS |
| Two controller failures | varies | varies | 3 | 3 | PASS if three voters remain mutually reachable |
| Complete DC2 loss | 3 | 0 | 3 | 3 | PASS |
| Complete DC1 loss | 0 | 2 | 2 | 3 | FAIL / DR required |
| DC1↔DC2 partition | 3 | 2 | DC1=3, DC2=2 | 3 | DC1 wins |

### 5.3 Why not `3 + 3`

With `3 + 3`:

```text
total voters = 6
majority = 4
```

A network split produces:

```text
DC1: 3/6 -> no quorum
DC2: 3/6 -> no quorum
```

A complete loss of either DC produces the same result.

Adding the sixth voter therefore increases the majority threshold from three to four but does not leave four voters in either data center.

### 5.4 Why not `4 + 2`

A `4 + 2` arrangement would also make DC1 preferred, but it is normally less attractive than `3 + 2`:

- six total voters still require four for quorum;
- it requires one additional voting controller without improving tolerance to loss of the preferred site;
- DC1 must retain four voters rather than three during some failure combinations;
- odd voter counts are generally preferable for efficient Raft fault tolerance.

The `3 + 2` design is the simplest five-voter quorum that intentionally assigns the majority to DC1.

---

## 6. Important Architectural Constraint

Current Confluent documentation recommends stretched clusters when three fully operational data centers, or a 2.5-DC design with a third controller location, are available and connected by a stable low-latency network.

This project cannot satisfy that recommendation because only two DCs are available.

The proposed `3 + 2` layout must therefore be treated as a **known compromise**:

```text
Availability preference:
DC1 > DC2
```

The business must explicitly approve this failure-domain asymmetry.

---

## 7. Version Comparison Relevant to This Test

| Area | Confluent Platform 7.8.1 | Confluent Platform 8.3.x |
|---|---|---|
| Kafka metadata level | 3.8-IV0 family | 4.3-IV0 |
| KRaft | Supported | Required |
| Static controller quorum | Supported | Supported for upgraded clusters |
| Dynamic KRaft quorum | Not the baseline mode for 7.8 cluster | Supported; recommended operational model |
| `kraft.version` dynamic capability | Static-era baseline | `kraft.version=1` enables dynamic controller quorum |
| Controller discovery | `controller.quorum.voters` | `controller.quorum.bootstrap.servers` for dynamic quorum |
| Add/remove controller online | Static configuration is operationally restrictive | Supported with dynamic quorum |
| Java recommendation | Java 17 | Java 21 |
| Broker/controller Java support | 8/11/17 depending on platform/environment | 17/21/25 for CP 8.3 server-side runtime; Java 21 recommended |
| Very old Kafka client protocol APIs | Supported more broadly | APIs older than Kafka 2.1 removed |
| Release metadata | Kafka 3.8 | Kafka 4.3 |

The project should use the **latest available 8.3.x patch**, not assume that `8.3.0` is the desired production target.

---

## 8. Upgrade Strategy

### 8.1 Design principle

Do not combine all major changes into one uncontrolled event.

Use separate checkpoints:

```text
Phase 0  Baseline current 7.8.1
    |
Phase 1  Client and platform readiness
    |
Phase 2  Rolling software upgrade to 8.3.x
    |
Phase 3  Stabilization on 8.3.x
    |
Phase 4  Upgrade KRaft feature capability / dynamic quorum
    |
Phase 5  Change controller voters from 3+3 to 3+2
    |
Phase 6  Failure testing
    |
Phase 7  Production decision
```

### 8.2 Important upgrade-order correction

For the Confluent Platform 8.3 upgrade path, current Confluent documentation specifies that after required Control Center preparation, Kafka nodes are upgraded **broker by broker and then controller by controller**, one node at a time for a rolling upgrade.

Always follow the exact documentation for the target 8.3.x patch being tested.

---

## 9. Phase 0 — Capture the 7.8.1 Baseline

### 9.1 Record software versions

Capture:

```bash
kafka-broker-api-versions.sh --bootstrap-server <broker>:<port>
```

Record:

- Confluent Platform package version;
- Kafka version;
- Java version;
- OS version;
- kernel version;
- filesystem;
- disk layout;
- broker IDs / node IDs;
- controller IDs;
- controller listener endpoints.

### 9.2 Record current metadata quorum

Run:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <controller-host>:<controller-port> \
  describe --status
```

Also:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <controller-host>:<controller-port> \
  describe --replication
```

Capture at minimum:

- `ClusterId`;
- `LeaderId`;
- `LeaderEpoch`;
- `HighWatermark`;
- `MaxFollowerLag`;
- `MaxFollowerLagTimeMs`;
- `CurrentVoters`;
- `CurrentObservers`.

**Expected baseline:** six controller voters, unless the real environment differs.

If the environment differs, stop using the assumptions in this document and update the test design from the observed state.

### 9.3 Capture KRaft configuration

For every controller and broker, archive:

```text
process.roles
node.id
controller.listener.names
listeners
listener.security.protocol.map
inter.broker.listener.name
controller.quorum.voters
controller.quorum.bootstrap.servers
metadata.log.dir
log.dirs
```

### 9.4 Capture MRC and rack configuration

Record:

```text
broker.rack
replica.selector.class
confluent.* observer / replica placement settings
default.replication.factor
min.insync.replicas
unclean.leader.election.enable
```

Export topic-level overrides separately.

### 9.5 Capture topic placement

For every critical topic:

- partition count;
- replication factor;
- replica location;
- leader location;
- ISR;
- observer placement if used;
- `min.insync.replicas`.

Validate that broker rack labels accurately represent DC placement.

---

## 10. Phase 1 — Client Compatibility Gate

Confluent Platform 8.0+ removes support for protocol APIs older than Kafka 2.1.

Before upgrading brokers to 8.3:

1. Inventory all producers.
2. Inventory all consumers.
3. Inventory Kafka Streams applications.
4. Inventory Kafka Connect workers and connectors.
5. Inventory Schema Registry clients.
6. Inventory custom administrative tools.
7. Inventory monitoring products that use Kafka APIs.
8. Inventory third-party appliances and integration middleware.

On the supported 7.7–7.9 pre-8.x platform family, use the `DeprecatedRequestsPerSec` metric to find old protocol use.

Because the current cluster is already 7.8.1, the compatibility scan can be performed before the 8.3 upgrade. Confluent states that 7.9 is strongly recommended for this preparation, although KRaft clusters at 7.7.1 and later have an 8.3 upgrade path.

### Acceptance criterion

Proceed only when:

```text
Deprecated protocol requests older than Kafka 2.1 = 0
```

for a representative observation period covering all normal workloads and scheduled jobs.

---

## 11. Phase 2 — Java Readiness

Confluent Platform 8.3 recommends Java 21.

For the test environment:

```text
Preferred JDK: Java 21 LTS
```

Validate:

```bash
java -version
```

Also validate:

- service unit `JAVA_HOME`;
- container base images, if applicable;
- truststores and keystores;
- JMX agents;
- APM agents;
- security agents;
- custom JVM parameters;
- connector compatibility.

Do not treat Java 25 support in CP 8.3 Docker images as a reason to use Java 25 for Kafka Connect; current Confluent documentation states connectors are not certified on Java 25 and recommends Java 21 for connectors.

---

## 12. Phase 3 — Pre-Upgrade Health Gate

The cluster must be healthy before rolling upgrade.

Minimum checks:

```text
KRaft leader exists                        PASS
All expected controller voters visible     PASS
Controller replication lag acceptable      PASS
Under-replicated partitions = 0            PASS
Offline partitions = 0                     PASS
No unexpected ISR shrink events            PASS
Broker disks healthy                       PASS
Inter-DC latency within expected range      PASS
Inter-DC packet loss acceptable             PASS
Critical consumers healthy                 PASS
Producer error rate normal                  PASS
No deprecated client API traffic            PASS
```

Record a 30–60 minute baseline of:

- produce request latency;
- fetch request latency;
- inter-broker replication traffic;
- controller request latency;
- ISR shrink/expand rates;
- active controller count;
- under-replicated partitions;
- offline partitions;
- bytes in/out per broker;
- CPU;
- heap;
- GC;
- disk utilization;
- network retransmits;
- inter-DC RTT and p99.

---

## 13. Phase 4 — Rolling Upgrade to Confluent Platform 8.3.x

Follow the target patch's official upgrade documentation.

High-level order from current Confluent 8.3 documentation:

1. Validate all clients.
2. Upgrade Control Center to a compatible version if Control Center is used.
3. Upgrade Kafka brokers one at a time.
4. Upgrade KRaft controllers one at a time.
5. Upgrade other Confluent Platform components.
6. Upgrade clients/applications where required.
7. Only later upgrade the Kafka release/metadata feature level when ready.

### 13.1 Per-broker cycle

For each broker:

```text
A. Verify cluster healthy
B. Verify no offline partitions
C. Stop exactly one broker
D. Upgrade package/image/configuration
E. Start broker
F. Wait for broker registration
G. Wait for replicas to catch up
H. Verify ISR recovery
I. Verify no unexpected leader/partition problems
J. Proceed to next broker only after PASS
```

Recommended test order may alternate DCs to avoid repeatedly concentrating risk in one location, subject to the exact operational procedure.

Example:

```text
B1 DC1
B4 DC2
B2 DC1
B5 DC2
B3 DC1
B6 DC2
```

Do not use this order blindly if replica placement or workload topology makes another sequence safer.

### 13.2 Per-controller cycle

After broker upgrade completion, upgrade one controller at a time.

Before each restart:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <healthy-controller>:<port> \
  describe --status
```

Do not proceed if quorum health is uncertain.

Cycle:

```text
A. Confirm >= required number of healthy voters
B. Record current KRaft leader
C. Stop one controller
D. Upgrade controller
E. Start controller
F. Verify it rejoins
G. Verify metadata log catches up
H. Verify a leader exists
I. Verify MaxFollowerLag
J. Continue only after PASS
```

During this phase the six-voter topology remains unchanged.

---

## 14. Phase 5 — Post-Upgrade Stabilization Before Feature Changes

Do **not** immediately change the controller topology.

Run the cluster on 8.3.x with the original topology long enough to validate:

- broker stability;
- controller stability;
- client compatibility;
- Kafka Connect;
- Kafka Streams;
- Schema Registry;
- Control Center;
- monitoring;
- backup procedures;
- normal maintenance;
- normal load.

Run the same metrics comparison used for the 7.8.1 baseline.

### Acceptance criterion

No material regression unexplained by expected version/default changes.

---

## 15. Phase 6 — Upgrade Kafka Release / Metadata Features

Confluent Platform 8.3 supports Kafka metadata version `4.3-IV0`.

Current documentation provides an upgrade mechanism such as:

```bash
bin/kafka-features.sh \
  --bootstrap-server <broker>:<port> \
  upgrade --release-version 4.3
```

**Important:** feature-level upgrades can constrain downgrade options. Perform this only after the software rollout is stable and after reviewing the downgrade implications for the exact target patch.

Capture feature state before and after:

```bash
bin/kafka-features.sh \
  --bootstrap-controller <controller>:<port> \
  describe
```

---

## 16. Phase 7 — Static to Dynamic KRaft Quorum

### 16.1 Why dynamic quorum is useful here

The existing six-controller 7.8.1 design is expected to use a static voter list via:

```properties
controller.quorum.voters=...
```

Dynamic KRaft quorum provides the ability to change controller membership while the cluster is running and is therefore especially useful when reducing the voter set from six to five.

For dynamic controller capability, verify:

```bash
bin/kafka-features.sh \
  --bootstrap-controller <controller>:<port> \
  describe
```

Expected dynamic state:

```text
kraft.version FinalizedVersionLevel: 1
```

### 16.2 Configuration model

Static:

```properties
controller.quorum.voters=...
```

Dynamic:

```properties
controller.quorum.bootstrap.servers=<controller1>:9093,<controller2>:9093,...
```

For dynamic controllers:

- remove `controller.quorum.voters`;
- configure `controller.quorum.bootstrap.servers`;
- include enough reachable controller endpoints for robust discovery;
- perform the documented rolling configuration restart.

Current Confluent documentation for static-to-dynamic migration specifies updating controllers and brokers to the bootstrap-server configuration and rolling the nodes, then verifying `CurrentVoters`.

### 16.3 Verification

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <controller>:<port> \
  describe --status
```

Do not remove any controller voter until:

```text
Dynamic quorum verified        PASS
All six current voters healthy PASS
Metadata log caught up         PASS
Cluster workload healthy       PASS
```

---

## 17. Phase 8 — Change from `3 + 3` to `3 + 2`

### 17.1 Choose the controller to remove

Example:

```text
DC1 voters: C1, C2, C3
DC2 voters: C4, C5, C6

Target:
DC1 voters: C1, C2, C3
DC2 voters: C4, C5

Remove:
C6
```

Choose the node based on:

- hardware lifecycle;
- network placement;
- failure domain;
- rack/power distribution;
- operational accessibility;
- observed controller lag;
- maintenance strategy.

### 17.2 Obtain the controller ID and directory ID

Run:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <controller>:<port> \
  describe --status
```

Record:

```text
controller-id
controller-directory-id
```

for the DC2 controller selected for removal.

### 17.3 Remove the voter before shutting it down

On a dynamic quorum, current Confluent documentation supports:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <controller>:<port> \
  remove-controller \
  --controller-id <ID> \
  --controller-directory-id <DIRECTORY_ID>
```

If authentication/TLS client settings are required, use the environment's appropriate command configuration.

### 17.4 Verify the new voter set

Immediately check:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <controller>:<port> \
  describe --status
```

Expected:

```text
CurrentVoters = 5 controllers
DC1 voters = 3
DC2 voters = 2
```

Also verify:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <controller>:<port> \
  describe --replication
```

### 17.5 Acceptance criteria

```text
Total current voters = 5              PASS
DC1 voters = 3                        PASS
DC2 voters = 2                        PASS
KRaft leader exists                   PASS
Metadata high watermark advances      PASS
Controller lag acceptable             PASS
No offline partitions                 PASS
No unexplained ISR degradation        PASS
Produce/consume healthy               PASS
```

---

## 18. Data-Plane Design for the Test

Controller quorum availability alone does not guarantee that writes remain available after a DC failure.

The test must separately define topic replication.

### 18.1 Example strict RPO=0-style placement

For illustration only:

```text
Replication factor = 6

DC1:
  3 replicas

DC2:
  3 replicas
```

Example producer:

```properties
acks=all
```

Example topic:

```properties
min.insync.replicas=4
```

This design forces acknowledgements to depend on replication crossing DC boundaries under normal conditions because no single DC contains four replicas.

Consequences:

- higher write latency;
- stronger protection against acknowledged data existing only in one DC;
- after complete loss of one DC, only three replicas remain, so writes requiring `min.insync.replicas=4` stop.

That write stop is expected behavior and should not be confused with KRaft quorum failure.

### 18.2 MRC observer model

If Confluent MRC observers and automatic observer promotion are used, test them separately.

Record the real placement policy. Do not use sample observer configurations as production values without validating the existing MRC design.

### 18.3 Required distinction

Every failure test must distinguish:

```text
CONTROL PLANE
KRaft controller quorum

DATA PLANE
Partition leaders
ISR
Observers
min.insync.replicas
Producer acks
Consumers
```

A passing controller-quorum test does not automatically mean that a producer can write.

---

## 19. Failure Test Matrix

## Test T01 — Single Broker Failure in DC1

### Action

Stop B1.

### Expected control-plane result

```text
KRaft quorum unaffected
```

### Expected data-plane result

- partition leadership moves where necessary;
- ISR may temporarily shrink;
- no offline partition if replication is healthy;
- critical producers/consumers remain operational subject to topic configuration.

### Pass criteria

```text
Offline partitions = 0
KRaft leader exists
ISR recovers
Producer errors remain within expected transient limits
Consumer recovery within agreed threshold
```

---

## Test T02 — Single Controller Failure in DC1

Initial state:

```text
DC1 = 3 voters
DC2 = 2 voters
total = 5
```

Stop one DC1 controller:

```text
DC1 = 2
DC2 = 2
available = 4/5
```

### Expected

```text
quorum required = 3
available = 4
=> PASS
```

If the stopped controller is the active KRaft leader, a new leader should be elected.

### Validate

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <surviving-controller>:<port> \
  describe --status
```

---

## Test T03 — Two Controller Failures

Stop two controllers while ensuring three mutually reachable voters remain.

Example:

```text
DC1 = 2
DC2 = 1
total available = 3
```

### Expected

```text
3/5 = quorum
```

The cluster is at minimum quorum and has no additional voter-failure tolerance.

### Pass criteria

- KRaft leader remains/elects;
- metadata operations remain available;
- alerting identifies critical degraded state.

---

## Test T04 — Complete Loss of DC2

This is the principal advantage of the `3 + 2` design.

### Before

```text
DC1 = 3 voters
DC2 = 2 voters
```

### Failure

Disable all DC2 systems or network connectivity according to the controlled test method.

### After

```text
DC1 = 3 voters
DC2 = 0 reachable
```

### Expected KRaft result

```text
3/5 voters available
required = 3
=> KRaft quorum survives
```

### Control-plane expectations

- a KRaft leader exists in DC1;
- metadata high watermark continues advancing;
- broker registrations for surviving DC1 brokers remain valid;
- metadata operations remain possible.

### Data-plane expectations

Depend on replica placement and `min.insync.replicas`.

If RF=6 with 3 replicas per DC and `min.insync.replicas=4`:

```text
remaining ISR <= 3
required ISR = 4
=> new writes with acks=all should fail
```

Therefore record two results independently:

```text
KRaft availability: PASS
Write availability: may intentionally FAIL
Data durability policy: PASS if behavior matches design
```

This distinction is essential.

---

## Test T05 — Complete Loss of Preferred DC1

### Before

```text
DC1 = 3 voters
DC2 = 2 voters
```

### Failure

DC1 becomes unavailable.

### Remaining controllers

```text
DC2 = 2/5
```

### Expected KRaft result

```text
2 < 3
=> no KRaft quorum
```

This is an **expected failure by architecture**, not a test defect.

### Expected operational state

Existing brokers in DC2 may still contain Kafka log data. However, loss of metadata quorum prevents normal controller operations such as metadata changes and leader/ISR management that require the active controller.

Do not claim that the surviving DC2 is a fully operational cluster merely because broker processes are running.

### Pass criterion

The test passes if:

1. no split-brain metadata quorum forms;
2. monitoring detects loss of quorum;
3. the documented DC1-loss DR procedure is invoked;
4. no unsafe automatic action fabricates a second independent cluster from stale state;
5. recovery objectives are measured.

---

## Test T06 — Inter-DC Network Partition

Cut connectivity between DC1 and DC2 while hosts in both locations remain up.

Expected controller view:

```text
DC1:
3 of 5 voters mutually reachable
=> quorum

DC2:
2 of 5 voters mutually reachable
=> no quorum
```

### Expected result

DC1 remains the authoritative metadata side.

This is the deterministic behavior that the `3 + 2` design is intended to achieve.

### Critical additional validation

Kafka brokers and data replicas are also partitioned by the WAN failure.

Therefore inspect:

- ISR shrink;
- leader location;
- producer behavior;
- consumer behavior;
- observer promotion;
- follower fetching;
- replica lag;
- `min.insync.replicas`.

A working KRaft control plane does not guarantee available writes when synchronous replicas in DC2 are unreachable.

---

## Test T07 — Loss of WAN, Recovery of WAN

After T06:

1. restore connectivity;
2. verify controllers reconnect;
3. verify brokers reconnect;
4. verify metadata replication;
5. verify replica catch-up;
6. verify ISR expansion;
7. verify observers;
8. verify no duplicate or unexpected leader state;
9. verify workload latency returns to baseline.

### Pass criteria

```text
All five voters healthy
All six brokers registered
Offline partitions = 0
Expected ISR restored
Replication lag returns to normal
No data consistency errors detected
```

---

## Test T08 — Failure of DC2 While KRaft Leader Is in DC2

Before the failure, if possible, arrange or wait for a KRaft leader located in DC2.

Then lose DC2.

Expected:

```text
DC1 retains 3/5 voters
=> new KRaft leader can be elected in DC1
```

Measure:

- controller election duration;
- metadata-operation interruption;
- producer/consumer effects;
- monitoring detection time.

---

## Test T09 — Failure of One DC1 Controller Followed by Complete DC2 Loss

Initial:

```text
DC1 = 3
DC2 = 2
```

Fail one controller in DC1:

```text
DC1 = 2
DC2 = 2
=> 4/5, healthy
```

Then lose DC2:

```text
DC1 = 2
DC2 = 0
=> 2/5
=> no quorum
```

This demonstrates an important property:

**The 3+2 design tolerates complete DC2 loss only while all three preferred-site voters needed for the resulting majority remain available.**

The operational team must understand this correlated-failure exposure.

---

## Test T10 — DC2 Controller Maintenance

Because DC2 has two voters, taking one DC2 controller down leaves:

```text
DC1 = 3
DC2 = 1
=> 4/5
```

The cluster remains healthy.

Test routine maintenance and verify no unexpected metadata impact.

---

## 20. Producer Test Plan

For critical producers record:

```text
acks
enable.idempotence
delivery.timeout.ms
request.timeout.ms
retries
max.in.flight.requests.per.connection
bootstrap.servers
DNS/load-balancer failover behavior
```

During every failure test measure:

- successful records/sec;
- failed records/sec;
- retry rate;
- p50/p95/p99 send latency;
- timeout count;
- duplicate detection;
- sequence/idempotence errors.

### Required test cases

1. Producer started in DC1.
2. Producer started in DC2.
3. Leader partition in same DC as producer.
4. Leader partition in opposite DC.
5. DC2 loss.
6. DC1 loss.
7. WAN partition.
8. WAN restoration.

---

## 21. Consumer Test Plan

Record:

```text
group protocol
session.timeout.ms
heartbeat settings
max.poll.interval.ms
auto.offset.reset
isolation.level
rack-aware / follower-fetching configuration
```

Measure:

- rebalance duration;
- records/sec;
- consumer lag;
- fetch latency;
- error rate;
- offset commit success;
- duplicate processing according to application semantics.

If follower fetching is enabled, verify that consumers normally read from the intended DC and document behavior when that local replica is unavailable.

---

## 22. Topic-Level Validation

Create dedicated test topics representing at least three classes.

### Class A — Critical synchronous durability

Example:

```text
RF=6
3 replicas DC1
3 replicas DC2
minISR=4
producer acks=all
```

Expected after complete loss of one DC:

```text
durability protection retained
writes stop
```

### Class B — Availability-oriented test topic

Use a deliberately different configuration approved for the lab to demonstrate availability/durability trade-offs.

Do **not** silently reuse this configuration for production.

### Class C — Observer-enabled MRC topic

If MRC observers are licensed/configured:

- verify observer placement;
- verify observer lag;
- verify automatic promotion configuration;
- verify failure behavior.

---

## 23. Monitoring Requirements

Create dashboards and alerts for at least:

### KRaft

- active controller;
- current voters;
- current observers;
- metadata leader changes;
- metadata high watermark;
- metadata replication lag;
- metadata quorum unavailable.

### Broker

- broker availability;
- offline partitions;
- under-replicated partitions;
- ISR shrink/expand;
- leader elections;
- unclean leader elections;
- request latency;
- network errors.

### Storage

- disk usage;
- disk latency;
- log directory failures;
- filesystem errors.

### Network

- DC1↔DC2 RTT;
- p95/p99 latency;
- packet loss;
- retransmissions;
- bandwidth saturation.

### Client

- producer errors/timeouts;
- producer latency;
- consumer lag;
- rebalance rate;
- failed offset commits.

---

## 24. RPO/RTO Measurement

For every disaster test record:

```text
T0 = failure injected
T1 = monitoring detects failure
T2 = KRaft leader available / unavailable determination
T3 = application impact begins
T4 = service restored
T5 = all replicas fully caught up
```

Calculate:

```text
Detection time = T1 - T0
Control-plane recovery time = T2 - T0
Application RTO = T4 - T0
Replica convergence time = T5 - T0
```

For RPO testing, publish messages containing:

```text
monotonic sequence number
producer timestamp
unique event ID
producer DC
test-run ID
```

After recovery verify the highest acknowledged sequence that exists in the surviving data.

---

## 25. DC1 Loss Disaster-Recovery Runbook Requirement

Because `3 + 2` intentionally cannot retain quorum after loss of DC1, production approval requires a separate, tested DR runbook.

The runbook must specify:

1. how the team confirms DC1 is truly unavailable;
2. how split-network conditions are distinguished from destructive site loss;
3. who has authority to initiate quorum recovery;
4. how controller metadata state is validated;
5. how dynamic quorum recovery is performed using the exact supported Confluent 8.3.x procedure;
6. how data-plane leader/ISR state is assessed;
7. how applications are redirected;
8. what data-loss decision is permitted, if any;
9. how the original DC is fenced before recovery;
10. how DC1 is safely reintroduced.

Do not create an improvised `force` procedure from this test document. Use the exact disaster-recovery procedure supported by the target Confluent version and validate it in a disposable lab before production use.

---

## 26. Rollback Strategy

Maintain rollback checkpoints.

### Checkpoint A — Before software upgrade

Rollback:

```text
Remain on 7.8.1 / chosen patched 7.8.x state
No quorum topology change
```

### Checkpoint B — 8.3 software installed but feature level not finalized

Review supported downgrade path for the exact metadata/version state.

### Checkpoint C — Feature level upgraded

Downgrade may be restricted depending on metadata changes. Do not assume package rollback is sufficient.

### Checkpoint D — Dynamic quorum enabled

Preserve:

- controller IDs;
- directory IDs;
- storage directories;
- configuration backups;
- quorum status output.

### Checkpoint E — Five-voter topology active

If re-adding the sixth controller is required, use the supported dynamic-controller membership procedure:

1. provision/configure controller;
2. format as required for joining the existing quorum;
3. start it;
4. wait until metadata is caught up;
5. add it using the supported dynamic quorum operation if auto-join is not applicable to the exact environment;
6. verify `CurrentVoters`.

---

## 27. Go / No-Go Criteria

### GO

All of the following must be true:

```text
[ ] Client protocol compatibility validated
[ ] Java runtime validated
[ ] 8.3.x rolling upgrade completed
[ ] Cluster stable under representative workload
[ ] Dynamic quorum validated
[ ] 5-voter 3+2 membership validated
[ ] DC2-loss test passes at KRaft level
[ ] WAN-partition test leaves DC1 authoritative
[ ] No split-brain behavior observed
[ ] Data-plane behavior matches minISR/acks design
[ ] Producer and consumer behavior documented
[ ] RPO measured
[ ] RTO measured
[ ] DC1-loss DR runbook tested
[ ] Monitoring and alerting validated
[ ] Business accepts DC1 as preferred site
[ ] Business accepts lack of automatic KRaft quorum after total DC1 loss
```

### NO-GO

Any of the following is a no-go:

```text
[ ] Unexpected loss of KRaft quorum during single-node maintenance
[ ] Unexpected split-brain symptoms
[ ] Unknown controller membership
[ ] Unexplained metadata lag
[ ] Deprecated Kafka client traffic
[ ] Offline partitions under normal state
[ ] Uncontrolled unclean leader election
[ ] Failure behavior inconsistent with documented minISR policy
[ ] DC1-loss recovery is untested
[ ] Monitoring cannot distinguish quorum failure from broker failure
[ ] WAN latency/instability makes synchronous replication unacceptable
[ ] Required RPO/RTO cannot be achieved
```

---

## 28. Test Evidence Template

For each test:

```text
Test ID:
Date/time:
Engineer:
Confluent version:
Kafka metadata version:
kraft.version:
Java version:

DC1 controllers available:
DC2 controllers available:
CurrentVoters:
CurrentObservers:
KRaft LeaderId:

Brokers available:
Offline partitions:
Under-replicated partitions:
ISR status:

Producer:
  successes:
  failures:
  p99 latency:

Consumer:
  lag:
  rebalances:
  errors:

Inter-DC RTT p50:
Inter-DC RTT p99:
Packet loss:

Failure injected at:
Failure detected at:
Service recovered at:

Measured RPO:
Measured RTO:

Expected result:
Observed result:
PASS / FAIL:

Notes:
```

---

## 29. Recommended Final State for This Constraint

If only two DCs are available and the organization accepts DC1 as the preferred site, the recommended test target is:

```text
                         SINGLE STRETCHED CLUSTER

          DC1 - PREFERRED                       DC2 - SECONDARY
     ----------------------------          ----------------------------
     B1  Kafka broker                      B4  Kafka broker
     B2  Kafka broker                      B5  Kafka broker
     B3  Kafka broker                      B6  Kafka broker

     C1  KRaft voter                       C4  KRaft voter
     C2  KRaft voter                       C5  KRaft voter
     C3  KRaft voter

              \                              /
               \                            /
                +---- 5-voter quorum ------+
                       majority = 3
```

Normal:

```text
5/5 -> healthy
```

DC2 lost:

```text
3/5 -> DC1 retains KRaft quorum
```

DC1 lost:

```text
2/5 -> no KRaft quorum; DR required
```

WAN partition:

```text
DC1 = 3/5 -> authoritative
DC2 = 2/5 -> cannot form quorum
```

This is a clearer failure model than the existing `3 + 3` layout:

```text
DC1 = 3/6 -> no quorum
DC2 = 3/6 -> no quorum
```

during a full inter-site partition.

---

## 30. Key Risks

| Risk | Impact | Mitigation / Test |
|---|---|---|
| Complete DC1 loss | KRaft quorum unavailable | Tested DR runbook |
| DC1 controller degraded before DC2 loss | May lose quorum despite preferred-site design | Alerting + maintenance policy |
| WAN latency | High produce latency with synchronous replication | Measure p95/p99 RTT and producer latency |
| WAN partition | ISR shrink / write unavailability | Test minISR and MRC behavior |
| Old clients | Cannot communicate with CP 8.3 broker protocol | `DeprecatedRequestsPerSec` validation |
| Feature-level upgrade | Downgrade constraints | Separate checkpoint and backup |
| Incorrect voter removal | Metadata-quorum risk | Dynamic quorum procedure + status verification |
| Incorrect rack/placement config | Wrong replicas per DC | Export and validate topic assignments |
| Treating 3+2 as symmetric HA | Incorrect business expectation | Explicit architecture sign-off |

---

## 31. Decision Record

The test should end with one of these decisions:

### Decision A — Accept 3+2

Use when:

- DC1 is explicitly the preferred site;
- loss of DC2 must be automatically survivable at the metadata layer;
- loss of DC1 may invoke manual DR;
- RPO/RTO tests satisfy business requirements.

### Decision B — Keep 3+3 Temporarily

Use only if:

- topology change is deferred;
- the organization explicitly accepts that a complete site loss or clean 3/3 network partition removes KRaft majority;
- a separate recovery procedure exists.

### Decision C — Replace Stretched Cluster with Two Independent Clusters

Evaluate Cluster Linking / active-passive or active-active when:

- WAN latency is high or unstable;
- two-site symmetry is more important than synchronous RPO=0;
- operational isolation is preferred;
- the lack of a third voting location makes stretched-cluster behavior unacceptable.

Confluent's current multi-datacenter guidance recommends independent clusters with Cluster Linking for many higher-latency or unpredictable-network scenarios.

---

## 32. Official References

The following sources should be rechecked against the exact patch release used during the test.

1. **Confluent Platform — Upgrade Confluent Platform**  
   https://docs.confluent.io/platform/current/installation/upgrade.html

2. **Confluent Platform — Configure and Monitor KRaft**  
   https://docs.confluent.io/platform/current/kafka-metadata/config-kraft.html

3. **Confluent Platform 7.8 — Configure and Monitor KRaft**  
   https://docs.confluent.io/platform/7.8/kafka-metadata/config-kraft.html

4. **Confluent Platform 7.8 — Multi-Region Cluster architecture overview**  
   https://docs.confluent.io/platform/7.8/multi-dc-deployments/multi-region-overview.html

5. **Confluent Platform — Multi-Datacenter Architectures**  
   https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region-architectures.html

6. **Confluent Platform — Configure Multi-Region Clusters**  
   https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region.html

7. **Confluent Platform — Supported Versions and Interoperability**  
   https://docs.confluent.io/platform/current/installation/versions-interoperability.html

8. **Confluent Platform — System Requirements**  
   https://docs.confluent.io/platform/current/installation/system-requirements.html

---

## 33. Final Recommendation for the Test

For the stated constraint of **exactly two data centers and no third voting site**, test the following sequence:

```text
1. Baseline current CP 7.8.1 KRaft 3+3 controllers
2. Validate deprecated client protocol use
3. Validate Java 21 readiness
4. Upgrade CP to latest suitable 8.3.x patch using supported rolling procedure
5. Stabilize without changing topology
6. Upgrade release/features only after stability is proven
7. Enable / migrate to dynamic KRaft quorum
8. Verify all six voters healthy
9. Remove one DC2 voter using the supported dynamic-quorum procedure
10. Verify final 3+2 voter set
11. Run single-controller failure tests
12. Run complete DC2-loss test
13. Run inter-DC partition test
14. Run complete DC1-loss test and invoke DR procedure
15. Validate data-plane behavior separately from KRaft behavior
16. Record RPO/RTO
17. Approve or reject the architecture based on evidence
```

The architectural principle is:

> **With only two data centers, choose deterministic ownership rather than false symmetry.**

`3 + 2` gives DC1 deterministic KRaft majority during a two-way site partition or total DC2 loss. It does not provide symmetric site resilience, and this limitation must remain explicit in the production design and DR documentation.
