#!/usr/bin/env bash
set -euo pipefail

A="a-broker-1:9092,a-broker-2:9092,a-broker-3:9092"

kafka-topics --bootstrap-server "$A" \
  --create \
  --topic payments \
  --partitions 6 \
  --replication-factor 3 \
  --config min.insync.replicas=2
