# CLO835 Semester Project 2 — MongoDB Replica Set on kind

This project sets up a 3-member MongoDB replica set on a local `kind`
Kubernetes cluster, using plain Kubernetes YAML (no Helm, no kustomize).
Everything is brought up with one script, `bootstrap.sh`.

- Student: Nrupad Raval — ID `102465259`
- Namespace: `mongo-102465259`
- Image: `mongo:7` (official image from Docker Hub)

## Repo layout

```
kind-config.yaml      kind cluster definition (1 control-plane + 2 workers)
bootstrap.sh           runs everything below in order
manifests/
  00-namespace.yaml
  10-headless-service.yaml   mongo-h, used for pod-to-pod DNS
  11-read-service.yaml       mongo-read, normal ClusterIP for clients
  20-statefulset.yaml        the mongo StatefulSet (3 pods, PVC each)
scripts/
  vars.sh              student ID + namespace, set once here
  init-replicaset.sh    runs rs.initiate()
  seed.sh               inserts the 10 seed documents
  insert.sh             inserts one marker document (used in the demo)
runbook.md              commands used during the live demo
```

## How to run it

```bash
./bootstrap.sh
```

This creates the kind cluster, applies the manifests, waits for the 3 pods
to be ready, initiates the replica set, and seeds the database. It prints
the status of all 3 members at the end. See `runbook.md` for the rest of
the demo steps (finding the primary, killing a pod, checking the data
survived, etc).

## Why a StatefulSet and not a Deployment

MongoDB replica set members need to keep the same name and the same
storage every time they restart, otherwise the other members can't find
them again and the data would be gone. A Deployment doesn't guarantee
either of those things — pods get random names and can share/lose
storage. A StatefulSet gives each pod a fixed name (`mongo-0`, `mongo-1`,
`mongo-2`) and its own PersistentVolumeClaim that follows it around.

## Why the headless service

`mongo-h` has `clusterIP: None`, which means it doesn't get a single
virtual IP like a normal service. Instead, each pod gets its own DNS
name: `mongo-0.mongo-h.mongo-102465259.svc.cluster.local`, and so on.
That's exactly what `rs.initiate()` uses to register the three members,
so they can still find each other even after a restart changes their pod
IP.

## Student ID

The student ID only appears in one place, `scripts/vars.sh`. Every other
script and manifest reads it from there instead of having it typed in
multiple times.
