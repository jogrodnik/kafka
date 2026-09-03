# Kafka KRaft Dynamic Controller Quorum — Operations & Recovery Runbook

## 1. Scope

This runbook covers operational management of a **KIP-853 dynamic KRaft controller quorum**.

Example architecture:

```text
DC1
    C101  node.id=101
    C102  node.id=102
    C103  node.id=103

DC2
    C201  node.id=201
    C202  node.id=202
```

Normal voter set:

```text
101
102
103
201
202
```

Quorum size:

```text
N = 5
majority = 3
```

Therefore:

```text
2 controllers may fail
and quorum can still operate.

3 controllers unavailable
= quorum majority lost.
```

The runbook distinguishes two fundamentally different classes of failure:

```text
A. MAJORITY EXISTS
   -> normal supported Kafka quorum operations

B. MAJORITY LOST
   -> STOP normal membership operations
   -> preserve surviving metadata
   -> forensic / disaster-recovery procedure
```

---

# 2. Important KRaft state

The operator must understand four different pieces of state.

```text
meta.properties
    |
    +--> cluster.id
    +--> node.id
    +--> directory.id
    |
    +--> local storage identity


quorum-state
    |
    +--> LeaderId
    +--> LeaderEpoch
    +--> vote/election state
    |
    +--> local persistent Raft state


__cluster_metadata-0
    |
    +--> snapshots
    +--> log segments
    +--> VotersRecord
    |
    +--> replicated KRaft state


controller.quorum.bootstrap.servers
    |
    +--> addresses used to FIND quorum
    |
    +--> NOT membership
```

For a dynamic quorum:

```properties
controller.quorum.bootstrap.servers=
c101.dc1.example.com:9093,
c102.dc1.example.com:9093,
c103.dc1.example.com:9093,
c201.dc2.example.com:9093,
c202.dc2.example.com:9093
```

Do **not** define dynamic membership with:

```properties
controller.quorum.voters=...
```

Dynamic membership comes from replicated KRaft state.

---

# 3. Command environment

For the examples below:

```bash
export KAFKA_HOME=/opt/kafka
export PATH="$KAFKA_HOME/bin:$PATH"

export CTRL_PORT=9093

export C101=c101.dc1.example.com
export C102=c102.dc1.example.com
export C103=c103.dc1.example.com
export C201=c201.dc2.example.com
export C202=c202.dc2.example.com

export BOOTSTRAP_CONTROLLER="${C101}:${CTRL_PORT}"
```

For authenticated clusters:

```bash
export ADMIN_CONFIG=/etc/kafka/admin.properties
```

Example helper:

```bash
KMQ="$KAFKA_HOME/bin/kafka-metadata-quorum.sh"
KST="$KAFKA_HOME/bin/kafka-storage.sh"
KFEAT="$KAFKA_HOME/bin/kafka-features.sh"
KDUMP="$KAFKA_HOME/bin/kafka-dump-log.sh"
```

If authentication is required, commands generally become:

```bash
$KMQ \
  --command-config "$ADMIN_CONFIG" \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --status
```

---

# 4. First command during every controller incident

Always begin with:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --status
```

Expected type of output:

```text
ClusterId:        ...
LeaderId:         101
LeaderEpoch:      82
HighWatermark:    421304

CurrentVoters:
  101 / UUID101
  102 / UUID102
  103 / UUID103
  201 / UUID201
  202 / UUID202
```

Record at minimum:

```text
ClusterId
LeaderId
LeaderEpoch
HighWatermark
CurrentVoters
directoryId of each voter
```

Do not begin changing membership before you have captured this information.

---

# 5. Check detailed replication state

Run:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --replication
```

Conceptual output:

```text
NodeId  DirectoryId  LogEndOffset  Lag  LastFetchTimestamp ...
101     UUID101      421305        0
102     UUID102      421305        0
103     UUID103      421305        0
201     UUID201      421305        0
202     UUID202      421305        0
```

This command answers:

```text
Which controller is leader?

Which replicas are caught up?

What is each LogEndOffset?

What is each replica's directory.id?

Which replicas are lagging?

Which node is currently an observer rather than voter?
```

---

# 6. Verify that this is a dynamic quorum

Run:

```bash
$KFEAT \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe
```

Look for:

```text
Feature: kraft.version
FinalizedVersionLevel: 1
```

Interpretation:

```text
kraft.version absent or 0
    -> static KRaft quorum

kraft.version >= 1
    -> KIP-853 dynamic quorum
```

If the cluster is static, **do not use the dynamic membership procedures in this runbook**.

---

# 7. Daily quorum health check

A simple operational check:

```bash
#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_CONTROLLER="${1:-c101.dc1.example.com:9093}"

echo "=== KRaft quorum status ==="

kafka-metadata-quorum.sh \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --status

echo

echo "=== KRaft replication ==="

kafka-metadata-quorum.sh \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --replication
```

A healthy five-controller quorum should normally show:

```text
LeaderId != -1

CurrentVoters = 5 controllers

at least 3 controllers reachable

small or zero follower lag

recent LastFetchTimestamp

recent LastCaughtUpTimestamp
```

---

# 8. Important difference: LEO versus High Watermark

Never treat:

```text
LogEndOffset
```

as equivalent to:

```text
HighWatermark
```

Example:

```text
HighWatermark = 10000

C201 LEO = 10000
C202 LEO = 10004
```

This does **not** automatically mean C202 is more authoritative.

The tail:

```text
10000 ... 10004
```

may contain records which have not become committed.

Therefore:

```text
largest LogEndOffset
!=
latest proven committed metadata
```

This distinction becomes critical in disaster recovery.

---

# 9. Identify a controller's storage identity

On the controller host:

```bash
grep -E '^(cluster.id|node.id|directory.id|version)=' \
  /var/lib/kafka/kraft-metadata/meta.properties
```

Example:

```text
cluster.id=q1Sh-9_ISia_zwGINzRvyQ
node.id=201
directory.id=AbCdEfGhIjKlMnOpQrStUv
version=1
```

Record it:

```bash
CLUSTER_ID="$(grep '^cluster.id=' \
  /var/lib/kafka/kraft-metadata/meta.properties |
  cut -d= -f2)"

NODE_ID="$(grep '^node.id=' \
  /var/lib/kafka/kraft-metadata/meta.properties |
  cut -d= -f2)"

DIRECTORY_ID="$(grep '^directory.id=' \
  /var/lib/kafka/kraft-metadata/meta.properties |
  cut -d= -f2)"
```

Display:

```bash
printf 'cluster.id=%s\nnode.id=%s\ndirectory.id=%s\n' \
  "$CLUSTER_ID" \
  "$NODE_ID" \
  "$DIRECTORY_ID"
```

Remember:

```text
controller replica identity
≈
(node.id, directory.id)
```

Example:

```text
old C201:

(201, AAAA)

newly formatted C201:

(201, BBBB)
```

These are different storage incarnations.

---

# 10. Locate the metadata directory

Normally:

```properties
metadata.log.dir=/var/lib/kafka/kraft-metadata
```

Check configuration:

```bash
grep '^metadata.log.dir=' /etc/kafka/controller.properties
```

Then:

```bash
META_DIR=/var/lib/kafka/kraft-metadata
```

Metadata partition:

```bash
ls -lah "$META_DIR/__cluster_metadata-0/"
```

You should see files such as:

```text
00000000000000000000.log
...
xxxxxxxxxxxxxxxxxxxx-yyyyyyyyyy.checkpoint

quorum-state
leader-epoch-checkpoint
...
```

Exact files vary by Kafka version and runtime history.

---

# 11. Inspect `quorum-state`

First preserve the file:

```bash
cp \
  "$META_DIR/__cluster_metadata-0/quorum-state" \
  "/tmp/quorum-state.$(date +%Y%m%d-%H%M%S)"
```

For routine operations, do **not edit this file**.

It contains local Raft election state.

Conceptually:

```text
LeaderId
LeaderEpoch
VotedId
VotedDirectoryId
```

It is **not** the authoritative dynamic voter configuration.

Never fix membership by manually editing:

```text
quorum-state
```

---

# 12. Decode the KRaft metadata log

List segments:

```bash
ls -1 \
  "$META_DIR/__cluster_metadata-0/"*.log
```

Decode a segment:

```bash
$KDUMP \
  --cluster-metadata-decoder \
  --files \
  "$META_DIR/__cluster_metadata-0/00000000000000000000.log"
```

Search for voter-related records:

```bash
$KDUMP \
  --cluster-metadata-decoder \
  --files \
  "$META_DIR/__cluster_metadata-0/00000000000000000000.log" \
  | grep -i -E 'VotersRecord|KRaftVersionRecord'
```

For several log files:

```bash
for f in "$META_DIR/__cluster_metadata-0/"*.log; do
    echo "===== $f ====="

    $KDUMP \
      --cluster-metadata-decoder \
      --files "$f" \
      | grep -i -E 'VotersRecord|KRaftVersionRecord'
done
```

---

# 13. Decode a metadata snapshot

Find snapshots:

```bash
find "$META_DIR/__cluster_metadata-0" \
  -maxdepth 1 \
  -name '*.checkpoint' \
  -printf '%f\n' \
  | sort
```

Then decode an actual metadata snapshot:

```bash
$KDUMP \
  --cluster-metadata-decoder \
  --files \
  "$META_DIR/__cluster_metadata-0/<snapshot>.checkpoint"
```

Search specifically for voter state:

```bash
$KDUMP \
  --cluster-metadata-decoder \
  --files \
  "$META_DIR/__cluster_metadata-0/<snapshot>.checkpoint" \
  | grep -i -A20 -B5 'VotersRecord'
```

The correct model is:

```text
latest valid snapshot
        +
records after the snapshot
        =
local reconstructed KRaft state
```

Do not assume a historic `VotersRecord` must still exist in an old `.log` file.

---

# 14. NORMAL FAILURE — one controller down

Example:

```text
C202 down

alive:
101
102
103
201

quorum:
4 / 5

majority:
YES
```

First:

```bash
$KMQ \
  --bootstrap-controller "${C101}:9093" \
  describe --status
```

Then:

```bash
$KMQ \
  --bootstrap-controller "${C101}:9093" \
  describe --replication
```

If C202 merely crashed but its storage remains intact:

```bash
systemctl status kafka-controller
```

or:

```bash
ps -ef | grep '[k]afka'
```

Check logs:

```bash
journalctl \
  -u kafka-controller \
  -n 200 \
  --no-pager
```

Restart:

```bash
sudo systemctl restart kafka-controller
```

Then monitor:

```bash
watch -n 2 \
  "$KMQ --bootstrap-controller ${C101}:9093 describe --replication"
```

Expected:

```text
C202 starts

C202 uses existing:

node.id=202
directory.id=UUID202

C202 reconnects

C202 catches up

C202 remains same voter identity
```

No `remove-controller` is required for an ordinary restart.

---

# 15. Controller lagging badly

Check:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --replication
```

Pay attention to:

```text
LogEndOffset
Lag
LastFetchTimestamp
LastCaughtUpTimestamp
```

Example:

```text
Leader C101 LEO = 900000

C201 LEO = 900000
C202 LEO = 650000
```

Investigate:

```bash
journalctl \
  -u kafka-controller \
  --since "30 min ago" \
  --no-pager
```

Connectivity:

```bash
nc -vz "$C101" 9093
nc -vz "$C102" 9093
nc -vz "$C103" 9093
```

DNS:

```bash
getent hosts "$C101"
getent hosts "$C102"
getent hosts "$C103"
```

TLS if applicable:

```bash
openssl s_client \
  -connect "${C101}:9093" \
  -servername "$C101"
```

Do **not** remove a lagging voter as your first action.

First determine whether it can catch up.

---

# 16. Add a completely new controller C203

Suppose we want:

```text
existing:

101
102
103
201
202

new controller:

203
```

Configuration on C203:

```properties
process.roles=controller

node.id=203

controller.listener.names=CONTROLLER

listeners=CONTROLLER://c203.dc2.example.com:9093

controller.quorum.bootstrap.servers=
c101.dc1.example.com:9093,
c102.dc1.example.com:9093,
c103.dc1.example.com:9093,
c201.dc2.example.com:9093,
c202.dc2.example.com:9093
```

No:

```properties
controller.quorum.voters=
```

must be present.

---

# 17. Obtain the existing cluster ID

From running quorum:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --status
```

Record:

```text
ClusterId
```

For example:

```bash
export CLUSTER_ID='q1Sh-9_ISia_zwGINzRvyQ'
```

Never generate a new cluster ID for a controller joining an existing cluster.

Wrong:

```bash
kafka-storage.sh random-uuid
```

for this purpose.

Correct:

```text
reuse the existing Kafka ClusterId
```

---

# 18. Format the new controller as NOT an initial voter

On C203:

```bash
$KST format \
  --cluster-id "$CLUSTER_ID" \
  --config /etc/kafka/controller.properties \
  --no-initial-controllers
```

This distinction is critical.

Do **not** use:

```bash
--standalone
```

for a controller joining an existing quorum.

Do **not** construct a new independent voter set.

Use:

```bash
--no-initial-controllers
```

---

# 19. Verify C203 identity

```bash
grep -E \
  '^(cluster.id|node.id|directory.id|version)=' \
  /var/lib/kafka/kraft-metadata/meta.properties
```

Expected:

```text
cluster.id=<existing cluster ID>
node.id=203
directory.id=<new UUID>
```

---

# 20. Start C203

```bash
sudo systemctl start kafka-controller
```

Check:

```bash
sudo systemctl status kafka-controller
```

Logs:

```bash
journalctl \
  -u kafka-controller \
  -f
```

C203 should initially participate in metadata replication without yet being part of the committed voter set.

---

# 21. Verify C203 is caught up before promotion

Run:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --replication
```

You should see C203 represented as an observer/non-voting replica while it catches up.

Wait for approximately:

```text
C203 LogEndOffset ~= leader LogEndOffset

Lag ~= 0

LastCaughtUpTimestamp recent
```

Do not add C203 as voter while badly behind.

---

# 22. Add C203 to the voter set

With current stable Kafka CLI form:

```bash
$KMQ \
  --command-config /etc/kafka/controller-203.properties \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  add-controller
```

The supplied controller config allows the command to identify the new controller's:

```text
node.id
directory.id
controller endpoints
```

Afterward:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --status
```

Expected:

```text
CurrentVoters:

101
102
103
201
202
203
```

Then:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --replication
```

---

# 23. Temporary six-controller quorum

During replacement you may temporarily have:

```text
101
102
103
201
202
203
```

That means:

```text
N = 6
majority = 4
```

Do not deliberately leave the cluster at six voters unless there is an architectural reason.

Typical replacement:

```text
5 voters
   |
   +--> add replacement
   |
6 voters
   |
   +--> remove old controller
   |
5 voters
```

---

# 24. Planned removal of a healthy controller

Example: remove C202.

First obtain authoritative voter identity:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --status
```

Record:

```text
controller-id = 202

controller-directory-id = UUID202
```

Recheck replication:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --replication
```

Make sure removing C202 will still leave a healthy majority.

Then remove:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  remove-controller \
  --controller-id 202 \
  --controller-directory-id UUID202
```

Verify:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --status
```

Expected:

```text
CurrentVoters:

101
102
103
201
```

Only after membership removal has succeeded:

```bash
sudo systemctl stop kafka-controller
```

Do not simply stop/delete a controller and assume dynamic membership disappears automatically.

---

# 25. Replace failed C202 storage

Scenario:

```text
old:

node.id=202
directory.id=AAAA

disk lost
```

The other four controllers are healthy.

First confirm majority:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --status
```

Then:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --replication
```

Record the old identity:

```text
202 + AAAA
```

---

# 26. Build new C202 storage

New storage keeps:

```properties
node.id=202
```

but gets a new:

```text
directory.id=BBBB
```

Format:

```bash
$KST format \
  --cluster-id "$CLUSTER_ID" \
  --config /etc/kafka/controller.properties \
  --no-initial-controllers
```

Verify:

```bash
grep -E \
  '^(cluster.id|node.id|directory.id)=' \
  /var/lib/kafka/kraft-metadata/meta.properties
```

Expected:

```text
cluster.id=CLUSTER-A
node.id=202
directory.id=BBBB
```

---

# 27. Start replacement C202 and allow catch-up

```bash
sudo systemctl start kafka-controller
```

Monitor:

```bash
watch -n 2 \
  "$KMQ --bootstrap-controller $BOOTSTRAP_CONTROLLER describe --replication"
```

Conceptually:

```text
old voter:
    202 + AAAA

replacement observer:
    202 + BBBB
```

Kafka can distinguish them because the directory IDs differ.

---

# 28. Add replacement voter identity

Once caught up:

```bash
$KMQ \
  --command-config /etc/kafka/controller.properties \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  add-controller
```

Then check:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --status
```

Inspect carefully which `(node.id, directory.id)` identities are present.

---

# 29. Remove old storage identity

Remove:

```text
202 + AAAA
```

not:

```text
202 + BBBB
```

Command:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  remove-controller \
  --controller-id 202 \
  --controller-directory-id AAAA
```

Verify:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --status
```

Final desired state:

```text
202 + BBBB
```

---

# 30. Never select a controller only by `node.id`

Dangerous:

```text
remove controller 202
```

without understanding the directory identity.

Always think:

```text
VOTER IDENTITY

node.id
+
directory.id
```

This is particularly important during disk replacement.

---

# 31. Controller has wrong `cluster.id`

Check:

```bash
grep '^cluster.id=' \
  /var/lib/kafka/kraft-metadata/meta.properties
```

Compare with:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --status
```

If:

```text
local cluster.id != active ClusterId
```

STOP.

Do not modify `meta.properties` manually.

Do not copy another controller's `meta.properties`.

Do not try to force the controller into the cluster by changing:

```text
cluster.id
```

The storage was formatted for another cluster or incorrectly provisioned.

Re-provision the controller correctly.

---

# 32. Controller has wrong `node.id`

Compare:

```bash
grep '^node.id=' \
  /var/lib/kafka/kraft-metadata/meta.properties
```

with:

```bash
grep '^node.id=' /etc/kafka/controller.properties
```

Example problematic condition:

```text
config:
node.id=201

meta.properties:
node.id=202
```

STOP.

Do not edit `meta.properties` manually.

Investigate why the wrong metadata directory or configuration was mounted.

---

# 33. `directory.id` changed unexpectedly

Compare current voter set:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --status
```

with local:

```bash
grep '^directory.id=' \
  "$META_DIR/meta.properties"
```

If voter set contains:

```text
201 + AAAA
```

but local storage says:

```text
201 + BBBB
```

you are dealing with a storage replacement, not an ordinary restart.

Follow the replacement procedure.

---

# 34. Bootstrap server unreachable

Remember:

```text
controller.quorum.bootstrap.servers
=
discovery addresses
```

You do not need the first listed controller specifically.

Try another known controller:

```bash
$KMQ \
  --bootstrap-controller "${C201}:9093" \
  describe --status
```

Then:

```bash
$KMQ \
  --bootstrap-controller "${C202}:9093" \
  describe --status
```

Check connectivity:

```bash
for h in "$C101" "$C102" "$C103" "$C201" "$C202"; do
    echo "=== $h ==="
    nc -vz "$h" 9093
done
```

A stale or unreachable bootstrap endpoint does not itself alter quorum membership.

---

# 35. Leader controller failed

Suppose:

```text
LeaderId = 101
```

and C101 fails.

With four other voters alive:

```text
102
103
201
202
```

you still have:

```text
4/5
```

The remaining quorum should elect a new leader automatically.

Observe:

```bash
watch -n 1 \
  "$KMQ --bootstrap-controller ${C201}:9093 describe --status"
```

You should eventually see:

```text
LeaderId: <new controller>
LeaderEpoch: <higher epoch>
```

Do **not** manually "promote" a controller.

KRaft performs leader election.

There is no normal operator command equivalent to:

```text
promote C201 to controller leader
```

---

# 36. No leader, but 3/5 controllers appear alive

First check reachability between controllers.

From C101:

```bash
for h in "$C102" "$C103" "$C201" "$C202"; do
    nc -vz "$h" 9093
done
```

Repeat from the other controller hosts.

Check DNS:

```bash
getent hosts "$C101"
getent hosts "$C102"
getent hosts "$C103"
getent hosts "$C201"
getent hosts "$C202"
```

Check system clock:

```bash
timedatectl
```

Check logs:

```bash
journalctl \
  -u kafka-controller \
  --since "15 min ago" \
  --no-pager \
  | grep -Ei \
  'raft|quorum|leader|vote|election|fetch|timeout|error'
```

Check current configuration:

```bash
grep -E \
  '^(node.id|controller.listener.names|listeners|controller.quorum.bootstrap.servers|listener.security.protocol.map)=' \
  /etc/kafka/controller.properties
```

The most common operational categories are:

```text
network partition

DNS problem

listener mismatch

TLS/SASL failure

bad controller endpoint

controller process unavailable

severe latency

storage problem
```

Do not modify membership until connectivity/election problems are understood.

---

# 37. Planned controller maintenance

Before taking C202 down:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --status
```

Then:

```bash
$KMQ \
  --bootstrap-controller "$BOOTSTRAP_CONTROLLER" \
  describe --replication
```

Verify at least:

```text
other 4 voters healthy

lag small

leader stable
```

Then:

```bash
sudo systemctl stop kafka-controller
```

For temporary maintenance there is no reason to remove C202 from membership.

After maintenance:

```bash
sudo systemctl start kafka-controller
```

Monitor catch-up:

```bash
watch -n 2 \
  "$KMQ --bootstrap-controller $BOOTSTRAP_CONTROLLER describe --replication"
```

---

# 38. Do not remove voters for short outages

Bad procedure:

```text
controller unavailable for 5 minutes
    |
    v
remove-controller
```

Normal procedure:

```text
controller unavailable temporarily
    |
    v
repair/restart controller
    |
    v
same node.id
same directory.id
    |
    v
catch up
```

Use membership changes when the membership itself needs to change.

---

# 39. DC2 complete failure — C201 and C202 lost

Topology:

```text
DC1:
101
102
103

DC2:
201 X
202 X
```

Survivors:

```text
3 / 5
```

Majority survives.

This is a normal quorum-degraded situation.

Check:

```bash
$KMQ \
  --bootstrap-controller "${C101}:9093" \
  describe --status
```

Then:

```bash
$KMQ \
  --bootstrap-controller "${C101}:9093" \
  describe --replication
```

If DC2 is expected to return, do not remove C201/C202 immediately.

When DC2 returns:

```text
C201 starts
C202 starts

same storage identities

metadata catch-up

quorum returns to 5/5
```

---

# 40. Permanent loss of C201 and C202

If DC2 is permanently destroyed but DC1 still has:

```text
101
102
103
```

you retain quorum.

You can replace C201/C202 using normal dynamic membership procedures.

For each lost controller:

```text
provision replacement

format with existing CLUSTER_ID

--no-initial-controllers

start

wait for catch-up

add-controller

remove stale old voter identity
```

Perform one membership change at a time.

---

# 41. CRITICAL INCIDENT — DC1 lost

Now the dangerous case:

```text
DC1:
101 X
102 X
103 X

DC2:
201
202
```

Current voters:

```text
101
102
103
201
202
```

Survivors:

```text
2 / 5
```

Required majority:

```text
3
```

Therefore:

```text
NO QUORUM
```

---

# 42. Hard safety gate after majority loss

When only C201 and C202 remain:

### DO NOT

```bash
kafka-storage.sh format ...
```

on C201 or C202.

Do not:

```bash
kafka-storage.sh format --standalone ...
```

Do not:

```bash
kafka-storage.sh random-uuid
```

and reinitialize the survivors.

Do not:

```bash
kafka-metadata-quorum.sh add-controller
```

expecting 2/5 to approve it.

Do not:

```bash
kafka-metadata-quorum.sh remove-controller
```

expecting the minority to redefine membership.

Do not delete:

```text
__cluster_metadata-0
```

Do not delete:

```text
quorum-state
```

Do not edit:

```text
meta.properties
```

Do not choose the controller with the largest LEO and immediately restart a new quorum.

---

# 43. Why normal membership commands stop working

The voter set is still conceptually:

```text
101
102
103
201
202
```

A committed membership update requires a valid functioning KRaft consensus process.

But only:

```text
201
202
```

remain.

Therefore:

```text
2 < majority of 5
```

The minority cannot safely say:

```text
"we remove 101, 102 and 103"
```

because those two surviving controllers do not constitute the old quorum majority.

---

# 44. First action after majority loss: freeze writes to metadata storage

Stop surviving controllers if necessary to prevent uncontrolled changes during investigation:

```bash
sudo systemctl stop kafka-controller
```

Verify:

```bash
ps -ef | grep '[k]afka'
```

The objective is:

```text
C201 metadata = preserved exactly

C202 metadata = preserved exactly
```

---

# 45. Make forensic copies

On C201:

```bash
sudo rsync \
  -aHAX \
  --numeric-ids \
  /var/lib/kafka/kraft-metadata/ \
  /recovery/c201-kraft-metadata/
```

On C202:

```bash
sudo rsync \
  -aHAX \
  --numeric-ids \
  /var/lib/kafka/kraft-metadata/ \
  /recovery/c202-kraft-metadata/
```

Even better, snapshot the underlying volume if your infrastructure supports it.

Perform investigation on copies.

Do not manipulate the only surviving metadata copies.

---

# 46. Hash the forensic copies

C201:

```bash
find /recovery/c201-kraft-metadata \
  -type f \
  -print0 \
  | sort -z \
  | xargs -0 sha256sum \
  > /recovery/c201.sha256
```

C202:

```bash
find /recovery/c202-kraft-metadata \
  -type f \
  -print0 \
  | sort -z \
  | xargs -0 sha256sum \
  > /recovery/c202.sha256
```

This gives you evidence that the copies used for analysis did not change.

---

# 47. Record identity of C201

```bash
cat \
  /recovery/c201-kraft-metadata/meta.properties
```

Record:

```text
cluster.id
node.id
directory.id
version
```

Expected:

```text
node.id=201
directory.id=UUID201
```

---

# 48. Record identity of C202

```bash
cat \
  /recovery/c202-kraft-metadata/meta.properties
```

Expected:

```text
node.id=202
directory.id=UUID202
```

Verify:

```text
C201 cluster.id == C202 cluster.id
```

If they differ:

```text
STOP
```

You may not even be looking at metadata from the same Kafka cluster.

---

# 49. Save `quorum-state`

C201:

```bash
cp \
  /recovery/c201-kraft-metadata/__cluster_metadata-0/quorum-state \
  /recovery/c201-quorum-state
```

C202:

```bash
cp \
  /recovery/c202-kraft-metadata/__cluster_metadata-0/quorum-state \
  /recovery/c202-quorum-state
```

Treat this as supporting Raft evidence.

Do not treat it as the authoritative voter membership database.

---

# 50. List metadata files on both survivors

```bash
find \
  /recovery/c201-kraft-metadata/__cluster_metadata-0 \
  -maxdepth 1 \
  -type f \
  -printf '%f %s\n' \
  | sort \
  > /recovery/c201-files.txt
```

And:

```bash
find \
  /recovery/c202-kraft-metadata/__cluster_metadata-0 \
  -maxdepth 1 \
  -type f \
  -printf '%f %s\n' \
  | sort \
  > /recovery/c202-files.txt
```

Compare:

```bash
diff -u \
  /recovery/c201-files.txt \
  /recovery/c202-files.txt
```

---

# 51. Decode all surviving metadata log segments

C201:

```bash
mkdir -p /recovery/c201-decoded
```

Then:

```bash
for f in \
  /recovery/c201-kraft-metadata/__cluster_metadata-0/*.log
do
    base="$(basename "$f")"

    "$KDUMP" \
      --cluster-metadata-decoder \
      --files "$f" \
      > "/recovery/c201-decoded/${base}.txt"
done
```

C202:

```bash
mkdir -p /recovery/c202-decoded
```

```bash
for f in \
  /recovery/c202-kraft-metadata/__cluster_metadata-0/*.log
do
    base="$(basename "$f")"

    "$KDUMP" \
      --cluster-metadata-decoder \
      --files "$f" \
      > "/recovery/c202-decoded/${base}.txt"
done
```

---

# 52. Find all visible VotersRecord entries

C201:

```bash
grep \
  -Rni \
  'VotersRecord' \
  /recovery/c201-decoded
```

C202:

```bash
grep \
  -Rni \
  'VotersRecord' \
  /recovery/c202-decoded
```

Compare the voter history.

For example:

```text
C201:

VotersRecord A
101 102 103 201 202


C202:

VotersRecord A
101 102 103 201 202
```

or perhaps:

```text
C201:
latest visible set =
101 102 103 201 203

C202:
latest visible set =
101 102 103 201 202
```

The latter requires detailed investigation.

---

# 53. Decode snapshots as well

Do **not** inspect only `.log` segments.

List snapshots:

```bash
find \
  /recovery/c201-kraft-metadata/__cluster_metadata-0 \
  -name '*.checkpoint' \
  -printf '%p\n' \
  | sort
```

For each relevant metadata snapshot:

```bash
"$KDUMP" \
  --cluster-metadata-decoder \
  --files "$SNAPSHOT"
```

Repeat for C202.

Remember:

```text
effective local metadata state
=
snapshot
+
records following snapshot
```

---

# 54. Compare the surviving histories

You now need to establish:

```text
C201:

cluster.id
directory.id
snapshot offset
snapshot epoch
log segment ranges
latest record offset
leader epochs
visible VotersRecords


C202:

cluster.id
directory.id
snapshot offset
snapshot epoch
log segment ranges
latest record offset
leader epochs
visible VotersRecords
```

Conceptually create:

```text
             C201                 C202

ClusterId    A                    A

DirectoryId  UUID201              UUID202

Snapshot     O1/E1                O2/E2

Last log     LEO1                 LEO2

Voters       ...                  ...

Epoch        ...                  ...
```

---

# 55. Do not use this unsafe rule

Never use:

```text
if C201 LEO > C202 LEO
then C201 = safe seed
```

This is unsafe.

Possible situation:

```text
C201:

LEO = 5005

C202:

LEO = 5000

original HighWatermark:
5000
```

Offsets:

```text
5001-5005
```

on C201 may have been uncommitted.

---

# 56. There is another opposite danger

Suppose both surviving DC2 controllers have:

```text
LEO = 10000
```

but before DC1 failed the three DC1 controllers committed:

```text
10001
10002
10003
```

to:

```text
C101
C102
C103
```

Those three constituted a majority:

```text
3 / 5
```

Therefore those records could have been committed even if C201 and C202 never received them.

After DC1 disappears:

```text
C201 and C202 cannot prove
that offset 10000 was the final committed offset.
```

This is why minority recovery cannot guarantee RPO=0 solely from surviving minority logs.

---

# 57. Majority-loss decision

The operational question is not:

```text
Which survivor has the biggest log?
```

It is:

```text
Can we prove the last metadata record
that was committed by the original quorum?
```

If:

```text
YES
```

you may be able to construct a controlled recovery process around that known state.

If:

```text
NO
```

then recovery must explicitly acknowledge possible metadata loss.

---

# 58. Why `--standalone` is not a routine DR command

This command:

```bash
kafka-storage.sh format \
  --cluster-id "$CLUSTER_ID" \
  --standalone \
  --config controller.properties
```

creates a new bootstrap snapshot and establishes the formatted controller as a single-voter quorum.

That makes it appropriate for **initial cluster bootstrapping**.

It is not a normal command for:

```text
"three of five controllers disappeared,
so make one survivor leader."
```

Formatting surviving metadata would overwrite/reinitialize critical state and can destroy evidence required to determine what was committed.

Therefore it is forbidden in the initial majority-loss response.

---

# 59. `controller.quorum.bootstrap.servers` cannot repair majority loss

Changing:

```properties
controller.quorum.bootstrap.servers=
c201.dc2.example.com:9093,
c202.dc2.example.com:9093
```

does not redefine:

```text
CurrentVoters
```

from:

```text
101 102 103 201 202
```

to:

```text
201 202
```

Bootstrap servers answer:

```text
WHERE CAN I TRY TO FIND QUORUM?
```

They do not answer:

```text
WHO IS ALLOWED TO VOTE?
```

Therefore bootstrap configuration is not an emergency quorum override.

---

# 60. Never manually edit VotersRecord

Do not attempt:

```text
open metadata log

change voter IDs

remove C101/C102/C103

save file
```

KRaft metadata is an ordered replicated log with checksums, offsets, epochs, snapshots and consensus semantics.

Manual byte-level modification is not an operational membership mechanism.

---

# 61. Never copy `meta.properties` between controllers

Bad:

```bash
scp \
  c201:/var/lib/kafka/kraft-metadata/meta.properties \
  c202:/var/lib/kafka/kraft-metadata/meta.properties
```

Why:

```text
C201 identity:

node.id=201
directory.id=UUID201

C202 identity:

node.id=202
directory.id=UUID202
```

They must remain distinct.

---

# 62. Never copy only `quorum-state` to another controller

Bad:

```bash
cp c201/quorum-state c202/quorum-state
```

`quorum-state` belongs to the local Raft participant.

It is not a portable membership configuration.

---

# 63. Do not reconstruct membership from bootstrap configuration

Wrong inference:

```properties
controller.quorum.bootstrap.servers=
c201:9093,c202:9093
```

therefore:

```text
voters = 201,202
```

This is incorrect.

The authoritative dynamic voter state comes from KRaft metadata.

---

# 64. Operational command matrix

| Operation | Primary command |
|---|---|
| Quorum summary | `kafka-metadata-quorum.sh ... describe --status` |
| Replica state | `kafka-metadata-quorum.sh ... describe --replication` |
| Check dynamic quorum feature | `kafka-features.sh ... describe` |
| Format new controller joining cluster | `kafka-storage.sh format ... --no-initial-controllers` |
| Add voter | `kafka-metadata-quorum.sh ... add-controller` |
| Remove voter | `kafka-metadata-quorum.sh ... remove-controller` |
| Inspect `meta.properties` | `cat/grep meta.properties` |
| Decode metadata log | `kafka-dump-log.sh --cluster-metadata-decoder` |
| Decode snapshot | `kafka-dump-log.sh --cluster-metadata-decoder` |
| Inspect metadata image | `kafka-metadata-shell.sh --snapshot ...` |
| Temporary controller restart | service manager / `kafka-server-start.sh` |
| Majority lost | **no normal add/remove command** |

---

# 65. Incident decision tree

```text
             KRaft controller incident
                       |
                       v
             describe --status
                       |
                       v
              Majority available?
                 /          \
               YES           NO
                |             |
                v             v
          normal Kafka      STOP normal
            recovery        membership changes
                |             |
                |             v
                |        preserve metadata
                |             |
                |             v
                |       clone C201/C202
                |             |
                |             v
                |       inspect identity
                |             |
                |             v
                |       inspect snapshots
                |             |
                |             v
                |       inspect log history
                |             |
                |             v
                |       establish committed
                |       recovery boundary?
                |          /       \
                |        YES        NO
                |         |          |
                |         v          v
                |     controlled   possible
                |      recovery    metadata loss
                |
                v
            verify quorum
```

---

# 66. Fast incident checklist

### Step 1

```bash
kafka-metadata-quorum.sh \
  --bootstrap-controller c201.dc2.example.com:9093 \
  describe --status
```

### Step 2

```bash
kafka-metadata-quorum.sh \
  --bootstrap-controller c201.dc2.example.com:9093 \
  describe --replication
```

### Step 3

Determine:

```text
How many voters?

How many alive?

Is LeaderId known?

What is LeaderEpoch?

What is HighWatermark?

Which directory IDs are voters?
```

### Step 4

If majority exists:

```text
repair
restart
catch up
add/remove/replace if necessary
```

### Step 5

If majority does not exist:

```text
DO NOT FORMAT

DO NOT CHANGE MEMBERSHIP

DO NOT DELETE METADATA

STOP SURVIVORS IF NEEDED

COPY METADATA

HASH COPIES

COMPARE C201/C202

DECODE SNAPSHOTS

DECODE LOGS

IDENTIFY VotersRecord HISTORY

DETERMINE WHETHER COMMITTED
RECOVERY BOUNDARY IS PROVABLE
```

---

# 67. Commands I would put on the first page of the production runbook

```bash
# 1. Quorum status

bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c101.dc1.example.com:9093 \
  describe --status
```

```bash
# 2. Replication status

bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c101.dc1.example.com:9093 \
  describe --replication
```

```bash
# 3. Verify KIP-853 dynamic quorum

bin/kafka-features.sh \
  --bootstrap-controller c101.dc1.example.com:9093 \
  describe
```

```bash
# 4. Inspect controller identity

grep -E \
  '^(cluster.id|node.id|directory.id|version)=' \
  /var/lib/kafka/kraft-metadata/meta.properties
```

```bash
# 5. Decode metadata segment

bin/kafka-dump-log.sh \
  --cluster-metadata-decoder \
  --files \
  /var/lib/kafka/kraft-metadata/__cluster_metadata-0/<segment>.log
```

```bash
# 6. Decode metadata snapshot

bin/kafka-dump-log.sh \
  --cluster-metadata-decoder \
  --files \
  /var/lib/kafka/kraft-metadata/__cluster_metadata-0/<snapshot>.checkpoint
```

```bash
# 7. Format NEW controller joining existing cluster

bin/kafka-storage.sh format \
  --cluster-id "$CLUSTER_ID" \
  --config /etc/kafka/controller.properties \
  --no-initial-controllers
```

```bash
# 8. Add caught-up controller

bin/kafka-metadata-quorum.sh \
  --command-config /etc/kafka/controller.properties \
  --bootstrap-controller c101.dc1.example.com:9093 \
  add-controller
```

```bash
# 9. Remove voter

bin/kafka-metadata-quorum.sh \
  --bootstrap-controller c101.dc1.example.com:9093 \
  remove-controller \
  --controller-id 202 \
  --controller-directory-id "$DIRECTORY_ID"
```

---

# 68. Golden rule

The safest operational model is:

```text
               NORMAL OPERATIONS

     quorum majority still exists
                  |
                  v
       Kafka consensus decides
                  |
                  v
       add/remove voter safely


               DISASTER RECOVERY

        quorum majority is lost
                  |
                  v
       Kafka consensus cannot decide
                  |
                  v
         preserve surviving state
                  |
                  v
       determine what was committed
                  |
                  v
       only then design reconstruction
```

And most importantly:

```text
controller.quorum.bootstrap.servers
does not recreate quorum.

node.id alone
does not identify a voter incarnation.

largest LogEndOffset
does not prove committed authority.

quorum-state
does not define dynamic membership.

VotersRecord / snapshot state
must be interpreted together with
Raft commit semantics.
```