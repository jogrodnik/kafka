#!/usr/bin/env bash
set -euo pipefail

A="a-broker-1:9092,a-broker-2:9092,a-broker-3:9092"
B="b-broker-1:9092,b-broker-2:9092,b-broker-3:9092"

echo "payment-001" | kafka-console-producer \
  --bootstrap-server "$A" \
  --topic payments \
  --producer.config client/producer-direct-a.properties

kafka-console-consumer \
  --bootstrap-server "$B" \
  --topic payments \
  --from-beginning \
  --max-messages 1
