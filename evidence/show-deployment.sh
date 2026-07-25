#!/usr/bin/env bash
# Walks through the already-bootstrapped deployment, task by task, for
# evidence screenshots. Touches evidence/.ckpts/<name> after each step.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/vars.sh"
CKPT_DIR="${REPO_ROOT}/evidence/.ckpts"
mkdir -p "${CKPT_DIR}"
rm -f "${CKPT_DIR}"/*
ckpt() { touch "${CKPT_DIR}/$1"; echo ">>> checkpoint: $1"; sleep 1.5; }

echo "############################################################"
echo "# CLO835 Semester Project 2 - MongoDB Replica Set on kind"
echo "# Student: Nrupad Raval  |  ID: ${STUDENT_ID}  |  Namespace: ${NAMESPACE}"
echo "############################################################"
sleep 2

echo; echo "=== TASK 1: Namespace ${NAMESPACE} ==="
kubectl get ns "${NAMESPACE}" --show-labels
ckpt "01-namespace"

echo; echo "=== TASK 2/3: Headless service mongo-h + client service mongo-read ==="
kubectl -n "${NAMESPACE}" get svc -o wide
ckpt "02-services"

echo; echo "=== TASK 4/5: StatefulSet mongo (3 replicas, mongo:7, PVC per pod) ==="
kubectl -n "${NAMESPACE}" get statefulset mongo -o wide
kubectl -n "${NAMESPACE}" get pods -o wide
kubectl -n "${NAMESPACE}" get pvc -o wide
ckpt "03-statefulset-and-pvcs"

echo; echo "=== TASK 6: Liveness / readiness probes ==="
kubectl -n "${NAMESPACE}" get pod mongo-0 -o jsonpath='{.spec.containers[0].livenessProbe}' | python3 -m json.tool 2>/dev/null || kubectl -n "${NAMESPACE}" get pod mongo-0 -o jsonpath='{.spec.containers[0].livenessProbe}{"\n"}'
ckpt "04-probes"

echo; echo "=== TASK 5 (init): rs.initiate() result - replica set rs0 ==="
kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "
  rs.status().members.forEach(m => print(m.name + '  ->  stateStr=' + m.stateStr + '  health=' + m.health));
"
ckpt "05-rs-status"

echo; echo "=== TASK 7: Seed data - clo835.students, student ID stamped in documents ==="
kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "
  print('document count: ' + db.getSiblingDB('clo835').students.countDocuments({sid: '${STUDENT_ID}'}));
  db.getSiblingDB('clo835').students.find({sid: '${STUDENT_ID}'}).sort({seq:1}).forEach(d => printjson(d));
"
ckpt "06-seed-data"

echo; echo "=== TASK 9: student ID parameterization (single source: scripts/vars.sh) ==="
cat "${REPO_ROOT}/scripts/vars.sh"
ckpt "07-parameterization"

echo; echo "=== bootstrap.sh full run log (this cluster's actual bootstrap) ==="
if [ -f "${REPO_ROOT}/evidence/bootstrap-run.log" ]; then
  tail -n 20 "${REPO_ROOT}/evidence/bootstrap-run.log"
fi
ckpt "08-bootstrap-log-tail"

echo; echo "=== Deployment walkthrough complete. Proceeding to failover twist next. ==="
ckpt "09-done"
