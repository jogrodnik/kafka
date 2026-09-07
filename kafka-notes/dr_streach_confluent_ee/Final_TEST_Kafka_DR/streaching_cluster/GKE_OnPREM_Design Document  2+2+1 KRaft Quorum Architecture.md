# Design Document: 2+2+1 KRaft Quorum Architecture (DC1 + DC2 + GKE Witness)

**Status:** Draft for internal review
**Scope:** Apache Kafka / Confluent Platform KRaft metadata quorum, deployed across two full data centers plus one lightweight Kubernetes-hosted witness controller
**Prepared for:** Internal escalation and architecture sign-off

---

## 1. Purpose and Scope

This document specifies the target architecture, network requirements, and validation rules for a **2+2+1 KRaft controller topology**: two full, broker-carrying data centers (**DC1**, **DC2**) plus one minimal, controller-only "0.5" site hosted on Google Kubernetes Engine (**GKE**). It supersedes the earlier "1.5 DC" proposal (single full site + GKE witness only), which does not tolerate the loss of the one full site.

This is a **controller/metadata-quorum design**, not a full data-plane disaster-recovery design. Section 9 explicitly separates the two concerns.

## 2. Problem Statement

The starting constraint was: only two physical/cloud locations are available (an on-premises site and a GCP/GKE footprint), and the initial proposal placed all Kafka brokers in a single on-premises site with a lightweight controller in GKE. That design ("1.5 DC") solves nothing for a full-site outage: losing the only broker-carrying site removes both the data and the controller majority (2 of 3 remaining in GKE alone is a minority).

The corrected requirement is the topology Confluent documents natively for KRaft: **two full sites with equal broker and controller counts, plus a third minimal site that participates only in the controller quorum** ([Confluent — Multi-Region Architectures](https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region-architectures.html)). This requires provisioning an actual second full site (DC2) — the GKE footprint alone cannot substitute for it.

## 3. Proposed Architecture

| Site | Role | KRaft controllers | Brokers |
|---|---|---|---|
| DC1 | Full site | 2 | Yes — full replica count |
| DC2 | Full site (to be provisioned/confirmed) | 2 | Yes — full replica count, equal to DC1 |
| GKE (Site 0.5) | Controller-only, no data plane | 1 | No |

Total controller quorum: **5 voters**, majority = **3**. This is the reference 5-node pattern Confluent documents for the 2.5 DC model ([Confluent — Multi-Region Architectures](https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region-architectures.html); [Confluent — Multi-Region Clusters](https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region.html)). Confluent's own documentation does not use the term "voter" or "witness" for the fifth node — it is described simply as a controller node without a broker role, participating in the same Raft quorum as the others.

**Open item:** DC2's physical location is not yet defined in this proposal. It must be an independent power and network domain from DC1 (otherwise the "two full sites" premise collapses back into a single-site risk).

## 4. Quorum Math and Failure Scenarios

| Scenario | Voters remaining | Quorum status (majority = 3 of 5) | Data-plane impact |
|---|---|---|---|
| Normal operation | 5 of 5 | Holds | Full |
| DC1 lost | 3 of 5 (2×DC2 + 1×GKE) | Holds | Depends on broker replication factor — see Section 9 |
| DC2 lost | 3 of 5 (2×DC1 + 1×GKE) | Holds | Same, mirrored |
| GKE (0.5) lost | 4 of 5 (2×DC1 + 2×DC2) | Holds | None — GKE never carries broker data |
| DC1 + GKE lost simultaneously | 2 of 5 | **Fails** — manual intervention required | Outage or degraded, depending on DC2-only capacity |
| DC2 + GKE lost simultaneously | 2 of 5 | **Fails** — manual intervention required | Same, mirrored |

The defining property of 2+2+1 versus a plain 2-DC layout is that **losing any single site — including either full DC — still leaves a controller majority**. This is the specific failure mode the original 1.5 DC proposal did not cover.

## 5. Network Requirements on Boundary Connections

| Link | Traffic carried | RTT requirement | Bandwidth profile | Connectivity type | Source |
|---|---|---|---|---|---|
| **DC1 ↔ DC2** | Broker data replication (`acks=all`) + controller Raft traffic | Ideally **< 50 ms**; hard ceiling **< 100 ms** | High — scales with produce/replication throughput | Dedicated private circuit (leased line, dark fiber, or equivalent), redundant physical path recommended | [AutoMQ — Kafka Stretch Clusters](https://www.automq.com/blog/kafka-stretch-clusters-multi-datacenter-architecture); [Confluent — Multi-Region Architectures](https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region-architectures.html) |
| **DC1 ↔ GKE (0.5)** | Controller-only Raft traffic (heartbeats, metadata log replication), port `9074` | Hard ceiling **< 100 ms** | Low — small control-plane traffic only, no broker data crosses this link | Dedicated/Partner Interconnect, not public internet or shared VPN; mTLS mandatory | [Confluent — Multi-Region Architectures](https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region-architectures.html); [GCP — Networking for hybrid and multi-cloud](https://docs.cloud.google.com/architecture/network-hybrid-multicloud); [Confluent — Configure Dynamic KRaft Quorum](https://docs.confluent.io/operator/current/co-configure-kraft-dynamic-quorum.html) |
| **DC2 ↔ GKE (0.5)** | Same as DC1 ↔ GKE | Hard ceiling **< 100 ms** | Low | Same as above | Same |

Reference values for context (not requirements, background only):
- Rook-Ceph's stretch-cluster pattern recommends **< 10 ms** for storage replication between its two main sites — a stricter analogue, not a Kafka-specific figure ([OneUptime — Rook-Ceph stretch cluster](https://oneuptime.com/blog/post/2026-03-31-rook-deploy-stretch-cluster-two-datacenters/view)).
- If the same Kubernetes control plane (etcd) were ever stretched across sites instead of keeping per-site clusters, Red Hat requires etcd peer RTT **< 100 ms** and explicitly advises against this pattern for production ([Red Hat — Guidance for clusters that span data centers](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/etcd/etcd-guidance-span)). This project does not stretch the Kubernetes control plane (see Section 6, Option A).
- If GKE's Hong Kong region (`asia-east2`) is used for Site 0.5, GCP's own inter-region VM-to-VM measurements from Hong Kong were: Taiwan 18.4 ms, Singapore 35.0 ms, Tokyo 48.4 ms ([iKala — GCP Hong Kong region](https://ikala.cloud/blog/infrastructure/gcp-hk-region-asia-east-2)). **Caveat:** these are GCP-internal VM-to-VM figures from 2018, not on-premises-to-GCP measurements — actual RTT from DC1/DC2 to the chosen GCP region must be measured independently before committing to a region.

A single link per pair is a single point of failure for that boundary — a redundant physical path per connection is recommended, particularly for DC1↔DC2 given it carries data-plane traffic.

## 6. Kubernetes Implementation Options

Two implementation patterns exist; pick one explicitly.

| Option | Description | Source |
|---|---|---|
| **A — Three independent Kubernetes clusters (recommended)** | One small/independent K8s cluster per site; each runs its own `KRaftController` resource; controllers from different clusters join one Raft ensemble over the network. This is the pattern Confluent for Kubernetes (CFK) implements natively for Multi-Region Clusters, and it requires **at least three separate Kubernetes clusters**. | [Confluent for Kubernetes — Multi-Region Deployment](https://docs.confluent.io/operator/current/co-multi-region.html); [Confluent Kubernetes Examples — hybrid multi-region-clusters](https://github.com/confluentinc/confluent-kubernetes-examples/blob/master/hybrid/multi-region-clusters/README.md) |
| **B — One Kubernetes cluster stretched across all three sites** | Single K8s control plane (etcd) spans DC1, DC2, and GKE; topology enforced via `topology.kubernetes.io/zone` labels and `topologySpreadConstraints`/`podAntiAffinity`. This is the Rook-Ceph stretch-cluster pattern. | [Kubernetes — Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/); [OneUptime — Rook-Ceph stretch cluster](https://oneuptime.com/blog/post/2026-03-31-rook-deploy-stretch-cluster-two-datacenters/view) |

**Recommendation: Option A.** Red Hat explicitly advises against stretching a single Kubernetes control plane across data centers in production — doing so turns three independent failure domains into one stretched domain and is not a substitute for a real DR plan ([Red Hat — Guidance for clusters that span data centers](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/etcd/etcd-guidance-span)). Keeping Kubernetes control planes per-site and letting **KRaft alone** own the quorum decision matches the CFK-native pattern and avoids that risk.

**Documented gap:** no vendor source in this research (Confluent, CFK, AutoMQ) specifies a minimum infrastructure footprint for Site 0.5 — e.g., whether a single-node cluster is sufficient versus a full HA control plane. The conclusion below is an inference from the Rook-Ceph arbiter pattern, not a confirmed Confluent/CFK requirement:
- Site 0.5 likely does not need a highly-available Kubernetes control plane of its own; a minimal (even single-node) cluster is consistent with how Rook-Ceph treats its arbiter node — one additional node, no storage/broker role ([OneUptime — Rook-Ceph stretch cluster](https://oneuptime.com/blog/post/2026-03-31-rook-deploy-stretch-cluster-two-datacenters/view)).

## 7. GKE-Specific Configuration for Site 0.5

| Area | Recommendation | Source |
|---|---|---|
| Node type | Standard node pool, **never** Spot/Preemptible VMs — Spot VMs have no availability guarantee and reclamation is not covered by `PodDisruptionBudget`; losing the witness controller at a random moment (potentially during a real DC outage) defeats the purpose | [GCP — Spot VMs in GKE](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/spot-vms) |
| Cluster mode | **GKE Standard**, not Autopilot — Autopilot is regional-by-default and spreads across 3 zones automatically with limited control over node pool/machine type; the witness controller needs a pinned node pool, zone, taints/tolerations for deterministic placement | [GCP — Autopilot vs Standard feature comparison](https://docs.cloud.google.com/kubernetes-engine/docs/resources/autopilot-standard-feature-comparison) |
| Storage | Persistent Disk SSD (`pd-ssd`) for the metadata log — avoid higher-latency network storage classes | Inferred from general KRaft I/O requirements; not independently sourced in this research pass |
| Region choice | Trade-off between lowest latency (same city as DC1/DC2, e.g. `asia-east2` if on-prem is in Hong Kong) versus geographic independence (e.g. Taiwan/Singapore, still under the 100 ms ceiling) | [iKala — GCP Hong Kong region](https://ikala.cloud/blog/infrastructure/gcp-hk-region-asia-east-2) |
| Connectivity | Dedicated/Partner Interconnect; example topology with 4 connections across 2 metro areas reaches 99.99% SLA; HA VPN is a cheaper fallback but its jitter/stability for Raft traffic should be validated before use | [GCP — Networking for hybrid and multi-cloud](https://docs.cloud.google.com/architecture/network-hybrid-multicloud) |
| Load balancing / DNS | GKE has native `LoadBalancer` support; on-premises sites may need MetalLB or equivalent; controller addresses must resolve across all three sites via `external-dns` or equivalent | [Confluent for Kubernetes — Multi-Region Deployment](https://docs.confluent.io/operator/current/co-multi-region.html) |
| Security | mTLS between controllers/brokers across sites is effectively mandatory since traffic crosses a public cloud provider boundary; restrict firewall rules for port `9074` and replication ports to the Interconnect/VPN IP ranges only, never open internet | Confluent for Kubernetes documentation for the mTLS point; firewall scoping is a general security best practice, not independently sourced |

## 8. Confluent/CFK Version Requirements

| Requirement | Version |
|---|---|
| Dynamic KRaft quorum support | Confluent Platform **7.9+**, recommended **7.9.6+** |
| CFK operator | **3.2 or newer** |
| Greenfield Multi-Region Cluster deployments | 7.9.6+, 8.0.5+, 8.1.2+, or 8.2.1+ |
| Auto-Join Quorum (simplifies adding/promoting controllers) | 8.2+ |
| Cross-cluster listener advertisement (`listeners.advertisedListenersEnabled: true`) | Required on CFK ≥ 3.2 for multi-Kubernetes-cluster deployments — otherwise the KRaft leader advertises an internal endpoint unreachable from controllers in other clusters |

**Known defective patch versions — do not deploy:** `7.9.0–7.9.5`, `8.0.4`, `8.1.1`, `8.2.0`.

Source: [Confluent — Configure Dynamic KRaft Quorum](https://docs.confluent.io/operator/current/co-configure-kraft-dynamic-quorum.html); CFK multi-region configuration details from [Confluent for Kubernetes — Multi-Region Deployment](https://docs.confluent.io/operator/current/co-multi-region.html).

Additional CFK identity requirements for a multi-cluster KRaft ensemble:
- A **single, identical `clusterID`** must be set explicitly across all three Kubernetes clusters — CFK generates a unique ID per cluster by default, which breaks quorum formation if left unset.
- `nodeId = platform.confluent.io/broker-id-offset + podId`, with a distinct `broker-id-offset` annotation per site to avoid ID collisions.

Source: [Confluent for Kubernetes — Multi-Region Deployment](https://docs.confluent.io/operator/current/co-multi-region.html).

## 9. Data-Plane Considerations (Separate from Controller Quorum)

Controller quorum health and broker data availability are **independent guarantees**. Achieving 2+2+1 controller resilience does **not** automatically make broker data resilient to a full-site loss — that depends entirely on topic replication factor and placement.

For an equivalent **RPO = 0 on the data plane**, Confluent/SoftwareMill document an observer-based pattern: 2 synchronous replicas in each of DC1/DC2 plus an observer, `min.insync.replicas = 3`, with synchronous replication between the two full sites ([SoftwareMill — ISR/RF in Confluent stretched cluster 2.5](https://softwaremill.com/understanding-in-sync-replicas-and-replication-factor-in-confluent-stretched-cluster-2-5/)). This is a separate configuration decision from controller placement — an organization could in principle have RPO = 0 on data while accepting non-zero RPO on metadata, or vice versa, depending on how replication is configured.

**Recommendation for the escalation:** state explicitly that the 2+2+1 controller topology alone does not guarantee zero data loss or continued broker availability on a full-DC outage unless replication factor is also configured to span DC1 and DC2.

## 10. Pre-Production Validation Rules

| # | Category | Validation rule |
|---|---|---|
| 1 | Topology | Confirm DC2 is provisioned as an independent power/network domain from DC1 (not a second room in the same facility) |
| 2 | Topology | Confirm 2 controllers in DC1, 2 in DC2, 1 in GKE — total 5 voters |
| 3 | Topology | Confirm equal broker replica counts in DC1 and DC2 |
| 4 | Network | Measure actual RTT DC1↔DC2 from real infrastructure; confirm < 50 ms target, hard fail above 100 ms |
| 5 | Network | Measure actual RTT DC1↔GKE and DC2↔GKE from real infrastructure; hard fail above 100 ms |
| 6 | Network | Confirm all three inter-site links use dedicated/private connectivity (Interconnect or equivalent), not public internet or shared VPN |
| 7 | Network | Confirm redundant physical path exists for DC1↔DC2 at minimum |
| 8 | Kubernetes | Confirm Option A (3 independent K8s clusters) is implemented, not a single stretched control plane |
| 9 | Kubernetes | Confirm GKE node pool for Site 0.5 uses Standard mode, non-Spot/non-Preemptible VMs |
| 10 | Kubernetes | Confirm `pd-ssd` storage class is used for the GKE controller's metadata log |
| 11 | Configuration | Confirm identical `clusterID` across all three Kubernetes clusters |
| 12 | Configuration | Confirm distinct `broker-id-offset` per site, no `nodeId` collisions |
| 13 | Configuration | Confirm `listeners.advertisedListenersEnabled: true` set on all CFK-managed controllers |
| 14 | Version | Confirm Confluent Platform ≥ 7.9.6 (or another version from the greenfield MRC list) and CFK ≥ 3.2 |
| 15 | Version | Confirm none of the defective patch versions (7.9.0–7.9.5, 8.0.4, 8.1.1, 8.2.0) are in use |
| 16 | Security | Confirm mTLS is enforced on all cross-site controller/broker traffic |
| 17 | Security | Confirm firewall rules restrict port 9074 and replication ports to Interconnect/VPN IP ranges only |
| 18 | Data plane | Confirm topic replication factor and `min.insync.replicas` configuration explicitly for the desired data-loss tolerance (this is independent of controller quorum, see Section 9) |
| 19 | Testing | Simulate loss of DC1, loss of DC2, and loss of GKE independently; confirm quorum behavior matches Section 4 in each case |
| 20 | Testing | Simulate loss of the DC1↔GKE and DC2↔GKE links independently; confirm no unexpected quorum loss |
| 21 | Monitoring | Confirm quorum-state visibility spans all three sites (e.g., Prometheus federation or a dedicated exporter) with alerting on hybrid-link flapping |

## 11. Open Items and Documentation Gaps

The following points are explicitly flagged as inferred or unconfirmed, not vendor-guaranteed:

- No Confluent/CFK source specifies a minimum Kubernetes footprint for Site 0.5 (Section 6).
- Persistent Disk SSD recommendation for the metadata log (Section 7) is inferred from general KRaft I/O sensitivity, not independently sourced in this research pass.
- Firewall scoping recommendation (Section 7, Section 10 rule 17) is a general security best practice, not a vendor-documented requirement.
- GCP Hong Kong latency figures (Section 5) are 2018 GCP-internal VM-to-VM measurements, not on-premises-to-GCP measurements — must be re-measured against real infrastructure before any region commitment.
- DC2's physical location is not yet defined in this proposal (Section 3) and must be confirmed before network requirements can be validated against real circuits.

## 12. Recommendations Summary

1. Provision DC2 as a genuine second full site — equal brokers and 2 controllers, independent power/network domain from DC1.
2. Deploy the fifth controller as a controller-only node in GKE (Site 0.5), no brokers.
3. Use three independent Kubernetes clusters (Option A), not a stretched control plane.
4. Enforce RTT ceilings: < 50 ms ideal / < 100 ms hard limit for DC1↔DC2; < 100 ms hard limit for each leg to GKE.
5. Use dedicated/private connectivity for all three inter-site links, with mTLS and firewall scoping.
6. Use GKE Standard (not Autopilot), non-Spot node pools, `pd-ssd` storage for the witness controller.
7. Standardize on Confluent Platform ≥ 7.9.6 / CFK ≥ 3.2 with dynamic quorum, avoiding the listed defective patch versions.
8. Configure broker replication factor and `min.insync.replicas` independently to achieve the desired data-plane RPO — do not conflate this with controller quorum resilience.
9. Run explicit failure-injection tests for each single-site and single-link loss scenario before go-live.

## Sources

1. Confluent — Multi-Region Architectures: https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region-architectures.html
2. Confluent — Multi-Region Clusters: https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region.html
3. SoftwareMill — Understanding In-Sync Replicas and Replication Factor in Confluent Stretched Cluster 2.5: https://softwaremill.com/understanding-in-sync-replicas-and-replication-factor-in-confluent-stretched-cluster-2-5/
4. AutoMQ — Kafka Stretch Clusters Explained: A Deep Dive into Multi-Datacenter Architecture: https://www.automq.com/blog/kafka-stretch-clusters-multi-datacenter-architecture
5. OneUptime — How to Deploy a Rook-Ceph Stretch Cluster Across Two Datacenters: https://oneuptime.com/blog/post/2026-03-31-rook-deploy-stretch-cluster-two-datacenters/view
6. Confluent for Kubernetes — Configure Multi-Region Deployment of Confluent Platform: https://docs.confluent.io/operator/current/co-multi-region.html
7. Confluent Kubernetes Examples (GitHub) — Hybrid Multi-Region Clusters README: https://github.com/confluentinc/confluent-kubernetes-examples/blob/master/hybrid/multi-region-clusters/README.md
8. Red Hat — Guidance for Clusters That Span Data Centers (etcd, OpenShift 4.22): https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/etcd/etcd-guidance-span
9. Kubernetes Documentation — Pod Topology Spread Constraints: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/
10. iKala — GCP Hong Kong Region (asia-east2) Latency Measurements: https://ikala.cloud/blog/infrastructure/gcp-hk-region-asia-east-2
11. Google Cloud — Spot VMs in GKE: https://docs.cloud.google.com/kubernetes-engine/docs/concepts/spot-vms
12. Google Cloud — Autopilot and Standard Feature Comparison: https://docs.cloud.google.com/kubernetes-engine/docs/resources/autopilot-standard-feature-comparison
13. Google Cloud — Networking for Hybrid and Multi-Cloud Workloads: https://docs.cloud.google.com/architecture/network-hybrid-multicloud
14. Confluent — Configure Dynamic KRaft Quorum: https://docs.confluent.io/operator/current/co-configure-kraft-dynamic-quorum.html
