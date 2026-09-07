#!/usr/bin/env bash
set -euo pipefail

B="b-broker-1:9092,b-broker-2:9092,b-broker-3:9092"

kafka-mirrors --create \
  --mirror-topic payments \
  --link dr-link \
  --replication-factor 3 \
  --bootstrap-server "$B"

kafka-mirrors --describe \
  --mirror-topic payments \
  --bootstrap-server "$B"
