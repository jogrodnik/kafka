#!/usr/bin/env bash
set -euo pipefail

: "${CLUSTER_A_ID:?export CLUSTER_A_ID first}"
: "${CLUSTER_B_ID:?export CLUSTER_B_ID first}"

# Run the relevant command on each actual host with its local properties file.
# Examples:
kafka-storage format -t "$CLUSTER_A_ID" -c dc1/controller-1.properties
kafka-storage format -t "$CLUSTER_A_ID" -c dc1/broker-1.properties

kafka-storage format -t "$CLUSTER_B_ID" -c dc2/controller-1.properties
kafka-storage format -t "$CLUSTER_B_ID" -c dc2/broker-1.properties

echo "Repeat for controller-2/3 and broker-2/3 on their respective hosts."
