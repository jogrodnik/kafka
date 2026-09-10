# Kafka Two-DC Stretched Cluster DR Runbook  
## Community vs Confluent Enterprise 8.3

---

# 1. Purpose

This document defines the Disaster Recovery runbook for a stretched Kafka cluster deployed across two data centers for the Kafka data plane and three failure domains for the KRaft controller quorum.

The document compares two implementations:

- Kafka / Confluent Community capabilities
- Confluent Enterprise 8.3 capabilities

The primary goal is to understand:

- what happens during a full data-center failure,
- what happens to acknowledged Kafka records,
- when writes stop,
- how broker data is recovered,
- how the KRaft control plane behaves,
- how the cluster is restored to the original 3+3 topology,
- and exactly where Confluent Enterprise reduces operational complexity compared with Community.

The target design prioritizes:

```text
RPO = 0 for successfully acknowledged Kafka records

RTO = minutes where possible

No unclean leader election

No intentional acceptance of data loss

Manual DR decision is acceptable
```

---

# 2. Agreed Production Architecture

## Kafka brokers

```text
DC1
B101
B102
B103

DC2
B201
B202
B203
```

Total broker count:

```text
6
```

## KRaft controllers

```text
DC1
C101
C102

DC2
C201
C202

DC3
C301
```

Controller topology:

```text
2 + 2 + 1
```

Total voters:

```text
5
```

Required majority:

```text
3
```

This design deliberately separates broker-data fault tolerance from controller-quorum fault tolerance.

---

# 3. Broker Data Configuration

For critical business topics:

```properties
replication.factor=6
min.insync.replicas=5
unclean.leader.election.enable=false
```

Producer requirement:

```properties
acks=all
```

Broker rack configuration:

```text
DC1 brokers:
broker.rack=DC1

DC2 brokers:
broker.rack=DC2
```

The intended replica layout for every critical partition is:

```text
DC1 = 3 replicas
DC2 = 3 replicas
```

Therefore:

```text
RF = 6
Placement = 3 + 3
minISR = 5
acks = all
```

---

# 4. Important Property of RF=6 in This Exact Six-Broker Cluster

There are exactly six brokers:

```text
B101 B102 B103 B201 B202 B203
```

and:

```text
RF = 6
```

Therefore each partition must have one replica on every broker.

For example:

```text
Topic: payments
Partition: 0

Replicas:
B101
B102
B103
B201
B202
B203
```

This automatically produces:

```text
DC1 = 3
DC2 = 3
```

in the current six-broker topology.

This is stronger than merely saying:

```text
Kafka is rack-aware
```

because there are no additional brokers on which another replica could be placed.

However, this property must not be treated as a permanent placement policy.

If the cluster later contains:

```text
7
8
9
...
```

brokers, `RF=6` alone no longer guarantees exactly:

```text
3 DC1 + 3 DC2
```

This is one of the areas where Confluent Enterprise Replica Placement becomes operationally valuable.

---

# 5. Why minISR=5 Is Important

The configuration:

```text
RF = 6
minISR = 5
acks = all
```

provides a very strong write durability requirement.

Kafka requires at least five replicas to remain in the ISR before an `acks=all` write can succeed.

The only possible geographic distribution of five ISR members in a 3+3 topology is:

```text
DC1 = 3
DC2 = 2
```

or:

```text
DC1 = 2
DC2 = 3
```

Therefore every successfully acknowledged write has, at acknowledgement time, at least:

```text
2 in-sync replicas in DC1
AND
2 in-sync replicas in DC2
```

This is the central durability property of the design.

Kafka documents that `min.insync.replicas` defines the minimum number of ISR members required for an `acks=all` write to succeed.

---

# 6. Important acks=all Clarification

`minISR=5` does not mean:

```text
Kafka acknowledges after exactly 5 replicas
```

If the ISR currently contains six replicas:

```text
ISR = 6
```

then an `acks=all` write is acknowledged after the write has been replicated according to Kafka's ISR acknowledgement semantics across that ISR.

`minISR=5` is the safety threshold below which the broker refuses new writes.

Therefore:

```text
ISR = 6
write allowed

ISR = 5
write allowed

ISR = 4
write rejected
```

The design should therefore be understood as:

```text
minISR=5 = minimum safe operating ISR
```

not as:

```text
exact acknowledgement count = 5
```

Apache Kafka explicitly describes this distinction in the broker and topic configuration reference.

---

# 7. Normal Healthy State

A healthy partition could look like:

```text
Partition P0

Leader:
B101

Followers:
B102
B103
B201
B202
B203

Replicas:
101,102,103,201,202,203

ISR:
101,102,103,201,202,203
```

State:

```text
RF  = 6
ISR = 6
minISR = 5
```

Writes:

```text
AVAILABLE
```

Reads:

```text
AVAILABLE
```

Durability:

```text
FULL
```

---

# 8. Loss of One Broker

Assume:

```text
B103 fails
```

The partition becomes:

```text
Replicas:
101,102,103,201,202,203

ISR:
101,102,201,202,203
```

Therefore:

```text
ISR = 5
minISR = 5
```

Writes can continue.

This is an important operational property.

The cluster tolerates one replica leaving the ISR while maintaining the configured write policy.

State:

```text
1 broker failure
        |
        v
ISR 6 -> 5
        |
        v
5 >= minISR 5
        |
        v
WRITE AVAILABLE
```

The failed broker should nevertheless be restored promptly because the cluster has exhausted its configured ISR margin.

---

# 9. Loss of a Second Replica Before Recovery

Assume:

```text
B103 already failed
```

and then:

```text
B202 leaves ISR
```

Now:

```text
ISR = 4
```

Therefore:

```text
4 < minISR 5
```

New `acks=all` writes stop.

Expected producer errors can include:

```text
NotEnoughReplicas

or

NotEnoughReplicasAfterAppend
```

This is deliberate.

The cluster chooses durability over write availability.

---

# 10. Full Loss of DC1

Assume complete failure of:

```text
B101
B102
B103
```

Surviving brokers:

```text
B201
B202
B203
```

A partition previously had:

```text
ISR:
101,102,103,201,202,203
```

Following DC1 loss:

```text
ISR:
201,202,203
```

Therefore:

```text
ISR = 3
minISR = 5
```

New writes cannot proceed.

The expected data-plane state is:

```text
DC1 LOST
    |
    v
3 synchronous replicas survive in DC2
    |
    v
ISR falls to 3
    |
    v
3 < minISR 5
    |
    v
WRITE STOP
```

This is expected and correct.

---

# 11. Why Acknowledged Data Should Survive DC1 Loss

Before an `acks=all` write was acknowledged, at least five replicas had to remain in ISR.

Because no DC contains more than three replicas, those five replicas necessarily included at least two replicas in each DC.

Therefore an acknowledged record could not have existed only in DC1.

At acknowledgement time the possible distribution was at least:

```text
3 DC1 + 2 DC2
```

or:

```text
2 DC1 + 3 DC2
```

Consequently, complete loss of one DC should leave current synchronous copies of acknowledged records in the surviving DC, assuming the surviving replicas remained healthy and no separate data-corruption event occurred.

This is the architectural reason this design can target:

```text
RPO = 0
```

for acknowledged writes.

---

# 12. What minISR=5 Does NOT Guarantee

`minISR=5` does not provide:

```text
automatic application failover

automatic DNS failover

automatic replacement of failed brokers

automatic restoration to six replicas

automatic verification of data correctness

automatic reconstruction of a destroyed DC

automatic DR declaration
```

It protects Kafka write durability.

Operational recovery remains a separate process.

---

# 13. KRaft Controller Architecture

Controllers are deployed as:

```text
DC1:
C101
C102

DC2:
C201
C202

DC3:
C301
```

Total voters:

```text
5
```

Majority:

```text
floor(5 / 2) + 1 = 3
```

A KRaft leader must maintain quorum with three voters.

This is independent from:

```text
RF
ISR
minISR
broker leader election
```

Those belong to the broker/data plane.

---

# 14. Controller Failure Matrix

## Loss of DC1

Controllers lost:

```text
C101
C102
```

Remaining:

```text
C201
C202
C301
```

Result:

```text
3 / 5 voters available
```

Quorum survives.

---

## Loss of DC2

Remaining:

```text
C101
C102
C301
```

Result:

```text
3 / 5
```

Quorum survives.

---

## Loss of DC3

Remaining:

```text
C101
C102
C201
C202
```

Result:

```text
4 / 5
```

Quorum survives.

---

## Loss of DC1 + DC3

Remaining:

```text
C201
C202
```

Result:

```text
2 / 5
```

No majority.

KRaft quorum is unavailable.

---

## Loss of DC2 + DC3

Remaining:

```text
C101
C102
```

Again:

```text
2 / 5
```

No quorum.

---

# 15. DR Declaration Criteria

Do not immediately start destructive or permanent recovery operations when one DC becomes unreachable.

First classify the incident as either:

```text
TRANSIENT FAILURE
```

or:

```text
DECLARED DISASTER
```

Examples of transient failure:

```text
network interruption
power incident with expected rapid recovery
temporary storage outage
routing failure
firewall problem
orchestrator problem
```

Examples of declared disaster:

```text
data center physically unavailable
storage permanently lost
recovery time exceeds business RTO
brokers cannot be recovered
site intentionally abandoned
```

Permanent reassignment should normally occur only after DR is formally declared.

---

# 16. Common DR Step 1 — Freeze Administrative Changes

Immediately stop non-essential Kafka administrative activity.

Do not perform:

```text
topic creation
topic deletion
partition-count changes
routine reassignments
cluster expansion
broker decommissioning
bulk configuration changes
```

until the cluster state is understood.

Also avoid automatically changing:

```text
minISR
```

during the initial diagnosis.

The first priority is evidence preservation and state assessment.

---

# 17. Common DR Step 2 — Verify KRaft Quorum

Run:

```bash
kafka-metadata-quorum.sh \
  --bootstrap-controller <controller-endpoint> \
  --command-config admin.properties \
  describe --status
```

Validate:

```text
LeaderId

CurrentVoters

CurrentObservers, if applicable

HighWatermark

MaxFollowerLag

MaxFollowerLagTimeMs
```

Expected after DC1 controller loss:

```text
Available voters:
C201
C202
C301
```

and an active controller should remain elected.

If there is no controller quorum, stop broker recovery actions that depend on cluster metadata changes until the control plane has been recovered.

---

# 18. Common DR Step 3 — Verify Broker Registration

Determine which brokers are visible to the cluster.

Expected after complete DC1 loss:

```text
Alive:
B201
B202
B203

Unavailable:
B101
B102
B103
```

Verify broker state through Kafka administrative tooling and monitoring.

Do not assume:

```text
Pod down = broker lost permanently
```

or:

```text
network unreachable = disk data destroyed
```

Those are different failure classes.

---

# 19. Common DR Step 4 — Inspect Topic State

Run:

```bash
kafka-topics.sh \
  --bootstrap-server <bootstrap-server> \
  --command-config admin.properties \
  --describe
```

For each critical partition record:

```text
Leader
Replicas
ISR
Eligible Leader Replicas, if enabled
Offline replicas
```

Example after DC1 failure:

```text
Topic: payments
Partition: 0
Leader: 201
Replicas: 101,102,103,201,202,203
ISR: 201,202,203
```

The important distinction is:

```text
leader exists
```

versus:

```text
no leader exists
```

---

# 20. Common DR Step 5 — Check Offline and Under-Replicated Partitions

Use Kafka tooling to identify degraded partitions.

Typical checks include:

```bash
kafka-topics.sh \
  --bootstrap-server <bootstrap-server> \
  --command-config admin.properties \
  --describe \
  --under-replicated-partitions
```

and:

```bash
kafka-topics.sh \
  --bootstrap-server <bootstrap-server> \
  --command-config admin.properties \
  --describe \
  --unavailable-partitions
```

Expected after full loss of DC1:

```text
many under-replicated partitions
```

but ideally:

```text
no unavailable partitions
```

if every partition still has a surviving ISR replica in DC2 and clean leader election succeeds.

---

# 21. Common DR Step 6 — Never Enable Unclean Leader Election as a Routine DR Action

The configuration must remain:

```properties
unclean.leader.election.enable=false
```

Kafka documents that enabling unclean leader election permits a replica outside the ISR to become leader and may result in data loss.

Therefore this must not be used simply to make partitions available faster.

The DR rule is:

```text
availability must not override RPO=0 silently
```

If an unclean election is ever considered, it must be treated as an explicit data-loss decision outside the normal RPO=0 runbook.

---

# 22. Community Runbook — Permanent Loss of DC1

Assume:

```text
DC1 brokers permanently lost:

B101
B102
B103
```

Surviving:

```text
B201
B202
B203
```

State:

```text
RF configured = 6
actual surviving replicas = 3
ISR = 3
minISR = 5
```

## Step 22.1 — Keep writes blocked initially

Do not immediately execute:

```text
minISR 5 -> 3
```

The conservative RPO=0 recovery procedure is to rebuild synchronous replicas first.

---

## Step 22.2 — Provision replacement brokers

Provision three replacement brokers.

For example:

```text
B301
B302
B303
```

These may be located in a rebuilt DC1 or an alternative recovery site.

Set:

```properties
broker.rack=DC1
```

if the site logically replaces DC1.

---

## Step 22.3 — Verify storage and capacity

Before replica movement confirm sufficient:

```text
disk capacity

network throughput

replica capacity

inter-DC bandwidth

CPU

page cache

replication throughput
```

Rebuilding RF=6 can generate very large network transfers.

---

## Step 22.4 — Build the desired assignment

Example old assignment:

```text
P0:
101,102,103,201,202,203
```

Desired assignment:

```text
P0:
301,302,303,201,202,203
```

This must be calculated for every partition that contained lost brokers.

---

## Step 22.5 — Execute reassignment

Use:

```bash
kafka-reassign-partitions.sh \
  --bootstrap-server <bootstrap-server> \
  --command-config admin.properties \
  --reassignment-json-file reassignment.json \
  --execute
```

Community Kafka now copies partition data from surviving replicas to the replacement replicas.

Conceptually:

```text
B201/B202/B203
       |
       | Replica Fetch
       |
       v
B301/B302/B303
```

Kafka provides rack-aware replica placement and standard partition reassignment tooling, but it does not provide Confluent Enterprise Replica Placement policy semantics.

---

## Step 22.6 — Monitor catch-up

Initially:

```text
ISR:
201,202,203

New replicas:
301 catching up
302 catching up
303 catching up
```

Do not consider the cluster fully recovered merely because the brokers are running.

The critical milestone is ISR restoration.

---

## Step 22.7 — Verify ISR growth

Expected progression:

```text
ISR 3
   |
   v
ISR 4
   |
   v
ISR 5
   |
   v
ISR 6
```

At:

```text
ISR = 5
```

the configured `minISR=5` safety threshold can again be satisfied.

Operationally, however, the preferred state remains:

```text
ISR = 6
```

---

## Step 22.8 — Verify reassignment

Run:

```bash
kafka-reassign-partitions.sh \
  --bootstrap-server <bootstrap-server> \
  --command-config admin.properties \
  --reassignment-json-file reassignment.json \
  --verify
```

The target result is:

```text
all reassignments complete
```

---

## Step 22.9 — Check leader distribution

After recovery, leaders may remain concentrated in DC2.

If required:

```bash
kafka-leader-election.sh \
  --bootstrap-server <bootstrap-server> \
  --command-config admin.properties \
  --election-type preferred \
  --all-topic-partitions
```

Kafka supports preferred leader election as a standard administrative operation.

---

## Step 22.10 — Resume traffic

Resume application writes only after validating:

```text
KRaft quorum healthy

all critical topics have leaders

ISR >= 5

preferred target: ISR = 6

no unexpected offline partitions

critical internal topics healthy

reassignment complete

producer/consumer health confirmed
```

---

# 23. Community Runbook — Internal Topics

Business topics are not enough.

The same analysis must include:

```text
__consumer_offsets

__transaction_state
```

and any other critical internal topics.

Relevant Kafka configuration includes the replication factor and minimum ISR settings applicable to these internal topics.

The failure of `__consumer_offsets` can affect:

```text
consumer group recovery
committed offsets
rebalance state
```

The failure of `__transaction_state` can affect:

```text
transaction coordinators
transaction recovery
producer epochs
transaction completion
```

Therefore the Community operational standard should ensure these internal topics receive protection compatible with the intended DR objective.

With six brokers, the target can be designed to match:

```text
RF = 6

3 replicas DC1
3 replicas DC2
```

where operationally appropriate.

The exact replication/minISR settings for internal topics must be validated before deployment because some are controlled by broker-level configuration and may not be casually changed after creation.

---

# 24. Community Operational Responsibility

In Community, the infrastructure team must own the logic that determines:

```text
Is every partition 3+3?

Which broker must receive each replacement replica?

Are internal topics correctly distributed?

Are leaders excessively concentrated?

Which reassignment JSON should be executed?

How much replication traffic should be allowed?

When is recovery complete?

Has the intended topology drifted?
```

Typical supporting automation includes:

```text
Helm

Kubernetes

shell/Python tooling

Prometheus

Grafana

custom validation

kafka-reassign-partitions

kafka-leader-election
```

The underlying Kafka replication mechanism is robust.

The operational difference is that more of the desired-state logic belongs to your platform automation and runbook.

---

# 25. Confluent Enterprise Architecture

Confluent Platform 8.3 contains Apache Kafka 4.3.

For the Enterprise implementation, keep the same synchronous data architecture:

```text
DC1:
3 synchronous replicas

DC2:
3 synchronous replicas
```

Do not introduce observers merely because Enterprise supports them.

For this RPO=0 design, the intended policy remains:

```text
6 synchronous replicas
```

The primary Enterprise additions are:

```text
Replica Placement

Multi-Region Cluster functionality

Self-Balancing

Confluent operational tooling

Control Center visibility
```

Confluent documents Replica Placement as a Multi-Region Cluster mechanism based on `broker.rack`.

---

# 26. Enterprise Replica Placement Policy

Define explicit placement instead of relying only on the current six-broker mathematical property.

Example:

```json
{
  "version": 2,
  "replicas": [
    {
      "count": 3,
      "constraints": {
        "rack": "DC1"
      }
    },
    {
      "count": 3,
      "constraints": {
        "rack": "DC2"
      }
    }
  ]
}
```

This declares:

```text
3 synchronous replicas MUST be in DC1

3 synchronous replicas MUST be in DC2
```

This is fundamentally different from merely saying:

```text
RF=6
```

The desired topology is now explicitly represented as a policy.

Confluent documentation states that Replica Placement defines how replicas are assigned to partitions and that the constraints rely on each broker having a `broker.rack` value.

---

# 27. Enterprise Runbook — Permanent Loss of DC1

The first incident steps are intentionally the same as Community.

## Step 27.1 — Verify KRaft

```bash
kafka-metadata-quorum.sh \
  --bootstrap-controller <controller> \
  --command-config admin.properties \
  describe --status
```

Expected:

```text
C201
C202
C301

3 / 5 voters
```

---

## Step 27.2 — Verify broker and ISR state

Expected:

```text
B101 lost
B102 lost
B103 lost

B201 alive
B202 alive
B203 alive
```

For business partitions:

```text
ISR = 3
```

---

## Step 27.3 — Keep `minISR=5`

Initially retain:

```text
minISR=5
```

Writes therefore remain blocked.

Enterprise does not bypass standard Kafka durability semantics.

---

## Step 27.4 — Declare DC1 permanently unavailable

A human DR decision remains necessary.

Do not allow Self-Balancing or any automation policy to substitute for incident classification when there is a possibility that a site may return shortly.

---

## Step 27.5 — Provision three replacement brokers

Example:

```text
B301
B302
B303
```

Configure:

```properties
broker.rack=DC1
```

Replica Placement now understands that these brokers satisfy the `DC1` placement constraint.

---

## Step 27.6 — Validate placement capacity

The Enterprise policy requires:

```text
3 brokers capable of hosting the DC1 replicas
```

If only two replacement brokers exist:

```text
DC1:
B301
B302
```

a policy requiring:

```text
count = 3
```

cannot be satisfied.

This must be treated as a failed or incomplete recovery.

---

## Step 27.7 — Use Replica Placement-aware balancing

With Confluent Enterprise, the recovery workflow can use placement-aware Confluent tooling instead of manually computing every target replica assignment.

Confluent documents commands such as:

```bash
confluent-rebalancer execute \
  --bootstrap-server <bootstrap> \
  --replica-placement-only \
  --throttle <bytes-per-second> \
  --verbose
```

followed by:

```bash
confluent-rebalancer status \
  --bootstrap-server <bootstrap>
```

and:

```bash
confluent-rebalancer finish \
  --bootstrap-server <bootstrap>
```

The important architectural distinction is that the tool understands the configured placement constraints.

---

## Step 27.8 — Self-Balancing option

If Self-Balancing Clusters are enabled:

```properties
confluent.balancer.enable=true
```

the cluster continuously evaluates placement, capacity, replica distribution, leadership and other balancing goals.

Confluent states that Self-Balancing reacts to replica-placement rules and can proactively move replicas to satisfy them.

Therefore recovery can move closer to:

```text
desired-state driven repair
```

rather than:

```text
operator-generated assignment repair
```

---

## Step 27.9 — Enterprise recovery flow

Conceptually:

```text
DC1 LOST
    |
    v
B101/B102/B103 unavailable
    |
    v
ISR = 3
    |
    v
minISR=5 blocks writes
    |
    v
DR declared
    |
    v
B301/B302/B303 provisioned
broker.rack=DC1
    |
    v
Replica Placement identifies required topology
    |
    v
Rebalancer / Self-Balancing moves replicas
    |
    v
B301/B302/B303 catch up
    |
    v
ISR 3 -> 4 -> 5 -> 6
    |
    v
Placement becomes compliant again
    |
    v
Normal operation restored
```

---

## Step 27.10 — Internal topic placement in Enterprise

Confluent provides placement settings specifically for important internal topics.

Examples include:

```properties
confluent.offsets.topic.placement.constraints
```

and:

```properties
confluent.transaction.state.log.placement.constraints
```

Confluent documents these default placement mechanisms for consumer offsets and transaction-state topics.

The Enterprise architecture can therefore explicitly declare:

```text
__consumer_offsets:
3 DC1 + 3 DC2

__transaction_state:
3 DC1 + 3 DC2
```

subject to the chosen replication settings and supported configuration.

This is a major operational advantage because the geographic policy is explicit rather than merely inferred.

---

# 28. Community vs Enterprise — Final DR Comparison and Architecture Decision

## Core Kafka durability

The fundamental replication mechanism is Kafka in both cases.

For both designs:

```text
RF=6

minISR=5

acks=all

unclean.leader.election.enable=false
```

can provide a very strong synchronous durability model.

Therefore the following statement would be incorrect:

```text
Community cannot provide RPO=0 but Enterprise can.
```

A better statement is:

```text
Community Kafka can provide RPO=0 for acknowledged records
when synchronous replica placement, ISR, minISR and producer
acknowledgement semantics are correctly designed and operated.
```

Enterprise does not create a second magical copy of the data.

The surviving Kafka replicas remain the recovery source.

---

## Where Community requires manual operational control

Community requires the platform team to own:

```text
placement validation

replacement-broker selection

assignment generation

reassignment execution

internal-topic verification

topology drift detection

leader redistribution

recovery validation
```

Typical DR flow:

```text
FAILURE
   |
   v
operator diagnoses
   |
   v
operator verifies ISR
   |
   v
operator provisions brokers
   |
   v
operator generates reassignment
   |
   v
kafka-reassign-partitions
   |
   v
replica catch-up
   |
   v
operator verifies ISR
   |
   v
leader rebalance
   |
   v
normal service
```

---

## Where Enterprise adds value

Enterprise adds an explicit desired-state layer.

For example:

```text
Replica Placement:
DC1 = 3
DC2 = 3
```

The cluster can then reason about a partition as:

```text
required:
3 DC1
3 DC2

actual:
0 DC1
3 DC2

result:
PLACEMENT NOT SATISFIED
```

When replacement capacity returns:

```text
required:
3 DC1
3 DC2

available:
3 DC1
3 DC2

result:
recovery can restore policy
```

Confluent states that Replica Placement constraints are required for properly functioning Multi-Region Cluster deployments because ordinary Kafka placement alone does not guarantee the intended distribution across regions in general topologies.

---

## Enterprise Self-Balancing advantage

Self-Balancing can combine:

```text
rack awareness

replica placement

capacity

replica count

leadership distribution

disk utilization

network considerations
```

when producing rebalance plans.

This makes the Enterprise design substantially easier to operate during:

```text
broker replacement

cluster expansion

cluster shrink

placement drift

post-DR restoration
```

---

## Important limitation

Enterprise does NOT mean:

```text
DC1 disappears
+
3 replicas remain
+
minISR remains 5
+
writes magically continue
```

That cannot happen.

With:

```text
3 surviving ISR
minISR=5
```

writes must stop.

This is the same fundamental Kafka behaviour in both Community and Enterprise.

---

## Availability after complete DC failure

Immediately after DC1 loss:

```text
RF configured = 6

surviving replicas = 3

ISR = 3

minISR = 5
```

Therefore:

```text
WRITE = unavailable
```

while surviving data remains available for recovery.

This is a deliberate architecture decision.

The design chooses:

```text
RPO protection
```

over:

```text
automatic write availability after losing 50% of broker replicas
```

---

## Why not automatically lower minISR to 3?

A tempting DR action is:

```text
minISR 5 -> 3
```

after DC1 disappears.

This would allow writing against:

```text
B201
B202
B203
```

but it changes the durability model.

Before DR:

```text
5 synchronous ISR required
```

During emergency mode:

```text
3 synchronous ISR required
```

If another broker fails while operating in this mode:

```text
3 -> 2
```

the margin becomes much smaller.

Therefore lowering `minISR` should not be an automatic technical reaction.

It must be a documented business DR decision.

---

## Recommended conservative recovery

For this architecture the preferred RPO=0 runbook is:

```text
1. Detect DC failure

2. Verify KRaft quorum

3. Verify surviving brokers

4. Verify leaders

5. Verify ISR

6. Confirm acknowledged data exists on surviving ISR

7. Keep unclean leader election disabled

8. Keep minISR=5

9. Declare DR

10. Provision three replacement brokers

11. Restore 3+3 topology

12. Replicate data to replacement brokers

13. Wait until ISR >= 5

14. Preferably restore ISR=6

15. Validate internal topics

16. Validate consumer groups

17. Validate transaction coordinators

18. Validate producer behaviour

19. Validate leader distribution

20. Remove temporary replication throttles

21. Confirm zero unexpected offline partitions

22. Confirm no under-replicated critical partitions

23. Confirm placement

24. Confirm controller quorum

25. Confirm monitoring

26. Resume producers

27. Resume all workloads

28. Close DR only after final health validation
```

---

# Final Architecture

```text
                     CONTROLLER PLANE
                     ----------------

              DC1          DC2         DC3

             C101         C201
             C102         C202         C301

               \            |           /
                \           |          /
                 +--------------------+
                 |  5-voter KRaft     |
                 |  quorum = 3        |
                 +--------------------+


                       DATA PLANE
                       ----------

              DC1                       DC2

             B101                      B201
             B102                      B202
             B103                      B203

               \                        /
                \                      /
                 +--------------------+
                 |  Kafka partition   |
                 |                    |
                 | RF = 6             |
                 | placement = 3 + 3  |
                 | minISR = 5         |
                 | acks = all         |
                 +--------------------+
```

---

# Expected Failure Properties

| Failure | Controller Quorum | Broker ISR | Writes | Expected RPO |
|---|---|---:|---|---|
| One broker | Healthy | 5 | Available | 0 |
| Two broker replicas leave ISR | Healthy | 4 | Blocked | 0 |
| DC1 brokers lost | Depends on controllers separately | 3 | Blocked | 0 target |
| DC1 brokers + DC1 controllers lost | 3/5 controllers survive | 3 | Blocked | 0 target |
| DC2 brokers + DC2 controllers lost | 3/5 controllers survive | 3 | Blocked | 0 target |
| DC3 controller lost | 4/5 | 6 | Available | 0 |
| DC1 + DC3 controllers lost | 2/5 | N/A control-plane issue | Metadata changes unavailable | Recovery required |
| DC2 + DC3 controllers lost | 2/5 | N/A control-plane issue | Metadata changes unavailable | Recovery required |

---

# Community vs Enterprise Summary

| Capability | Community | Confluent Enterprise 8.3 |
|---|---|---|
| KRaft quorum | Yes | Yes |
| 2+2+1 controllers | Yes | Yes |
| RF=6 | Yes | Yes |
| `minISR=5` | Yes | Yes |
| `acks=all` | Yes | Yes |
| Rack awareness | Yes | Yes |
| RPO=0 design using synchronous replicas | Yes | Yes |
| Standard clean leader election | Yes | Yes |
| Manual reassignment | Yes | Yes |
| Explicit geographic Replica Placement policy | No equivalent Confluent MRC policy | Yes |
| Exact `3 DC1 + 3 DC2` desired-state policy | Custom operational logic | Native Replica Placement |
| Placement-aware Confluent rebalance | No | Yes |
| Self-Balancing | No | Yes |
| Automatic desired-state repair assistance | Custom automation | Yes |
| Internal topic placement constraints | Custom governance | Dedicated Confluent controls |
| Observers | No Confluent MRC observer feature | Yes |
| Observer promotion policies | No | Yes |
| Control Center visibility | No Enterprise C3 feature | Yes |
| DR operator burden | High | Lower |
| Underlying Kafka synchronous durability | Kafka | Kafka |

---

# Architecture Decision

For the fixed six-broker topology:

```text
B101 B102 B103
B201 B202 B203
RF=6
```

Community Kafka is technically capable of implementing the required synchronous durability model.

Because:

```text
RF = total number of brokers
```

every critical partition currently exists on all six brokers and therefore has exactly:

```text
3 replicas in DC1
3 replicas in DC2
```

The strongest reason to adopt Confluent Enterprise is therefore not that Enterprise possesses fundamentally safer Kafka replication.

The stronger reason is operational control.

Community requires us to maintain:

```text
the desired placement model
+
validation
+
reassignment automation
+
topology reconstruction
+
internal-topic governance
+
DR procedures
```

ourselves.

Confluent Enterprise allows the architecture to express much of this explicitly through:

```text
Replica Placement
+
Multi-Region Cluster functionality
+
Self-Balancing
+
placement-aware operational tooling
+
Control Center
```

The architectural comparison is therefore:

```text
COMMUNITY

Kafka provides the replication mechanism.
We provide much of the DR orchestration.


ENTERPRISE

Kafka provides the replication mechanism.
Confluent provides additional desired-state and
multi-region operational control around it.
```

---

# Final Recommendation

For this specific design:

```text
Brokers:
3 DC1 + 3 DC2

Controllers:
2 DC1 + 2 DC2 + 1 DC3

RF=6

3+3 synchronous placement

minISR=5

acks=all

unclean.leader.election.enable=false
```

the architecture is internally consistent for a conservative RPO=0 stretched-cluster design.

A complete DC broker failure intentionally stops writes because:

```text
3 surviving ISR < minISR 5
```

while the 2+2+1 controller design allows the KRaft control plane to survive loss of either primary DC:

```text
2 controllers lost

3 controllers survive

3/5 = quorum
```

The normal DR strategy should therefore be:

```text
do not lower durability automatically

do not use unclean leader election

preserve surviving synchronous replicas

restore replacement brokers

restore ISR

restore 3+3 placement

then reopen normal write traffic
```

For Community, this recovery is primarily runbook- and automation-driven.

For Confluent Enterprise, Replica Placement and Self-Balancing significantly reduce the amount of custom placement and recovery logic that the operating team must maintain.

That is the practical difference between the two solutions for this architecture.