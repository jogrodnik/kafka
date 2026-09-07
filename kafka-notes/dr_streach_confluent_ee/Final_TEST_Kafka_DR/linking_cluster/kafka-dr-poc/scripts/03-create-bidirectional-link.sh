#!/usr/bin/env bash
set -euo pipefail

A="a-broker-1:9092,a-broker-2:9092,a-broker-3:9092"
B="b-broker-1:9092,b-broker-2:9092,b-broker-3:9092"
LINK="dr-link"

# Create the same-named bidirectional link object on both clusters.
kafka-cluster-links --create \
  --link "$LINK" \
  --config-file cluster-link/a-link.properties \
  --bootstrap-server "$A"

kafka-cluster-links --create \
  --link "$LINK" \
  --config-file cluster-link/b-link.properties \
  --bootstrap-server "$B"

kafka-cluster-links --list --bootstrap-server "$A"
kafka-cluster-links --list --bootstrap-server "$B"
