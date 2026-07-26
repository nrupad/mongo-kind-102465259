set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/vars.sh"

EXISTING=$(kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "
  db.getSiblingDB('clo835').students.countDocuments({ sid: '${STUDENT_ID}', note: 'seed' })
" 2>/dev/null | tail -n1 || echo "0")

if [ "${EXISTING}" -ge 10 ] 2>/dev/null; then
  echo "clo835.students already has ${EXISTING} seed documents for sid=${STUDENT_ID}. Skipping seed."
  exit 0
fi

echo "Seeding clo835.students with 10 documents (sid=${STUDENT_ID}, w: majority)..."
kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "
  const db = db.getSiblingDB('clo835');
  const docs = [];
  for (let i = 1; i <= 10; i++) {
    docs.push({ sid: '${STUDENT_ID}', seq: i, note: 'seed' });
  }
  const res = db.students.insertMany(docs, { writeConcern: { w: 'majority' } });
  print('Inserted: ' + Object.keys(res.insertedIds).length);
"

echo "Seed count now: $(kubectl -n "${NAMESPACE}" exec mongo-0 -- mongosh --quiet --eval "db.getSiblingDB('clo835').students.countDocuments({ sid: '${STUDENT_ID}' })" 2>/dev/null | tail -n1)"
