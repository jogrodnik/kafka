#!/usr/bin/env bash
set -euo pipefail

echo "Generate one ID for Cluster A and one different ID for Cluster B:"
echo "CLUSTER_A_ID=$(kafka-storage random-uuid)"
echo "CLUSTER_B_ID=$(kafka-storage random-uuid)"
echo
echo "Use the same Cluster A ID when formatting ALL six DC1 nodes."
echo "Use the same Cluster B ID when formatting ALL six DC2 nodes."
