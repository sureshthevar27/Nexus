const express = require('express');
const crypto = require('crypto');
const qrcode = require('qrcode');
const db = require('../db/sqlite');
const { mapToFHIR, mapReportToFHIR, searchTimeline, generateClinicalSummary } = require('../services/openai-mapper');

const router = express.Router();

const shareVault = new Map();
const otpStore = new Map();

const getRow = (sql, params = []) => new Promise((resolve, reject) => {
  db.get(sql, params, (err, row) => {
    if (err) return reject(err);
    resolve(row || null);
  });
});

const getAll = (sql, params = []) => new Promise((resolve, reject) => {
  db.all(sql, params, (err, rows) => {
    if (err) return reject(err);
    resolve(rows || []);
  });
});

const normalizeText = (value) => String(value || '').trim().toLowerCase();

const getNameFromRecord = (record) => {
  if (record.name) return record.name;
  if (record.f_name || record.l_name) return `${record.f_name || ''} ${record.l_name || ''}`.trim();
  if (record.fname || record.lname) return `${record.fname || ''} ${record.lname || ''}`.trim();
  if (record.patient_first_name || record.patient_last_name) {
    return `${record.patient_first_name || ''} ${record.patient_last_name || ''}`.trim();
  }
  return '';
};

const getDobFromRecord = (record) => record.b_day || record.dob || record.date_of_birth || '';

const getPhoneFromRecord = (record) => (
  record.phone || record.contact_number || record.mobile_number || ''
);

const generateOtp = () => '123456';

router.get('/patient/:id', async (req, res) => {
  try {
    // Multi-Hospital Retrieval: Query both decentralized nodes concurrently
    const [apolloRow, maxRow] = await Promise.all([
      getRow('SELECT raw_json FROM apollo_hospital_records WHERE abha_id = ?', [req.params.id]),
      getRow('SELECT raw_json FROM max_hospital_records WHERE abha_id = ?', [req.params.id])
    ]);

    if (!apolloRow && !maxRow) {
      return res.status(404).json({ error: 'Patient not found in any hospital network' });
    }

    const rawDataSources = [];
    if (apolloRow) rawDataSources.push(JSON.parse(apolloRow.raw_json));
    if (maxRow) rawDataSources.push(JSON.parse(maxRow.raw_json));

    // For the hackathon, we combine visits from multiple hospitals into one unified payload
    // In reality, FHIR merging is complex, but here we just append arrays
    let unifiedData = rawDataSources[0];
    if (rawDataSources.length > 1) {
      for (let i = 1; i < rawDataSources.length; i++) {
        const source = rawDataSources[i];
        if (source.visits) {
          unifiedData.visits = (unifiedData.visits || []).concat(source.visits);
        }
        if (source.patient_visits) {
          unifiedData.patient_visits = (unifiedData.patient_visits || []).concat(source.patient_visits);
        }
        if (source.admission_records) {
          unifiedData.admission_records = (unifiedData.admission_records || []).concat(source.admission_records);
        }
      }
    }

    const fhirData = await mapToFHIR(unifiedData);
    
    // Step 2: Semantic AI Agents (Summarization)
    const summaryData = await generateClinicalSummary(fhirData);
    
    res.json({
      ...fhirData,
      ai_insights: {
        clinical_summary: summaryData.clinical_summary
      }
    });
  } catch (error) {
    console.error('Failed to fetch patient:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/link-record', async (req, res) => {
  try {
    const { abha_id: abhaId, name, dob } = req.body || {};
    if (!abhaId || !name || !dob) {
      return res.status(400).json({ error: 'abha_id, name, and dob are required' });
    }

    const [apolloRows, maxRows] = await Promise.all([
      getAll('SELECT raw_json FROM apollo_hospital_records'),
      getAll('SELECT raw_json FROM max_hospital_records')
    ]);
    const rows = [...apolloRows, ...maxRows];
    const targetName = normalizeText(name);
    const targetDob = normalizeText(dob);

    const match = rows
      .map((row) => JSON.parse(row.raw_json))
      .find((record) => {
        const recordName = normalizeText(getNameFromRecord(record));
        const recordDob = normalizeText(getDobFromRecord(record));
        return recordName === targetName && recordDob === targetDob;
      });

    if (!match) {
      return res.status(404).json({ match: false, message: 'Patient not found' });
    }

    const otp = generateOtp();
    const expiresAt = Date.now() + 5 * 60 * 1000;
    otpStore.set(abhaId, { otp, expiresAt });

    const phone = getPhoneFromRecord(match);
    if (phone) {
      console.log(`OTP for ${abhaId} sent to ${phone}: ${otp}`);
    } else {
      console.log(`OTP for ${abhaId}: ${otp}`);
    }

    res.json({ match: true, otp_required: true });
  } catch (error) {
    console.error('Failed to link record:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/verify-otp', async (req, res) => {
  try {
    const { abha_id: abhaId, otp } = req.body || {};
    if (!abhaId || !otp) {
      return res.status(400).json({ error: 'abha_id and otp are required' });
    }

    const record = otpStore.get(abhaId);
    if (!record) return res.status(400).json({ error: 'OTP expired or not requested' });
    if (record.expiresAt < Date.now()) {
      otpStore.delete(abhaId);
      return res.status(400).json({ error: 'OTP expired' });
    }
    if (record.otp !== String(otp)) {
      return res.status(400).json({ error: 'OTP incorrect' });
    }

    const [apolloRow, maxRow] = await Promise.all([
      getRow('SELECT raw_json FROM apollo_hospital_records WHERE abha_id = ?', [abhaId]),
      getRow('SELECT raw_json FROM max_hospital_records WHERE abha_id = ?', [abhaId])
    ]);
    if (!apolloRow && !maxRow) return res.status(404).json({ error: 'Patient not found' });

    otpStore.delete(abhaId);
    const token = crypto.randomUUID();
    const rawData = apolloRow ? JSON.parse(apolloRow.raw_json) : JSON.parse(maxRow.raw_json);

    res.json({ access_token: token, patient_data: rawData });
  } catch (error) {
    console.error('Failed to verify OTP:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/share-record', (req, res) => {
  try {
    const { data } = req.body || {};
    if (!data) return res.status(400).json({ error: 'data is required' });

    const shareId = crypto.randomUUID();
    shareVault.set(shareId, { data, createdAt: Date.now() });

    const shareUrl = `${req.protocol}://${req.get('host')}/share/${shareId}`;
    res.json({ share_url: shareUrl });
  } catch (error) {
    console.error('Failed to share record:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/share/:shareId', (req, res) => {
  try {
    const entry = shareVault.get(req.params.shareId);
    if (!entry) return res.status(404).json({ error: 'Share not found' });

    res.json(entry.data);
  } catch (error) {
    console.error('Failed to fetch shared record:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/scan-report', async (req, res) => {
  try {
    const { text } = req.body || {};
    if (!text) return res.status(400).json({ error: 'text is required' });

    const observation = await mapReportToFHIR(text);
    res.json(observation);
  } catch (error) {
    console.error('Failed to scan report:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/patient/:id/timeline', async (req, res) => {
  try {
    const [apolloRow, maxRow] = await Promise.all([
      getRow('SELECT raw_json FROM apollo_hospital_records WHERE abha_id = ?', [req.params.id]),
      getRow('SELECT raw_json FROM max_hospital_records WHERE abha_id = ?', [req.params.id])
    ]);

    if (!apolloRow && !maxRow) {
      return res.status(404).json({ error: 'Patient not found' });
    }

    const rawDataSources = [];
    if (apolloRow) rawDataSources.push({ ...JSON.parse(apolloRow.raw_json), _source_db: 'Apollo Health DB' });
    if (maxRow) rawDataSources.push({ ...JSON.parse(maxRow.raw_json), _source_db: 'Max Super Specialty DB' });

    res.json({ patients_data: rawDataSources });
  } catch (error) {
    console.error('Failed to fetch timeline:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/patient/:id/search', async (req, res) => {
  try {
    const { query } = req.body || {};
    if (!query) return res.status(400).json({ error: 'query is required' });

    const [apolloRow, maxRow] = await Promise.all([
      getRow('SELECT raw_json FROM apollo_hospital_records WHERE abha_id = ?', [req.params.id]),
      getRow('SELECT raw_json FROM max_hospital_records WHERE abha_id = ?', [req.params.id])
    ]);

    if (!apolloRow && !maxRow) {
      return res.status(404).json({ error: 'Patient not found' });
    }

    const rawDataSources = [];
    if (apolloRow) rawDataSources.push(JSON.parse(apolloRow.raw_json));
    if (maxRow) rawDataSources.push(JSON.parse(maxRow.raw_json));

    let unifiedData = rawDataSources[0];
    if (rawDataSources.length > 1) {
      for (let i = 1; i < rawDataSources.length; i++) {
        const source = rawDataSources[i];
        if (source.visits) unifiedData.visits = (unifiedData.visits || []).concat(source.visits);
        if (source.patient_visits) unifiedData.patient_visits = (unifiedData.patient_visits || []).concat(source.patient_visits);
        if (source.admission_records) unifiedData.admission_records = (unifiedData.admission_records || []).concat(source.admission_records);
      }
    }

    const fhirData = await mapToFHIR(unifiedData);
    const searchResult = await searchTimeline(fhirData, query);
    const entries = Array.isArray(fhirData.entry) ? fhirData.entry : [];
    const matches = Array.isArray(searchResult.matches) ? searchResult.matches : [];
    const hydratedMatches = matches.map((match) => {
      let resource = null;
      if (Number.isInteger(match.entry_index) && entries[match.entry_index]) {
        resource = entries[match.entry_index].resource || null;
      } else if (match.resource_id) {
        const found = entries.find((entry) => entry.resource?.id === match.resource_id);
        resource = found?.resource || null;
      }

      const title = match.title
        || resource?.code?.text
        || resource?.medicationCodeableConcept?.text
        || resource?.type?.[0]?.text
        || resource?.resourceType
        || 'Record';

      return {
        ...match,
        title,
        resource_type: resource?.resourceType || match.resource_type,
        resource,
      };
    });

    res.json({
      summary: searchResult.summary,
      matches: hydratedMatches,
    });
  } catch (error) {
    console.error('Failed to search timeline:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/generate-qr', async (req, res) => {
  try {
    const { data } = req.body || {};
    if (!data) return res.status(400).json({ error: 'data is required' });

    const shareId = crypto.randomUUID();
    shareVault.set(shareId, { data, createdAt: Date.now() });

    const shareUrl = `${req.protocol}://${req.get('host')}/share/${shareId}`;
    const qrDataUrl = await qrcode.toDataURL(shareUrl);

    res.json({ share_url: shareUrl, qr_data_url: qrDataUrl });
  } catch (error) {
    console.error('Failed to generate QR:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
