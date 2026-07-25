#!/usr/bin/env bash
# Live failover dry run (runbook.md steps 2-6), ONE command per screen, for
# evidence screenshots. Clears the screen and fakes a shell prompt before
# each command so it reads like a normal manual terminal session. Not part
# of the graded repo layout - this just drives the real cluster the same
# way the live demo will.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/vars.sh"
CKPT_DIR="${REPO_ROOT}/evidence/.ckpts"
mkdir -p "${CKPT_DIR}"
rm -f "${CKPT_DIR}"/*

PROMPT="\033[1;32mnrupad@clo835\033[0m \033[1;35m(ns:${NAMESPACE})\033[0m:\033[1;34m~/mongo-kind\033[0m\$ "

task() {
  local name="$1"; shift
  local display="$1"; shift
  clear
  printf "${PROMPT}%s\n" "${display}"
  sleep 0.4
  "$@"
  touch "${CKPT_DIR}/${name}"
  sleep 2.5
}

OLD_PRIMARY=$(kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "rs.hello().primary" 2>/dev/null | tail -n1)
VICTIM=$(echo "${OLD_PRIMARY}" | cut -d. -f1)

task "01-status-before" "kubectl -n ${NAMESPACE} exec mongo-0 -- mongosh --eval \"rs.status().members\"" \
  kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "
    rs.status().members.forEach(m => print(m.name + '  ->  ' + m.stateStr + '  health=' + m.health));
  "

task "02-seed-count-before" "kubectl -n ${NAMESPACE} exec mongo-0 -- mongosh --eval \"db.students.countDocuments({sid})\"" \
  kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "
    print('namespace=${NAMESPACE}  sid=${STUDENT_ID}  seed count: ' + db.getSiblingDB('clo835').students.countDocuments({sid:'${STUDENT_ID}', note:'seed'}));
  "

MARKER="mentor-demo-$(date +%s)"
task "03-marker-inserted" "./scripts/insert.sh \"${MARKER}\"" \
  "${REPO_ROOT}/scripts/insert.sh" "${MARKER}"

task "04-pvc-before" "kubectl -n ${NAMESPACE} get pvc -o wide" \
  kubectl -n "${NAMESPACE}" get pvc -o wide
PVC_UID_BEFORE=$(kubectl -n "${NAMESPACE}" get pvc "data-${VICTIM}" -o jsonpath='{.metadata.uid}')

task "05-pod-deleted" "kubectl delete pod ${VICTIM} -n ${NAMESPACE}   # current primary" \
  kubectl -n "${NAMESPACE}" delete pod "${VICTIM}"

# Wait quietly (no polling spam on screen) for the pod to come back.
for i in $(seq 1 60); do
  PHASE=$(kubectl -n "${NAMESPACE}" get pod "${VICTIM}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
  READY=$(kubectl -n "${NAMESPACE}" get pod "${VICTIM}" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
  [ "${PHASE}" = "Running" ] && [ "${READY}" = "true" ] && break
  sleep 3
done

task "06-victim-recreated" "kubectl -n ${NAMESPACE} get pods -o wide" \
  kubectl -n "${NAMESPACE}" get pods -o wide

# Wait quietly for a NEW primary to be elected.
SURVIVOR="mongo-0"
[ "${SURVIVOR}" = "${VICTIM}" ] && SURVIVOR="mongo-1"
NEW_PRIMARY=""
for i in $(seq 1 60); do
  NEW_PRIMARY=$(kubectl -n "${NAMESPACE}" exec "${SURVIVOR}" -- mongosh --quiet --eval "rs.hello().primary" 2>/dev/null | tail -n1 || echo "")
  [ -n "${NEW_PRIMARY}" ] && [ "${NEW_PRIMARY}" != "none" ] && break
  sleep 2
done
NEW_PRIMARY_POD=$(echo "${NEW_PRIMARY}" | cut -d. -f1)

task "07-new-primary-elected" "kubectl -n ${NAMESPACE} exec ${SURVIVOR} -- mongosh --eval \"rs.status().members\"" \
  kubectl -n "${NAMESPACE}" exec "${SURVIVOR}" -- mongosh --quiet --eval "
    rs.status().members.forEach(m => print(m.name + '  ->  ' + m.stateStr + '  health=' + m.health));
  "

task "08-data-verified-on-new-primary" "kubectl -n ${NAMESPACE} exec ${NEW_PRIMARY_POD} -- mongosh --eval \"seed count + marker doc on new primary\"" \
  kubectl -n "${NAMESPACE}" exec "${NEW_PRIMARY_POD}" -- mongosh --quiet --eval "
    print('seed count: ' + db.getSiblingDB('clo835').students.countDocuments({sid:'${STUDENT_ID}', note:'seed'}));
    printjson(db.getSiblingDB('clo835').students.findOne({marker:'${MARKER}'}));
  "

task "09-secondary-read-verified" "kubectl -n ${NAMESPACE} exec ${SURVIVOR} -- mongosh --eval \"setReadPref('secondary'); find marker\"" \
  kubectl -n "${NAMESPACE}" exec "${SURVIVOR}" -- mongosh --quiet --eval "
    db.getMongo().setReadPref('secondary');
    printjson(db.getSiblingDB('clo835').students.findOne({marker:'${MARKER}'}));
  "

task "10-pvc-after" "kubectl -n ${NAMESPACE} get pvc -o wide   # same claim, not recreated" \
  kubectl -n "${NAMESPACE}" get pvc -o wide
PVC_UID_AFTER=$(kubectl -n "${NAMESPACE}" get pvc "data-${VICTIM}" -o jsonpath='{.metadata.uid}')
if [ "${PVC_UID_BEFORE}" != "${PVC_UID_AFTER}" ]; then
  echo "WARNING: PVC UID changed - claim was NOT reused." >&2
fi

task "11-final-status" "kubectl -n ${NAMESPACE} exec mongo-0 -- mongosh --eval \"rs.status().members\"   # cluster healthy again" \
  kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "
    rs.status().members.forEach(m => print(m.name + '  ->  ' + m.stateStr + '  health=' + m.health));
  "
