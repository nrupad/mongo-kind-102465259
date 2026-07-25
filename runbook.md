# Runbook — MongoDB Replica Set on kind

Student: Nrupad Raval (ID `102465259`) — namespace `mongo-102465259`.

All commands below assume you are in the repo root and `NS=mongo-102465259`.

```bash
export NS=mongo-102465259
```

## 1. Bootstrap from a clean host

```bash
./bootstrap.sh
```

**Expect:** kind cluster `mongo-kind` created (1 control-plane + 2 workers),
namespace/services/StatefulSet applied, all 3 pods `Ready`, replica set
`rs0` initiated, 10 seed documents inserted, and a final block like:

```
mongo-0.mongo-h.mongo-102465259.svc.cluster.local:27017 -> stateStr=PRIMARY health=1
mongo-1.mongo-h.mongo-102465259.svc.cluster.local:27017 -> stateStr=SECONDARY health=1
mongo-2.mongo-h.mongo-102465259.svc.cluster.local:27017 -> stateStr=SECONDARY health=1
```

Success = all three members `health=1`, exactly one `PRIMARY`, two
`SECONDARY`, script exits 0 in well under 15 minutes.

## 2. Find the current primary

```bash
kubectl -n $NS exec mongo-0 -- mongosh --quiet --eval "rs.status().members.forEach(m => print(m.name + ' ' + m.stateStr + ' health=' + m.health + ' optime=' + JSON.stringify(m.optimeDate)))"
kubectl -n $NS exec mongo-0 -- mongosh --quiet --eval "rs.hello().primary"
```

**Reading it:** `stateStr` is the human-readable replica state
(`PRIMARY`/`SECONDARY`/`STARTUP2`/etc.), `health` is `1` if the member is
reachable and passing heartbeats, `0` if not. `optime`/`optimeDate` is the
timestamp of the last operation applied from the oplog — compare it across
members to see who's caught up.

## 3. Insert a marker document (majority write concern)

```bash
./scripts/insert.sh "<message>"
```

This execs into whichever member pod is reachable and connects using the
full 3-host replica set seed list (`?replicaSet=rs0`), so the driver
auto-discovers the primary and routes the write there regardless of which
pod the script happened to reach. Underlying command:

```js
db.students.insertOne(
  { sid: "102465259", marker: "<message>", ts: new Date() },
  { writeConcern: { w: "majority" } }
)
```

## 4. Kill a named member and watch the election

```bash
kubectl delete pod mongo-N -n $NS
```

In one pane:

```bash
kubectl get pods -n $NS -w
```

In another pane, repeatedly (from a survivor, e.g. mongo-0 or mongo-1,
whichever isn't the victim):

```bash
watch -n1 'kubectl -n mongo-102465259 exec mongo-0 -- mongosh --quiet --eval "rs.status().members.forEach(m => print(m.name + \" \" + m.stateStr))"'
```

(swap `mongo-0` for a survivor if mongo-0 is the victim). **Expect:** the
victim briefly disappears/shows unhealthy, remaining members go through an
election, one of the two survivors flips to `PRIMARY` within a few seconds
(bounded by the default 10s `electionTimeoutMillis`), and the new pod comes
back as `STARTUP2` → `SECONDARY` once Kubernetes recreates it.

## 5. Verify data survived

```bash
kubectl -n $NS exec mongo-0 -- mongosh --quiet --eval "
  print('seed count: ' + db.getSiblingDB('clo835').students.countDocuments({ sid: '102465259', note: 'seed' }));
  printjson(db.getSiblingDB('clo835').students.find({ marker: { \$exists: true } }).sort({ ts: -1 }).limit(1).toArray());
"
```

Then check replication to a secondary explicitly:

```bash
kubectl -n $NS exec mongo-1 -- mongosh --quiet --eval "
  db.getMongo().setReadPref('secondary');
  printjson(db.getSiblingDB('clo835').students.find({ marker: { \$exists: true } }).sort({ ts: -1 }).limit(1).toArray());
"
```

Expect the seed count to still be 10 and the marker document present and
identical on both the new primary and a secondary — zero lost writes.

## 6. Prove PVC reattachment

```bash
kubectl get pvc -n $NS -o wide           # before kill
kubectl delete pod mongo-N -n $NS
kubectl get pvc -n $NS -o wide           # after: same PVC name/UID, same Bound volume
kubectl -n $NS get pod mongo-N -o jsonpath='{.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}{"\n"}'
```

**Expect:** `data-mongo-N` PVC is unchanged (same name, same
`VOLUME`/UID) across the delete/recreate — the StatefulSet controller
reattaches the existing claim rather than provisioning a new one, which is
why the recreated pod's data directory already has the full oplog history
to replay from.

## 7. Tear down and rebuild

```bash
kind delete cluster --name mongo-kind
./bootstrap.sh
```
