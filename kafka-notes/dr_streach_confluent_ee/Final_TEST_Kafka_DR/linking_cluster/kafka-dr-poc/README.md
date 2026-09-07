# Kafka DR POC — Two KRaft Clusters with Cluster Linking

## Goal

Build two fully independent Kafka KRaft clusters:

- **DC1 / Cluster A:** 3 isolated controllers + 3 brokers
- **DC2 / Cluster B:** 3 isolated controllers + 3 brokers
- **Normal direction:** A -> B
- **DR:** promote/fail over the mirror on B, switch the logical client endpoint, let clients rebootstrap, and resume on B.

This POC intentionally uses **PLAINTEXT** so the DR mechanics can be validated before adding TLS/SASL.

> Do not use these security settings in production.

## Important product requirement

Cluster Linking is a Confluent commercial capability on the cluster that owns the link/mirror functionality. For the bidirectional DR flow in this POC, use supported Confluent Platform / Confluent Server on both clusters and a valid Enterprise/trial entitlement.

## Hostnames

Add lab DNS or `/etc/hosts` entries so every node and CLI host can resolve:

- a-ctrl-1, a-ctrl-2, a-ctrl-3
- a-broker-1, a-broker-2, a-broker-3
- b-ctrl-1, b-ctrl-2, b-ctrl-3
- b-broker-1, b-broker-2, b-broker-3

## Ports

- Brokers: 9092
- KRaft controllers: 9093

## KRaft note

The files deliberately use a **static 3-controller quorum** because it makes a first DR POC deterministic and easy to inspect. Current Confluent guidance recommends dynamic controller quorums for new production clusters. Once this POC works, the same design can be converted to `controller.quorum.bootstrap.servers`.

## Build sequence

1. Generate **two different cluster IDs**.
2. Format all DC1 nodes with Cluster A ID.
3. Format all DC2 nodes with Cluster B ID.
4. Start controllers, then brokers, in both clusters.
5. Verify both KRaft quorums.
6. Create `payments` on A.
7. Create the bidirectional cluster link.
8. Create the `payments` mirror on B.
9. Produce on A and consume/inspect on B.
10. Start consumer group `payments-poc` on A and verify offset synchronization to B.
11. Simulate DC1 loss.
12. Fail over `payments` on B.
13. Change the logical DNS/PSC bootstrap endpoint from A to B.
14. Verify client KIP-899 rebootstrap behavior.
15. Reinitialize transactional producers on B; do not continue an in-flight A transaction.
16. Run reconciliation.

## Client DR endpoint

Production-style clients should use a logical endpoint such as:

`kafka-dr.example.internal:9092`

Normal state:

`kafka-dr.example.internal -> DC1 Kafka endpoint`

DR state:

`kafka-dr.example.internal -> DC2 Kafka endpoint`

The client configurations enable:

- `metadata.recovery.strategy=rebootstrap`
- `metadata.recovery.rebootstrap.trigger.ms=30000`

DNS switching is only performed **after B has been made writable and verified**.

## Financial POC invariants

For a financial-grade test, add an immutable `event_id` to each test event and deliberately test:

- duplicate replay,
- DC1 failure before transaction commit,
- DC1 failure immediately after commit,
- consumer restart on B,
- consumer offset position on B,
- new transactional producer initialization on B,
- financial reconciliation of expected vs processed event IDs.

## Directory layout

```text
dc1/
  controller-1.properties
  controller-2.properties
  controller-3.properties
  broker-1.properties
  broker-2.properties
  broker-3.properties

dc2/
  controller-1.properties
  controller-2.properties
  controller-3.properties
  broker-1.properties
  broker-2.properties
  broker-3.properties

cluster-link/
  a-link.properties
  b-link.properties

client/
  producer.properties
  consumer.properties
  producer-direct-a.properties
  consumer-direct-b.properties

scripts/
  00-generate-cluster-ids.sh
  01-format-example.sh
  02-create-source-topic.sh
  03-create-bidirectional-link.sh
  04-create-mirror-on-b.sh
  05-test-data.sh
  06-dr-failover-to-b.sh
  07-verify-offsets.sh
```
