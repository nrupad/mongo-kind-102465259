#!/usr/bin/env bash
# One script that sets up everything: the kind cluster, the namespace and
# services, the StatefulSet, the replica set, and the seed data.
# Each step checks if it already ran, so running this twice is safe.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/vars.sh"
export STUDENT_ID NAMESPACE

START_TIME=$(date +%s)
KIND_CLUSTER_NAME="mongo-kind"

echo "=== [1/6] kind cluster ==="
if kind get clusters 2>/dev/null | grep -qx "${KIND_CLUSTER_NAME}"; then
  echo "kind cluster '${KIND_CLUSTER_NAME}' already exists. Skipping creation."
else
  kind create cluster --config "${SCRIPT_DIR}/kind-config.yaml"
fi
kubectl cluster-info --context "kind-${KIND_CLUSTER_NAME}"

echo "=== [2/6] Applying manifests (namespace, services, statefulset) for namespace=${NAMESPACE} ==="
for f in "${SCRIPT_DIR}"/manifests/*.yaml; do
  echo "-- applying $(basename "${f}")"
  envsubst < "${f}" | kubectl apply -f -
done

echo "=== [3/6] Waiting for StatefulSet rollout ==="
kubectl -n "${NAMESPACE}" rollout status statefulset/mongo --timeout=300s

echo "=== [4/6] Initializing replica set ==="
"${SCRIPT_DIR}/scripts/init-replicaset.sh"

echo "=== [5/6] Seeding data ==="
"${SCRIPT_DIR}/scripts/seed.sh"

echo "=== [6/6] Final replica set status ==="
kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "
  rs.status().members.forEach(m => print(m.name + ' -> stateStr=' + m.stateStr + ' health=' + m.health));
"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
echo "=== bootstrap.sh complete in ${ELAPSED}s (limit: 900s) ==="
