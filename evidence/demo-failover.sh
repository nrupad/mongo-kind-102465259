#!/usr/bin/env bash
# Evidence-capture dry run of the runbook's failover procedure (runbook.md
# steps 2-6). Not part of the graded repo layout - this just drives the
# real cluster the same way the live demo will, so screenshots can be taken
# at each checkpoint. Touches evidence/.ckpts/<name> after each step so an
# external screenshot watcher can sync to real progress.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/vars.sh"
CKPT_DIR="${REPO_ROOT}/evidence/.ckpts"
mkdir -p "${CKPT_DIR}"
rm -f "${CKPT_DIR}"/*
ckpt() { touch "${CKPT_DIR}/$1"; echo ">>> checkpoint: $1"; sleep 1; }

echo "=== Failover demo dry-run for namespace ${NAMESPACE} ==="

echo "--- A. rs.status() before the twist ---"
kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "rs.status().members.forEach(m => print(m.name + ' ' + m.stateStr + ' health=' + m.health))"
OLD_PRIMARY=$(kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "rs.hello().primary" 2>/dev/null | tail -n1)
echo "Current primary: ${OLD_PRIMARY}"
VICTIM=$(echo "${OLD_PRIMARY}" | cut -d. -f1)
echo "Victim chosen for this dry run (current primary): ${VICTIM}"
ckpt "01-status-before"

echo "--- B. seed count before ---"
kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "print('seed count: ' + db.getSiblingDB('clo835').students.countDocuments({sid:'${STUDENT_ID}', note:'seed'}))"
ckpt "02-seed-count-before"

echo "--- C. insert marker document, w: majority ---"
MARKER="mentor-demo-$(date +%s)"
"${REPO_ROOT}/scripts/insert.sh" "${MARKER}"
ckpt "03-marker-inserted"

echo "--- D. kubectl get pvc BEFORE kill ---"
kubectl -n "${NAMESPACE}" get pvc -o wide
PVC_UID_BEFORE=$(kubectl -n "${NAMESPACE}" get pvc "data-${VICTIM}" -o jsonpath='{.metadata.uid}')
ckpt "04-pvc-before"

echo "--- E. kill victim pod ${VICTIM} (seconds after the marker insert) ---"
kubectl -n "${NAMESPACE}" delete pod "${VICTIM}"
ckpt "05-pod-deleted"

echo "--- F. watch pod recreation ---"
for i in $(seq 1 60); do
  PHASE=$(kubectl -n "${NAMESPACE}" get pod "${VICTIM}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
  READY=$(kubectl -n "${NAMESPACE}" get pod "${VICTIM}" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
  echo "poll ${i}: ${VICTIM} phase=${PHASE} ready=${READY}"
  [ "${PHASE}" = "Running" ] && [ "${READY}" = "true" ] && break
  sleep 3
done
kubectl -n "${NAMESPACE}" get pods -o wide
ckpt "06-victim-recreated"

echo "--- G. wait for a NEW primary to be elected ---"
SURVIVOR="mongo-0"
[ "${SURVIVOR}" = "${VICTIM}" ] && SURVIVOR="mongo-1"
NEW_PRIMARY=""
for i in $(seq 1 60); do
  NEW_PRIMARY=$(kubectl -n "${NAMESPACE}" exec "${SURVIVOR}" -- mongosh --quiet --eval "rs.hello().primary" 2>/dev/null | tail -n1 || echo "")
  echo "poll ${i}: primary=${NEW_PRIMARY}"
  [ -n "${NEW_PRIMARY}" ] && [ "${NEW_PRIMARY}" != "none" ] && break
  sleep 2
done
echo "New primary: ${NEW_PRIMARY}"
kubectl -n "${NAMESPACE}" exec "${SURVIVOR}" -- mongosh --quiet --eval "rs.status().members.forEach(m => print(m.name + ' ' + m.stateStr + ' health=' + m.health))"
ckpt "07-new-primary-elected"

echo "--- H. verify zero data loss on new primary ---"
NEW_PRIMARY_POD=$(echo "${NEW_PRIMARY}" | cut -d. -f1)
kubectl -n "${NAMESPACE}" exec "${NEW_PRIMARY_POD}" -- mongosh --quiet --eval "
  print('seed count: ' + db.getSiblingDB('clo835').students.countDocuments({sid:'${STUDENT_ID}', note:'seed'}));
  printjson(db.getSiblingDB('clo835').students.findOne({marker:'${MARKER}'}));
"
ckpt "08-data-verified-on-new-primary"

echo "--- I. verify replication to a secondary ---"
kubectl -n "${NAMESPACE}" exec "${SURVIVOR}" -- mongosh --quiet --eval "
  db.getMongo().setReadPref('secondary');
  printjson(db.getSiblingDB('clo835').students.findOne({marker:'${MARKER}'}));
"
ckpt "09-secondary-read-verified"

echo "--- J. PVC reused, not recreated ---"
kubectl -n "${NAMESPACE}" get pvc -o wide
PVC_UID_AFTER=$(kubectl -n "${NAMESPACE}" get pvc "data-${VICTIM}" -o jsonpath='{.metadata.uid}')
echo "PVC UID before=${PVC_UID_BEFORE} after=${PVC_UID_AFTER}"
if [ "${PVC_UID_BEFORE}" = "${PVC_UID_AFTER}" ]; then
  echo "PVC REUSED (same UID) - confirmed, not recreated."
else
  echo "WARNING: PVC UID changed - claim was NOT reused."
fi
ckpt "10-pvc-after"

echo "--- K. final rs.status() (cluster healthy again) ---"
kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "rs.status().members.forEach(m => print(m.name + ' ' + m.stateStr + ' health=' + m.health))"
ckpt "11-final-status"

echo "=== Failover demo dry run complete. Marker used: ${MARKER} ==="
ckpt "12-done"
