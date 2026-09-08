# Architecture Opinion: Why KRaft Quorum-State Backup Is Not a Viable DR Primitive

**Audience:** Platform / Infrastructure Architects
**Scope:** Confluent Platform 8.3.x EE / Apache Kafka 4.3.x, KRaft (controller) mode
**Topic:** Feasibility and risks of backing up KRaft quorum state (static configuration + runtime Raft state) as a disaster-recovery mechanism, and the resulting exposure to metadata and broker-data loss.

---

## 1. Executive summary

A safe, generic, online backup-and-restore of KRaft quorum state is **not a supported or reliable disaster-recovery primitive.** The quorum is distributed Raft state, not a static configuration bundle. A quorum "backup" assembled from static node identity plus runtime Raft artifacts is timeline-dependent, non-atomic across controllers, and on restore can produce a divergent metadata history that either gets discarded by Raft (making the backup useless) or overwrites newer committed metadata (causing data loss). Because broker data is mapped to metadata via topic IDs, partition assignments, and partition leader epochs, losing or corrupting the control-plane image can render otherwise-intact broker volumes logically inaccessible — and in some cases force truncation that destroys data.

The supported DR posture for KRaft is therefore **resilience through sufficient surviving voters** (topology that tolerates region loss) and, after quorum loss, **rebuild from the best surviving seed plus reconciliation against an external source of truth.** There is no "restore the quorum from a backup file" path.

---

## 2. What "quorum state" actually is

KRaft quorum state is not a single artifact. It is two categories of data that must remain mutually consistent:

**Static identity / configuration**
- `meta.properties`: `cluster.id`, `node.id`, `directory.id`
- `process.roles`, `listeners`, `controller.listener.names`
- `controller.quorum.bootstrap.servers` (dynamic quorum) or `controller.quorum.voters` (static quorum)

**Runtime Raft state**
- The metadata log `__cluster_metadata-0` (Raft log segments + internal snapshots)
- High Watermark (HW), Leader Epoch, Log End Offset (LEO)
- The current voter set, current leader, and member roles (leader / candidate / follower / observer)
- The in-memory `MetadataImage` (reconstructed from the log and snapshots), covering topics, partitions, configs, ACL/SCRAM, broker registrations, feature levels, and the quorum's own membership.

The critical property: **the runtime state is only meaningful relative to the quorum's timeline** — the leader epoch, the voter set, and the committed prefix at the moment of capture. It is not a portable, immutable bundle that can be zipped up and restored later into an arbitrary cluster state.

---

## 3. Why a generic quorum backup is not realizable

### 3.1 No atomic, cluster-wide snapshot primitive

KRaft provides no atomic, cluster-wide export/restore of the full quorum state. Each controller persists its on-disk state independently. Any file-level backup therefore captures different controllers at slightly different instants, yielding an **inconsistent global state** on restore — HW from one node, epoch from another, voter set from a third, all from non-coincident moments.

### 3.2 Metadata snapshots are not backup artifacts

The `*.checkpoint` snapshot files inside `__cluster_metadata-0` are **internal Raft/metadata snapshots** used for catch-up and in-timeline recovery. They are not portable "restore the quorum later" artifacts. `kafka-metadata-shell` can inspect metadata; it is not a supported full-fidelity export/restore mechanism for quorum state. Treating these as a backup format is a category error.

### 3.3 Restore correctness depends on the Raft timeline

The correctness of a restored log depends on the leader epoch, offset, voter-set history, and committed prefix — all of which are only meaningful relative to the quorum's history. A file copy of one node's log does **not** prove what the globally committed prefix was at the time of capture. This is precisely why the seed-selection rule in the official quorum-loss recovery is "highest epoch, then largest LEO" — a longer log with a lower epoch may be a stale, divergent branch that never held committed entries.

---

## 4. Restore failure modes

If one nevertheless attempts to restore a mix of static configuration and runtime state, the failure modes are concrete:

- **Divergent branch.** A backup from epoch E1 restored into a cluster that has advanced to E2 will, under normal Raft, be truncated to match the current leader (backup useless). If forced, it can overwrite newer committed metadata — **metadata loss.**
- **Stale voter set.** In dynamic KRaft the voter set is replicated Raft state. Restoring an older voter set creates divergence between members and can produce split-brain if the stale set of nodes can still contact each other.
- **Identity mismatch.** `meta.properties` (`cluster.id`/`node.id`/`directory.id`) must be consistent with the log and voter set. A partial restore (e.g., the log without matching `meta.properties`) causes corruption; Kafka refuses to start or behaves undefined.

### What is actually possible

A **cold, coordinated snapshot of all controller volumes while KRaft is fully stopped** can be valid — but only as a rollback to that exact point in time (e.g., a lab checkpoint, or a rollback point before an irreversible `force-standalone`). This is not equivalent to a portable "restore the quorum later" backup in a cluster whose Raft timeline or broker data has since advanced.

---

## 5. Impact on broker data

This is the most consequential chain of causation. **Metadata is the map to the bytes on broker disks.** `MetadataImage` holds the topic IDs, partition assignments, configurations, ACL/SCRAM, broker registrations, and partition state. Broker data (topic log segments on `log.dirs`) is bound to this map through:

- **Topic IDs (UUIDs)** — KRaft operates on topic IDs; broker segments are addressed by topic ID.
- **Partition IDs and assignments** — which broker holds which replica.
- **Partition leader epochs** — stored both in metadata and in broker partition log segments.

If restored metadata does not match the broker data:

- **Data remains physically on disk** but the broker lacks the correct control-plane references to serve it → the data becomes **logically inaccessible / orphaned.** The bytes are not always deleted; the failure is loss of the references and assignments needed to serve them.
- In some cases, **reconciliation or truncation** on partition-leader-epoch mismatch can cause **actual data destruction** — the broker brings its partition log to the shorter length indicated by the metadata.

In short: the broker volumes are the books in a warehouse; the metadata is the inventory that says which book is where and what it means. Lose the inventory and the books still exist but cannot be used; restore a stale inventory and some books become unusable or are "corrected" (truncated) to an inconsistent entry.

---

## 6. Why surviving-quorum backup cannot guarantee RPO=0

In the loss-of-majority scenario (e.g., DC1 with 3 of 5 voters lost), this is the cleanest argument:

- A record could have been committed by **C101+C102+C103** (the DC1 majority) and **never replicated to C201 or C202.**
- Such a record was committed truth of the cluster, yet physically existed only on the lost controllers.
- **No backup of C201/C202 can reconstruct it**, because it was never replicated to the survivors. A backup of surviving quorum state contains only what the survivors held.

No backup technology addresses this, because the "backup" of a survivor is not a copy of the whole — it is a copy of what the survivor possessed. This is a direct consequence of Raft's commit rule (majority, not all) combined with the loss of the majority side.

---

## 7. Recommended architecture posture

Given the above, the platform DR strategy for KRaft should be:

1. **Topology first — design to tolerate region loss.** A 3-voter-in-DC1 + 2-voter-in-DC2 layout cannot survive total DC1 loss because DC1 holds the majority. Prefer three failure domains (e.g., 2+2+1) so that loss of any single domain leaves at least a majority. Resilience is achieved by having enough surviving voters, not by backing up the quorum.

2. **Treat a cold, coordinated controller-volume snapshot as a rollback artifact only**, not as a portable restore mechanism. It is useful as a forensic/rollback point before an irreversible operation (e.g., `force-standalone`), not as a general "quorum restore."

3. **Maintain an external source of truth for metadata.** Topic/partition inventory, configurations, ACLs, and SCRAM should be declared in IaC (Terraform/Ansible), GitOps, a CMDB, or an application topic catalog. After any quorum recovery, reconcile `MetadataImage` against this baseline to detect lost committed entries that existed only on the lost majority.

4. **After quorum loss, follow the vendor recovery model: rebuild from the best surviving seed** (highest epoch, then largest LEO), rejoin non-seeds as observers, promote via `add-controller`, and engage Confluent Support for the irreversible `force-standalone` step. Do not attempt to "restore a backup" of quorum state.

5. **Decouple broker-data survivability from metadata survivability in DR planning.** Broker topic data may survive on volumes even when control-plane metadata is lost; conversely, restored/stale metadata can render surviving data inaccessible or force truncation. Treat broker-data recovery as a separate workstream that depends on a correct, reconciled metadata image.

---

## 8. Bottom line

Backing up KRaft quorum state (static config + runtime Raft artifacts) as a general DR mechanism is not technically sound: the runtime state is timeline-dependent and non-atomic across controllers, restore can create divergent metadata branches that overwrite committed truth, and metadata is the indirection layer through which broker data is addressed. The supported path is resilience by topology and, after loss, rebuild-from-surviving-seed plus external reconciliation — not quorum-state restore from backup. In a majority-loss scenario, no backup of the survivors can recover committed entries that existed only on the lost majority, which is why RPO=0 cannot be guaranteed for metadata in that case.
