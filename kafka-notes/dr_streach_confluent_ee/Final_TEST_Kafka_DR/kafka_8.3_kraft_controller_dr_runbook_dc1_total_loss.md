# Kafka Community 8.3 — KRaft Controller Disaster Recovery Runbook

**Scenario:** Two data centers, stretched Kafka cluster, dedicated KRaft controllers  
**Normal controller topology:** DC1 = 3 voters, DC2 = 2 voters  
**Failure covered by this runbook:** Complete loss of DC1  
**Edition:** Community features only  
**Validated conceptually against Apache Kafka KRaft / KIP-853 documentation:** 2026-08-24

---

## 1. Purpose

This runbook describes how to reason about and recover the **KRaft control plane** when a Kafka cluster is deployed across only two data centers and uses the following controller voter layout:

```text
DC1 - PREFERRED / PRIMARY          DC2 - SECONDARY
-------------------------          -------------------------
C1  KRaft voter                    C4  KRaft voter
C2  KRaft voter                    C5  KRaft voter
C3  KRaft voter

Total voters = 5
Majority     = 3
```

Normal state:

```text
5 / 5 voters available
=> quorum healthy
```

Loss of DC2:

```text
C1 C2 C3 survive
3 / 5 voters available
=> quorum remains available
```

Loss of DC1:

```text
C4 C5 survive
2 / 5 voters available
=> NO KRaft majority
=> NO active controller
=> control plane unavailable
```

This is the key architectural limitation of a two-DC `3+2` layout.

The design provides deterministic protection against loss of the **2-voter site**, but it does **not** provide symmetric automatic site-level HA.

---

# 2. Most Important DR Rule

After complete loss of DC1:

```text
Current voter set = C1 C2 C3 C4 C5
Available voters  = C4 C5
Required majority = 3
Available          = 2
```

Therefore:

```text
NO QUORUM
```

At this point:

```bash
kafka-metadata-quorum.sh ... add-controller
```

is **not** the first recovery action.

Why?

`add-controller` is an online dynamic-quorum operation. It must communicate with the active KRaft controller.

With only `2/5` voters:

```text
no majority
=> no active controller
=> AddRaftVoter cannot be committed
```

KIP-853 improves controller membership management while a quorum exists. It does not turn a minority partition into a new authoritative quorum.

---

# 3. What Must Be Recovered First

The first DR objective is:

> Restore at least one valid member of the original majority with metadata that belongs to the same KRaft cluster.

For the original topology:

```text
C1 C2 C3 | C4 C5
```

after DC1 loss:

```text
X  X  X  | C4 C5
```

you need to reach at least:

```text
C1'       | C4 C5
```

or:

```text
C2'       | C4 C5
```

or:

```text
C3'       | C4 C5
```

Then:

```text
3 / 5 voters
=> majority restored
=> KRaft leader can be elected
```

Only after this point should normal KIP-853 administrative operations be used.

---

# 4. Important Distinction: Controller Metadata vs Topic Data

Kafka brokers store topic records.

KRaft controllers store cluster metadata.

Examples of controller metadata include:

- topics;
- partition definitions;
- replica assignments;
- ISR state;
- leaders;
- broker registrations;
- topic IDs;
- configurations;
- ACL-related metadata where applicable;
- feature levels;
- KRaft voter configuration.

The fact that broker disks are intact does **not** mean that the KRaft metadata quorum can be reconstructed automatically from broker log directories.

Do not treat broker topic data as a replacement for the controller metadata log.

---

# 5. DR Preconditions

A production implementation of this design should prepare the following before an incident.

## 5.1 Preserve controller identity

For each controller record:

```text
node.id
controller hostname
controller listener port
metadata.log.dir
cluster.id
directory.id
DC / rack / VM identity
```

Example inventory:

```text
Controller  Node ID  Site  Listener
----------  -------  ----  ------------------------
C1          101      DC1   c1.kafka:9093
C2          102      DC1   c2.kafka:9093
C3          103      DC1   c3.kafka:9093
C4          104      DC2   c4.kafka:9093
C5          105      DC2   c5.kafka:9093
```

## 5.2 Protect the KRaft metadata storage

For dedicated controllers:

```properties
metadata.log.dir=/data/kafka-metadata
```

This storage is operationally critical.

The DR design should include infrastructure-level protection appropriate to the platform, for example:

- durable disks;
- storage snapshots;
- VM/storage replication;
- documented restore procedure;
- retained controller configuration;
- retained TLS/SASL material;
- retained DNS identity.

A restored controller must not accidentally become a new unrelated Kafka controller.

## 5.3 Preserve configuration

Keep version-controlled copies of:

```text
controller.properties
server.properties
security configuration
listener configuration
DNS records
certificates / trust material
systemd / container definitions
```

## 5.4 Know the cluster ID

Before an incident:

```bash
bin/kafka-cluster.sh cluster-id \
  --bootstrap-controller c1.kafka:9093
```

Record:

```text
cluster.id=<CLUSTER_ID>
```

Also inspect:

```text
meta.properties
```

on controller storage.

---

# 6. Normal-State Health Baseline

Run regularly and before maintenance.

## 6.1 Quorum status

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c1.kafka:9093,c4.kafka:9093 \
  describe --status
```

Record at minimum:

```text
ClusterId
LeaderId
LeaderEpoch
HighWatermark
MaxFollowerLag
MaxFollowerLagTimeMs
CurrentVoters
CurrentObservers
```

Expected:

```text
CurrentVoters = C1 C2 C3 C4 C5
LeaderId      = one of the five
HighWatermark = advancing when metadata changes
```

## 6.2 Replication state

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c1.kafka:9093,c4.kafka:9093 \
  describe --replication
```

Check:

```text
ReplicaId
ReplicaDirectoryId / DirectoryId
LogEndOffset
Lag
LastFetchTimestamp
LastCaughtUpTimestamp
Status
```

All five voters should normally be caught up or close to the leader.

---

# 7. Incident: Complete Loss of DC1

Initial condition:

```text
DC1                           DC2
--------------------          --------------------
C1 DOWN                       C4 UP
C2 DOWN                       C5 UP
C3 DOWN

B1/B2/B3 may be DOWN          B4/B5/B6 may be UP
```

KRaft:

```text
available voters = 2
required voters  = 3

=> control plane unavailable
```

---

# 8. Phase 1 — Declare and Freeze the Incident

Do not immediately:

- format replacement controllers;
- generate a new cluster ID;
- use `--standalone` on an empty replacement node;
- create a new independent KRaft quorum using the surviving brokers;
- delete controller metadata;
- modify surviving controller `meta.properties`;
- perform unclean leader election merely because the controller quorum is unavailable.

The first task is to preserve evidence and determine whether DC1 is:

```text
temporarily unreachable
```

or:

```text
permanently lost
```

A network partition and a destroyed data center require different actions.

---

# 9. Phase 2 — Confirm the Failure Is Really Quorum Loss

From DC2, test both surviving controllers:

```bash
nc -vz c4.kafka 9093
nc -vz c5.kafka 9093
```

Check processes:

```bash
systemctl status kafka
```

or the equivalent container / Kubernetes runtime status.

Check controller logs.

Typical symptom:

```text
no active KRaft leader
election retries
cannot obtain majority
```

Try:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c4.kafka:9093,c5.kafka:9093 \
  describe --status
```

The command may fail or be unable to obtain usable quorum state because the remaining controllers are a minority.

Do not interpret this as loss of topic data.

---

# 10. Phase 3 — Determine Recovery Source

Recovery priority:

```text
1. Recover connectivity to one original DC1 controller
2. Recover one original DC1 controller VM/server with its metadata disk intact
3. Restore one original controller's metadata storage and identity onto replacement infrastructure
4. Only after majority is restored, perform dynamic quorum membership repair
```

The safest case is simply:

```text
C1 becomes reachable again
```

Then:

```text
C1 + C4 + C5 = 3 voters
```

and the original quorum can elect a leader.

---

# 11. Recovery Path A — One Original DC1 Controller Returns

Example:

```text
C1 returns
C2 lost
C3 lost
C4 healthy
C5 healthy
```

Result:

```text
C1 C4 C5 = 3 / 5
=> majority
```

## 11.1 Start only the valid recovered controller

Verify its original storage is mounted:

```bash
grep -E '^(cluster.id|node.id|directory.id)' \
  /data/kafka-metadata/meta.properties
```

Confirm `node.id` is the expected controller identity.

Start Kafka:

```bash
bin/kafka-server-start.sh -daemon config/controller.properties
```

or:

```bash
systemctl start kafka
```

## 11.2 Verify quorum re-forms

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c1.kafka:9093,c4.kafka:9093,c5.kafka:9093 \
  describe --status
```

Expected:

```text
LeaderId:       valid controller ID
CurrentVoters:  five configured voters
Quorum:         operational
```

## 11.3 Verify replication

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c1.kafka:9093,c4.kafka:9093,c5.kafka:9093 \
  describe --replication
```

Do not proceed until the recovered controller and surviving controllers show a coherent committed metadata state.

---

# 12. Recovery Path B — Restore an Original Controller onto Replacement Infrastructure

Use this path only if the original controller host is lost but its KRaft metadata storage can be recovered through the approved infrastructure DR mechanism.

Example target:

```text
old C1:
node.id=101
hostname=c1.kafka
metadata.log.dir=/data/kafka-metadata
```

Replacement must be prepared so that the cluster sees the **same intended controller identity**, not an arbitrary new voter.

Important items:

```text
same Kafka cluster
same node.id where restoring that voter
correct controller endpoint
correct controller TLS/SASL identity
restored metadata.log.dir
correct cluster.id
correct directory identity/state
```

If dynamic voter records contain the original controller endpoint, DNS or network recovery may need to make that endpoint resolve to the replacement node.

## 12.1 Do not run a normal blank-node format over restored metadata

Do **not** do:

```bash
kafka-storage.sh format ...
```

against the restored metadata directory merely to make startup succeed.

Formatting the wrong storage can destroy the very metadata needed for recovery.

## 12.2 Validate restored storage offline

Inspect:

```text
/data/kafka-metadata/meta.properties
```

and the metadata partition:

```text
/data/kafka-metadata/__cluster_metadata-0/
```

Optional diagnostic decoding:

```bash
bin/kafka-dump-log.sh \
  --cluster-metadata-decoder \
  --files /data/kafka-metadata/__cluster_metadata-0/<segment-or-snapshot>
```

The purpose is validation, not manual metadata editing.

## 12.3 Start the restored voter

Once its identity, storage and network endpoint have been verified:

```bash
systemctl start kafka
```

Then test:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c1.kafka:9093,c4.kafka:9093,c5.kafka:9093 \
  describe --status
```

If majority forms:

```text
C1 + C4 + C5
=> 3 / 5
=> active controller elected
```

---

# 13. STOP CONDITION — If No Third Original Voter Can Be Recovered

If the only surviving authoritative controller state is:

```text
C4
C5
```

and all three original DC1 controller metadata copies are permanently unavailable:

```text
2 / 5
```

then do **not** assume that KIP-853 provides a supported command such as:

```text
force-majority
```

or:

```text
promote-minority-to-new-quorum
```

The normal `add-controller` / `remove-controller` APIs require a functioning active controller and therefore cannot commit voter-set changes when the cluster has no majority.

At this point the incident is no longer an ordinary online KRaft membership change.

It becomes a **metadata-quorum disaster**.

For a production environment, this case must be handled according to an explicitly validated restore design, vendor/support guidance where applicable, or a separately tested cluster-rebuild procedure.

Do not invent a new voter set on production data without a tested procedure.

---

# 14. Why `--standalone` Is Not the DR Fix

Kafka can bootstrap a brand-new dynamic KRaft cluster with:

```bash
bin/kafka-storage.sh format \
  --cluster-id <cluster-id> \
  --standalone \
  --config controller.properties
```

This is intended to bootstrap the first voter of a new quorum.

It creates initial KRaft control records.

It should **not** be treated as a generic command for converting an arbitrary surviving `2/5` minority into the authoritative continuation of an existing production metadata log.

The surviving brokers may contain topic records, but that does not mean a newly bootstrapped controller automatically knows the complete previous cluster metadata.

---

# 15. After Majority Is Restored — Dynamic Quorum Repair

Once:

```text
LeaderId != none
quorum healthy
metadata High Watermark stable
```

KIP-853 becomes useful.

Example current situation:

```text
C1 restored
C4 healthy
C5 healthy

C2 permanently lost
C3 permanently lost
```

Logical voter set may still contain:

```text
C1 C2 C3 C4 C5
```

Now you can repair the topology online.

---

# 16. Inspect Current Voters

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c1.kafka:9093,c4.kafka:9093,c5.kafka:9093 \
  describe --status
```

Record:

```text
CurrentVoters
controller IDs
controller directory IDs
endpoints
```

Also:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c1.kafka:9093,c4.kafka:9093,c5.kafka:9093 \
  describe --replication
```

---

# 17. Add a New Controller — Only After Quorum Exists

Suppose a new controller is prepared in DC2 or temporary DR infrastructure:

```text
C6
node.id=106
```

Format it as a node that is joining an **existing** cluster:

```bash
bin/kafka-storage.sh format \
  --cluster-id <CLUSTER_ID> \
  --config config/controller-c6.properties \
  --no-initial-controllers
```

Start it:

```bash
bin/kafka-server-start.sh -daemon \
  config/controller-c6.properties
```

It initially catches up as a non-voting controller/observer.

Then add it:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c1.kafka:9093,c4.kafka:9093,c5.kafka:9093 \
  --command-config config/controller-c6.properties \
  add-controller
```

Verify:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c1.kafka:9093,c4.kafka:9093,c5.kafka:9093 \
  describe --status
```

and:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c1.kafka:9093,c4.kafka:9093,c5.kafka:9093 \
  describe --replication
```

Do not count a new controller as useful redundancy until it has caught up and is part of the committed voter set.

---

# 18. Remove Permanently Lost Voters

After replacement voters are healthy, remove permanently lost controllers using the supported dynamic-quorum command for the exact Kafka 8.3 build.

Typical KIP-853 form:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c1.kafka:9093,c4.kafka:9093,c5.kafka:9093 \
  remove-controller \
  --controller-id <ID> \
  --controller-directory-id <DIRECTORY_ID>
```

Example conceptual sequence:

```text
Before:
C1 C2 C3 C4 C5

C2/C3 dead

Add:
C6
C7

Temporary:
C1 C2 C3 C4 C5 C6 C7

Remove dead voters:
C2
C3

Final:
C1 C4 C5 C6 C7
```

Choose the final voter count and failure-domain placement deliberately.

Avoid casually leaving an even-numbered voter set.

---

# 19. Rebuild Preferred 3+2 Architecture

If DC1 is later rebuilt, the target can again be:

```text
NEW DC1 / PREFERRED                DC2
-----------------------            -----------------------
C1' voter                          C4 voter
C2' voter                          C5 voter
C3' voter

5 voters
majority = 3
```

Use the online lifecycle:

```text
format new controller with --no-initial-controllers
start controller
wait for catch-up
add-controller
verify
remove temporary controller
verify again
```

Never remove a voter first if doing so would destroy quorum.

---

# 20. Mandatory Verification Before Touching Brokers

After controller recovery:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <healthy-controllers> \
  describe --status
```

Required:

```text
[ ] ClusterId correct
[ ] LeaderId exists
[ ] voter set understood
[ ] HighWatermark valid
[ ] no unexpected voter identity
```

Then:

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <healthy-controllers> \
  describe --replication
```

Required:

```text
[ ] majority caught up
[ ] controller lag converging
[ ] no unexplained stale metadata replica
```

---

# 21. Verify Broker Registration

Once the control plane is healthy:

```bash
bin/kafka-broker-api-versions.sh \
  --bootstrap-server <broker>:9092
```

and:

```bash
bin/kafka-topics.sh \
  --bootstrap-server <broker>:9092 \
  --describe
```

Check:

```text
offline partitions
leaders
replica assignments
ISR
under-replicated partitions
```

Useful summary:

```bash
bin/kafka-topics.sh \
  --bootstrap-server <broker>:9092 \
  --describe \
  --under-replicated-partitions
```

---

# 22. Controller DR Does Not Guarantee Data-Plane DR

Even after the KRaft quorum is restored, some topic partitions may still have no leader.

Controller recovery answers:

```text
Can Kafka manage the cluster again?
```

It does not answer:

```text
Does every partition have enough surviving replicas?
```

Partition recovery depends on:

```text
replication.factor
replica placement
broker.rack
ISR
Eligible Leader Replicas
High Watermark
min.insync.replicas
acks=all
```

Treat control-plane DR and partition/data DR as separate recovery stages.

---

# 23. Recommended Data-Plane Checks

## 23.1 Offline partitions

```bash
bin/kafka-topics.sh \
  --bootstrap-server <broker>:9092 \
  --describe \
  --unavailable-partitions
```

## 23.2 Under-replicated partitions

```bash
bin/kafka-topics.sh \
  --bootstrap-server <broker>:9092 \
  --describe \
  --under-replicated-partitions
```

## 23.3 Topic configuration

```bash
bin/kafka-configs.sh \
  --bootstrap-server <broker>:9092 \
  --entity-type topics \
  --entity-name <topic> \
  --describe
```

Check:

```text
min.insync.replicas
unclean.leader.election.enable
```

## 23.4 Broker rack configuration

For stretched topology, ensure the intended failure-domain mapping remains valid:

```properties
broker.rack=DC1
```

or:

```properties
broker.rack=DC2
```

---

# 24. Leader Recovery

Prefer safe leader election.

Example preferred election:

```bash
bin/kafka-leader-election.sh \
  --bootstrap-server <broker>:9092 \
  --election-type PREFERRED \
  --all-topic-partitions
```

Do not use an unclean election merely to make partitions available unless the business explicitly accepts possible data loss and the exact partition state has been assessed.

---

# 25. Reassignment After Site Recovery

After rebuilding the failed DC:

```bash
bin/kafka-reassign-partitions.sh \
  --bootstrap-server <broker>:9092 \
  --generate ...
```

Review the generated assignment.

Then execute only an approved plan:

```bash
bin/kafka-reassign-partitions.sh \
  --bootstrap-server <broker>:9092 \
  --execute \
  --reassignment-json-file reassignment.json
```

Verify:

```bash
bin/kafka-reassign-partitions.sh \
  --bootstrap-server <broker>:9092 \
  --verify \
  --reassignment-json-file reassignment.json
```

The objective is to restore replica distribution across both failure domains, not simply to make the cluster green.

---

# 26. Practical DR State Machine

```text
NORMAL
  |
  | DC1 lost
  v
2 / 5 CONTROLLERS
NO QUORUM
  |
  | recover one original voter
  | with valid metadata + identity
  v
3 / 5 CONTROLLERS
QUORUM RESTORED
  |
  | verify HW and metadata replication
  v
CONTROL PLANE HEALTHY
  |
  | add replacement controllers
  | KIP-853
  v
NEW VOTERS CAUGHT UP
  |
  | remove permanently lost voters
  v
STABLE KRAFT QUORUM
  |
  | verify brokers / ISR / ELR / leaders
  v
DATA-PLANE RECOVERY
  |
  | reassignment / preferred leaders
  v
NORMAL TOPOLOGY
```

---

# 27. Commands Cheat Sheet

## Quorum status

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <controller1>:9093,<controller2>:9093 \
  describe --status
```

## Quorum replication

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <controller1>:9093,<controller2>:9093 \
  describe --replication
```

## Format a new controller for an existing dynamic quorum

```bash
bin/kafka-storage.sh format \
  --cluster-id <CLUSTER_ID> \
  --config controller.properties \
  --no-initial-controllers
```

## Add controller

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <healthy-controller>:9093 \
  --command-config controller.properties \
  add-controller
```

## Remove controller

```bash
bin/kafka-metadata-quorum.sh \
  --bootstrap-controller <healthy-controller>:9093 \
  remove-controller \
  --controller-id <ID> \
  --controller-directory-id <DIRECTORY_ID>
```

## Inspect metadata log

```bash
bin/kafka-dump-log.sh \
  --cluster-metadata-decoder \
  --files <metadata.log.dir>/__cluster_metadata-0/<file>
```

## Topic state

```bash
bin/kafka-topics.sh \
  --bootstrap-server <broker>:9092 \
  --describe
```

## Under-replicated partitions

```bash
bin/kafka-topics.sh \
  --bootstrap-server <broker>:9092 \
  --describe \
  --under-replicated-partitions
```

## Preferred leader election

```bash
bin/kafka-leader-election.sh \
  --bootstrap-server <broker>:9092 \
  --election-type PREFERRED \
  --all-topic-partitions
```

---

# 28. Things Never to Do During KRaft DR

```text
[ ] Do not generate a different cluster ID for a replacement voter.
[ ] Do not format over a metadata directory that may contain the only recoverable controller state.
[ ] Do not assume two surviving voters can commit a new 5-voter configuration.
[ ] Do not assume KIP-853 is a force-quorum mechanism.
[ ] Do not manually edit metadata log records.
[ ] Do not manually edit VotersRecord data.
[ ] Do not delete meta.properties to "fix" identity errors.
[ ] Do not start multiple replacement controllers from duplicated writable copies of one controller disk without a validated design.
[ ] Do not use unclean leader election as a control-plane recovery mechanism.
[ ] Do not assume healthy brokers imply healthy KRaft metadata.
```

---

# 29. Recovery Acceptance Criteria

Control plane:

```text
[ ] active KRaft leader exists
[ ] intended voter count exists
[ ] voter IDs are known and unique
[ ] voter directory IDs are understood
[ ] metadata High Watermark is stable/advancing
[ ] controller replication lag converges
[ ] no election loop
```

Broker plane:

```text
[ ] surviving brokers registered
[ ] no unexplained broker fencing
[ ] cluster metadata visible through Admin API
```

Partition plane:

```text
[ ] offline partitions identified
[ ] ISR state understood
[ ] ELR state considered where applicable
[ ] no uncontrolled unclean election
[ ] surviving leaders are safe
```

Client plane:

```text
[ ] producers reconnect
[ ] consumers reconnect
[ ] metadata refresh succeeds
[ ] bootstrap/rebootstrap paths tested
```

Operational:

```text
[ ] RPO measured
[ ] RTO measured
[ ] incident timeline recorded
[ ] recovered controller source documented
[ ] final voter topology documented
```

---

# 30. Recommended Architecture Improvement

The strongest improvement is to provide a third independent failure domain for the deciding voter.

For example:

```text
DC1              DC2              THIRD FAILURE DOMAIN
----             ----             --------------------
C1               C3               C5
C2               C4

2 voters         2 voters         1 voter
```

Total:

```text
5 voters
majority = 3
```

Loss of DC1:

```text
DC2 2 + third site 1 = 3
=> quorum
```

Loss of DC2:

```text
DC1 2 + third site 1 = 3
=> quorum
```

This removes the fundamental asymmetry of `3+2` across only two sites.

If a third failure domain is impossible, the organization should explicitly accept:

```text
DC1 loss
=> manual KRaft DR
```

and test this runbook regularly.

---

# 31. Suggested DR Test Cases

## DR-01 — Loss of DC2

Expected:

```text
3 / 5 controllers remain
quorum survives automatically
```

No controller DR should be required.

## DR-02 — Loss of one DC1 controller

Expected:

```text
4 / 5 voters remain
quorum survives
```

## DR-03 — Loss of two arbitrary controllers

Expected:

```text
3 / 5 voters remain
quorum survives
```

## DR-04 — Complete loss of DC1

Expected:

```text
2 / 5 remain
no quorum
manual recovery required
```

Exercise recovery of one original voter.

## DR-05 — DC1/DC2 network partition

Expected:

```text
DC1 = 3 / 5
DC2 = 2 / 5

DC1 authoritative
DC2 minority
```

## DR-06 — Restored voter has stale metadata

Validate that quorum recovery and catch-up behavior is understood before declaring service restored.

## DR-07 — Replacement controller

After quorum recovery:

```text
format --no-initial-controllers
start
catch up
add-controller
verify
remove obsolete voter
verify
```

## DR-08 — Data plane after controller recovery

Validate:

```text
ISR
ELR
High Watermark
leader election
minISR
acks=all
rack placement
```

---

# 32. Final Operational Conclusion

For this topology:

```text
DC1 = 3 KRaft voters
DC2 = 2 KRaft voters
```

the DR model is:

```text
Loss of DC2
=> automatic KRaft survival

Loss of DC1
=> no majority
=> no active controller
=> KIP-853 cannot by itself create majority
=> recover one valid original voter first
=> 3/5 majority
=> active controller
=> then use KIP-853 to rebuild voter membership
=> then recover partition/data plane
```

The most important sentence in the runbook is therefore:

> **Dynamic KRaft quorum management is a post-quorum-recovery tool; it is not a replacement for recovering majority after the majority site has been completely lost.**

---

# 33. Official References

1. Apache Kafka — KRaft operations  
   https://kafka.apache.org/39/operations/kraft/

2. Apache Kafka — Hardware and OS / Replace KRaft Controller Disk  
   https://kafka.apache.org/42/operations/hardware-and-os/

3. Apache Kafka KIP-853 — KRaft Controller Membership Changes  
   https://cwiki.apache.org/confluence/display/KAFKA/KIP-853%3A+KRaft+Controller+Membership+Changes

4. Apache Kafka KIP-919 — AdminClient direct controller access / controller registration  
   https://cwiki.apache.org/confluence/display/KAFKA/KIP-919%3A+Allow+AdminClient+to+Talk+Directly+with+the+KRaft+Controller+Quorum+and+add+Controller+Registration

---

## Appendix A — Incident Worksheet

```text
Incident ID:
Date/time:
Engineer:

Kafka version:
Cluster ID:

Normal voters:
C1:
C2:
C3:
C4:
C5:

Available voters:
[ ] C1
[ ] C2
[ ] C3
[ ] C4
[ ] C5

Current reachable voter count:
Required majority:

Original controller metadata recoverable?
C1: YES / NO / UNKNOWN
C2: YES / NO / UNKNOWN
C3: YES / NO / UNKNOWN

Recovery source selected:

Recovered node.id:
Recovered directory.id:
Recovered metadata.log.dir:
Recovered endpoint:

Quorum restored at:

LeaderId:
LeaderEpoch:
HighWatermark:

Replacement voters added:

Old voters removed:

Offline partitions after quorum recovery:
Under-replicated partitions:

RPO:
RTO:

Final voter topology:

Notes:
```
