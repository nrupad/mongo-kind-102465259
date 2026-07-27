#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/vars.sh"

if [ $# -lt 1 ]; then
  echo "Usage: $0 \"<message>\"" >&2
  exit 1
fi
MESSAGE="$1"

TARGET=""
for pod in mongo-0 mongo-1 mongo-2; do
  if kubectl -n "${NAMESPACE}" exec "${pod}" -- true >/dev/null 2>&1; then
    TARGET="${pod}"
    break
  fi
done

if [ -z "${TARGET}" ]; then
  echo "No reachable mongo pod found in ${NAMESPACE}." >&2
  exit 1
fi

URI="mongodb://mongo-0.mongo-h.${NAMESPACE}.svc.cluster.local:27017,mongo-1.mongo-h.${NAMESPACE}.svc.cluster.local:27017,mongo-2.mongo-h.${NAMESPACE}.svc.cluster.local:27017/clo835?replicaSet=rs0"

echo "namespace=${NAMESPACE}  sid=${STUDENT_ID}  -- connecting through ${TARGET}, writing marker with w: majority..."
kubectl -n "${NAMESPACE}" exec "${TARGET}" -- mongosh --quiet "${URI}" --eval "
  const res = db.students.insertOne(
    { sid: '${STUDENT_ID}', marker: '${MESSAGE}', ts: new Date() },
    { writeConcern: { w: 'majority' } }
  );
  print('Inserted marker _id: ' + res.insertedId);
"
