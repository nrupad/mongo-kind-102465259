#!/usr/bin/env bash
# Initializes rs0 with the three stable per-pod DNS names. Idempotent: safe
# to re-run against an already-initiated replica set.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/vars.sh"

echo "Waiting for mongo-0, mongo-1, mongo-2 pods to be Running in ${NAMESPACE}..."
for pod in mongo-0 mongo-1 mongo-2; do
  kubectl -n "${NAMESPACE}" wait --for=condition=Ready "pod/${pod}" --timeout=300s
done

ALREADY_INITIATED=$(kubectl -n "${NAMESPACE}" exec mongo-0 -- \
  mongosh --quiet --eval "try { rs.status().ok } catch (e) { print(0) }" 2>/dev/null | tail -n1 || echo "0")

if [ "${ALREADY_INITIATED}" = "1" ]; then
  echo "Replica set rs0 is already initiated. Skipping rs.initiate()."
else
  echo "Initiating replica set rs0 with mongo-0/1/2 stable DNS names..."
  kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "
    rs.initiate({
      _id: 'rs0',
      members: [
        { _id: 0, host: 'mongo-0.mongo-h.${NAMESPACE}.svc.cluster.local:27017' },
        { _id: 1, host: 'mongo-1.mongo-h.${NAMESPACE}.svc.cluster.local:27017' },
        { _id: 2, host: 'mongo-2.mongo-h.${NAMESPACE}.svc.cluster.local:27017' }
      ]
    })
  "
fi

echo "Waiting for a PRIMARY to be elected..."
for i in $(seq 1 60); do
  STATE=$(kubectl -n "${NAMESPACE}" exec mongo-0 -- \
    mongosh --quiet --eval "rs.hello().isWritablePrimary || rs.hello().secondary || false" 2>/dev/null | tail -n1 || true)
  PRIMARY=$(kubectl -n "${NAMESPACE}" exec mongo-0 -- \
    mongosh --quiet --eval "(rs.hello().primary || 'none')" 2>/dev/null | tail -n1 || true)
  if [ "${PRIMARY}" != "none" ] && [ -n "${PRIMARY}" ]; then
    echo "Primary elected: ${PRIMARY}"
    break
  fi
  sleep 2
done

kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "rs.status().members.forEach(m => print(m.name + ' -> ' + m.stateStr))"
