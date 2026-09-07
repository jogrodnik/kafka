#!/usr/bin/env bash
set -euo pipefail

B="b-broker-1:9092,b-broker-2:9092,b-broker-3:9092"

echo "1) Confirm DC1 has been declared failed/fenced."
echo "2) Inspect mirror state and lag before accepting the RPO."
kafka-mirrors --describe --mirror-topic payments --bootstrap-server "$B"

echo
echo "3) Fail over the mirror. This converts it into a writable normal topic."
kafka-mirrors --failover \
  --mirror-topic payments \
  --bootstrap-server "$B"

echo
echo "4) Verify topic and mirror state."
kafka-topics --describe --topic payments --bootstrap-server "$B"
kafka-mirrors --describe --mirror-topic payments --include-stopped --bootstrap-server "$B" || true

cat <<'TXT'

NEXT, outside Kafka:
5) Switch DNS/PSC from the DC1 endpoint to the DC2 endpoint.
6) Clients should lose A connections and rebootstrap to the logical bootstrap name.
7) Consumers join the group on B.
8) Transactional producers must initialize a new transactional context on B.
9) Run reconciliation before declaring DR complete.
TXT
