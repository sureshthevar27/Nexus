const fs = require('fs');
const path = require('path');
const db = require('./sqlite');

const dataPath = path.join(__dirname, '..', '..', 'data', 'hospital_db.json');

const run = (sql, params = []) => new Promise((resolve, reject) => {
  db.run(sql, params, function (err) {
    if (err) return reject(err);
    resolve(this);
  });
});

const get = (sql, params = []) => new Promise((resolve, reject) => {
  db.get(sql, params, (err, row) => {
    if (err) return reject(err);
    resolve(row);
  });
});

const initDb = async () => {
  await run(
    'CREATE TABLE IF NOT EXISTS patients (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      'abha_id TEXT UNIQUE,' +
      'hospital_id TEXT,' +
      'raw_json TEXT NOT NULL' +
    ')'
  );

  const countRow = await get('SELECT COUNT(1) AS count FROM patients');
  if (countRow && countRow.count > 0) return;

  const raw = fs.readFileSync(dataPath, 'utf-8');
  const records = JSON.parse(raw);

  for (const record of records) {
    await run(
      'INSERT OR REPLACE INTO patients (abha_id, hospital_id, raw_json) VALUES (?, ?, ?)',
      [record.abha_id || null, record.hospital_id || null, JSON.stringify(record)]
    );
  }
};

module.exports = initDb;
