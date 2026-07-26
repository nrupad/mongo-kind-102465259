# Runbook — MongoDB Replica Set on kind

Student: Nrupad Raval (ID `102465259`) — namespace `mongo-102465259`.

Run this first so the commands below can just use `$NS`:

```bash
export NS=mongo-102465259
```

## 1. Bootstrap from a clean host

```bash
./bootstrap.sh
```

This creates the kind cluster, applies the manifests, waits for the 3
pods, sets up the replica set, and seeds the data. At the end it prints
something like this:

```
mongo-0.mongo-h.mongo-102465259.svc.cluster.local:27017 -> stateStr=PRIMARY health=1
mongo-1.mongo-h.mongo-102465259.svc.cluster.local:27017 -> stateStr=SECONDARY health=1
mongo-2.mongo-h.mongo-102465259.svc.cluster.local:27017 -> stateStr=SECONDARY health=1
```

If all three show `health=1`, with one `PRIMARY` and two `SECONDARY`,
it worked.

## 2. Find the current primary

```bash
kubectl -n $NS exec mongo-0 -- mongosh --quiet --eval "rs.status().members.forEach(m => print(m.name + ' ' + m.stateStr + ' health=' + m.health + ' optime=' + JSON.stringify(m.optimeDate)))"
kubectl -n $NS exec mongo-0 -- mongosh --quiet --eval "rs.hello().primary"
```

`stateStr` tells you what each member is doing right now (`PRIMARY`,
`SECONDARY`, `STARTUP2`, ...). `health` is `1` if the member is up and
responding, `0` if not. `optimeDate` is the time of the last operation
that member applied — if one member's optime is behind the others, it's
still catching up.

## 3. Insert a marker document (majority write concern)

```bash
./scripts/insert.sh "<message>"
```

It runs this, on whichever pod is still reachable:

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

Pane 1:

```bash
kubectl get pods -n $NS -w
```

Pane 2 (run from a pod that's still alive, not the one being killed):

```bash
watch -n1 'kubectl -n mongo-102465259 exec mongo-0 -- mongosh --quiet --eval "rs.status().members.forEach(m => print(m.name + \" \" + m.stateStr))"'
```

The killed pod should show unhealthy for a few seconds, one of the two
remaining pods becomes the new `PRIMARY`, and once Kubernetes brings the
old pod back it rejoins as `STARTUP2` then `SECONDARY`.

## 5. Verify data survived

```bash
kubectl -n $NS exec mongo-0 -- mongosh --quiet --eval "
  print('seed count: ' + db.getSiblingDB('clo835').students.countDocuments({ sid: '102465259', note: 'seed' }));
  printjson(db.getSiblingDB('clo835').students.find({ marker: { \$exists: true } }).sort({ ts: -1 }).limit(1).toArray());
"
```

And check the secondary has it too:

```bash
kubectl -n $NS exec mongo-1 -- mongosh --quiet --eval "
  db.getMongo().setReadPref('secondary');
  printjson(db.getSiblingDB('clo835').students.find({ marker: { \$exists: true } }).sort({ ts: -1 }).limit(1).toArray());
"
```

Seed count should still be 10, and the marker document should show up on
both the new primary and the secondary — nothing lost.

## 6. Prove the PVC was reused, not recreated

```bash
kubectl get pvc -n $NS -o wide           # before killing the pod
kubectl delete pod mongo-N -n $NS
kubectl get pvc -n $NS -o wide           # after: same name, same volume
kubectl -n $NS get pod mongo-N -o jsonpath='{.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}{"\n"}'
```

The `data-mongo-N` PVC should have the exact same name and volume before
and after. That's why the pod that comes back already has all its data —
it got its old disk back, not a blank one.

## 7. Tear down and rebuild

```bash
kind delete cluster --name mongo-kind
./bootstrap.sh
```
