#!/usr/bin/env bash
set -euo pipefail

A="a-broker-1:9092,a-broker-2:9092,a-broker-3:9092"
B="b-broker-1:9092,b-broker-2:9092,b-broker-3:9092"

echo "Cluster A:"
kafka-consumer-groups --bootstrap-server "$A" --group payments-poc --describe || true
echo
echo "Cluster B:"
kafka-consumer-groups --bootstrap-server "$B" --group payments-poc --describe || true
