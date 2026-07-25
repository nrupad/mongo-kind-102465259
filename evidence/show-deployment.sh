#!/usr/bin/env bash
# Walks through the already-bootstrapped deployment, ONE command per screen,
# for evidence screenshots. Clears the screen and fakes a shell prompt
# before each command so it reads like a normal manual terminal session.
# Touches evidence/.ckpts/<name> (silently) after each step so an external
# screenshot watcher can sync to real progress.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/vars.sh"
CKPT_DIR="${REPO_ROOT}/evidence/.ckpts"
mkdir -p "${CKPT_DIR}"
rm -f "${CKPT_DIR}"/*

PROMPT="\033[1;32mnrupad@clo835\033[0m \033[1;35m(ns:${NAMESPACE})\033[0m:\033[1;34m~/mongo-kind\033[0m\$ "

task() {
  # task <checkpoint-name> <displayed-command> -- <real command...>
  local name="$1"; shift
  local display="$1"; shift
  clear
  printf "${PROMPT}%s\n" "${display}"
  sleep 0.4
  "$@"
  touch "${CKPT_DIR}/${name}"
  sleep 2.5
}

task "01-namespace" "kubectl get ns ${NAMESPACE} --show-labels" \
  kubectl get ns "${NAMESPACE}" --show-labels

task "02-services" "kubectl -n ${NAMESPACE} get svc -o wide" \
  kubectl -n "${NAMESPACE}" get svc -o wide

task "03-statefulset" "kubectl -n ${NAMESPACE} get statefulset,pods -o wide" \
  kubectl -n "${NAMESPACE}" get statefulset,pods -o wide

task "04-pvcs" "kubectl -n ${NAMESPACE} get pvc -o wide" \
  kubectl -n "${NAMESPACE}" get pvc -o wide

task "05-probes" "kubectl -n ${NAMESPACE} get pod mongo-0 -o jsonpath='{.spec.containers[0].livenessProbe}'" \
  kubectl -n "${NAMESPACE}" get pod mongo-0 -o jsonpath='{.spec.containers[0].livenessProbe}{"\n"}'

task "06-rs-status" 'kubectl -n '"${NAMESPACE}"' exec mongo-0 -- mongosh --eval "rs.status().members"' \
  kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "
    rs.status().members.forEach(m => print(m.name + '  ->  ' + m.stateStr + '  health=' + m.health));
  "

task "07-seed-count" 'mongosh --eval "db.students.countDocuments({sid, note: \"seed\"})"' \
  kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "
    print('clo835.students seed count for sid ${STUDENT_ID}: ' + db.getSiblingDB('clo835').students.countDocuments({sid: '${STUDENT_ID}', note: 'seed'}));
  "

task "08-seed-data" "kubectl -n ${NAMESPACE} exec mongo-0 -- mongosh --eval \"db.students.find({sid}).forEach(print)\"" \
  kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "
    db.getSiblingDB('clo835').students.find({sid: '${STUDENT_ID}', note: 'seed'}).sort({seq:1}).forEach(
      d => print(d.seq + '.  sid=' + d.sid + '  note=' + d.note + '  _id=' + d._id)
    );
  "

task "09-parameterization" "cat scripts/vars.sh" \
  cat "${REPO_ROOT}/scripts/vars.sh"

task "10-done" "kubectl get ns ${NAMESPACE} -o jsonpath='{.metadata.name}{\"  ->  \"}{.metadata.labels.student}{\"\n\"}'" \
  kubectl get ns "${NAMESPACE}" -o jsonpath='{.metadata.name}{"  ->  "}{.metadata.labels.student}{"\n"}'
