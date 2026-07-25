# CLO835 Semester Project 2 — MongoDB Replica Set on kind

3-member MongoDB replica set (`rs0`) running on a local `kind` cluster,
built from raw Kubernetes manifests (no Helm, no kustomize), driven by a
single idempotent `bootstrap.sh`.

- Student: Nrupad Raval — ID `102465259`
- Namespace: `mongo-102465259`
- Image: `mongo:7` (official, Docker Hub)

## Repo layout

```
kind-config.yaml        1 control-plane + 2 worker kind cluster
bootstrap.sh             clean-host -> healthy seeded replica set, idempotent
manifests/
  00-namespace.yaml       namespace mongo-102465259 (templated via ${NAMESPACE})
  10-headless-service.yaml  mongo-h, clusterIP: None, peer discovery DNS
  11-read-service.yaml      mongo-read, ClusterIP, client access
  20-statefulset.yaml       mongo StatefulSet, 3 replicas, PVC per pod, probes
scripts/
  vars.sh                 single source of truth for STUDENT_ID / NAMESPACE
  init-replicaset.sh       idempotent rs.initiate() with stable DNS names
  seed.sh                  idempotent seed of clo835.students (10 docs, w:majority)
  insert.sh                marker document insert used live during the demo
runbook.md                copy-pasteable procedures for the live demo
evidence/                  pre-demo terminal captures from a real run
```

## Quick start

```bash
./bootstrap.sh
```

Brings up the kind cluster, applies all manifests, initiates the replica
set with the three stable pod DNS names
(`mongo-N.mongo-h.mongo-102465259.svc.cluster.local:27017`), and seeds
`clo835.students` with 10 documents tagged with the student ID. Finishes by
printing each member's `stateStr`. See `runbook.md` for the failover demo
procedures.

## Design notes

- **StatefulSet vs Deployment:** MongoDB replica set members need stable
  identities (`mongo-0/1/2`), stable per-pod DNS, and their own persistent
  volume that survives pod recreation — a Deployment's fungible,
  identically-named pods and shared/ephemeral storage model can't provide
  any of that.
- **Headless service (`mongo-h`, `clusterIP: None`):** gives each pod a
  resolvable DNS record (`<pod>.mongo-h.<ns>.svc.cluster.local`) instead of
  a single virtual IP, which is what `rs.initiate()` needs to record stable
  member hostnames that survive pod restarts and IP changes.
  `publishNotReadyAddresses: true` so peers can resolve each other during
  initial replica set formation, before readiness passes.
  `mongo-read` is a normal ClusterIP service for client-style access.
- **Student ID parameterization:** `scripts/vars.sh` is the only place
  `STUDENT_ID` is set. `bootstrap.sh` exports it and pipes every manifest
  through `envsubst` before `kubectl apply`, so the namespace name is
  substituted at apply time rather than hardcoded in each YAML file.
