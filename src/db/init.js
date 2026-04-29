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
  // Decentralized Multi-Hospital Architecture
  // Creating tables for two different hospital nodes
  await run(
    'CREATE TABLE IF NOT EXISTS apollo_hospital_records (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      'abha_id TEXT UNIQUE,' +
      'raw_json TEXT NOT NULL' +
    ')'
  );

  await run(
    'CREATE TABLE IF NOT EXISTS max_hospital_records (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      'abha_id TEXT UNIQUE,' +
      'raw_json TEXT NOT NULL' +
    ')'
  );

  // Check if populated
  const countApollo = await get('SELECT COUNT(1) AS count FROM apollo_hospital_records');
  const countMax = await get('SELECT COUNT(1) AS count FROM max_hospital_records');
  
  if ((countApollo && countApollo.count > 0) || (countMax && countMax.count > 0)) {
    return; // Already populated
  }

  const raw = fs.readFileSync(dataPath, 'utf-8');
  const records = JSON.parse(raw);

  // Distribute records to simulate decentralized nodes
  for (let i = 0; i < records.length; i++) {
    const record = records[i];
    const isApollo = i % 2 === 0;
    const table = isApollo ? 'apollo_hospital_records' : 'max_hospital_records';
    
    // Override the mock JSON data to simulate different hospitals
    record.hospital_name = isApollo ? 'Apollo Hospital' : 'Max Super Specialty Hospital';
    record.hospital_id = isApollo ? 'HOSP_APOLLO' : 'HOSP_MAX';

    await run(
      `INSERT OR REPLACE INTO ${table} (abha_id, raw_json) VALUES (?, ?)`,
      [record.abha_id || null, JSON.stringify(record)]
    );
  }
};

module.exports = initDb;
