const express = require('express');
const crypto = require('crypto');
const qrcode = require('qrcode');
const db = require('../db/sqlite');
const {
  mapToFHIR,
  mapReportToFHIR,
  searchTimeline,
  generateClinicalSummary,
  generateAgenticSynthesis,
  fallbackMapToFHIR,
} = require('../services/openai-mapper');
const renderShareHtml = require('../views/shareView');

const router = express.Router();

const shareVault = new Map();
const otpStore = new Map();
const fhirCache = new Map();
const intelligenceCache = new Map();
const summaryCache = new Map();
const CACHE_TTL_MS = 5 * 60 * 1000;

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

const getCacheValue = (cache, key) => {
  const entry = cache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.timestamp > CACHE_TTL_MS) {
    cache.delete(key);
    return null;
  }
  return entry.value;
};

const setCacheValue = (cache, key, value) => {
  cache.set(key, { value, timestamp: Date.now() });
};

const refreshSummaryCache = async (abhaId, unifiedData, consent = {}) => {
  const fhirData = await mapToFHIR(unifiedData);
  const summaryData = await generateClinicalSummary(fhirData, consent);
  const payload = { clinical_summary: summaryData.clinical_summary };
  setCacheValue(summaryCache, abhaId, payload);
  return payload;
};

router.get('/patient/:id', async (req, res) => {
  try {
    const cachedFhir = getCacheValue(fhirCache, req.params.id);
    if (cachedFhir) {
      return res.json(cachedFhir);
    }

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

    const payload = {
      ...fhirData,
      ai_insights: {
        clinical_summary: summaryData.clinical_summary
      }
    };

    setCacheValue(fhirCache, req.params.id, payload);

    res.json(payload);
  } catch (error) {
    console.error('Failed to fetch patient:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/patient/:id/fast', async (req, res) => {
  try {
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

    let unifiedData = rawDataSources[0];
    if (rawDataSources.length > 1) {
      for (let i = 1; i < rawDataSources.length; i++) {
        const source = rawDataSources[i];
        if (source.visits) unifiedData.visits = (unifiedData.visits || []).concat(source.visits);
        if (source.patient_visits) unifiedData.patient_visits = (unifiedData.patient_visits || []).concat(source.patient_visits);
        if (source.admission_records) unifiedData.admission_records = (unifiedData.admission_records || []).concat(source.admission_records);
      }
    }

    const fhirData = fallbackMapToFHIR(unifiedData);
    res.json(fhirData);
  } catch (error) {
    console.error('Failed to fetch patient (fast):', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/patient/:id/summary', async (req, res) => {
  try {
    const forceRefresh = req.body?.force_refresh === true;
    const consent = req.body?.consent || {};
    const cachedSummary = !forceRefresh ? getCacheValue(summaryCache, req.params.id) : null;

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

    let unifiedData = rawDataSources[0];
    if (rawDataSources.length > 1) {
      for (let i = 1; i < rawDataSources.length; i++) {
        const source = rawDataSources[i];
        if (source.visits) unifiedData.visits = (unifiedData.visits || []).concat(source.visits);
        if (source.patient_visits) unifiedData.patient_visits = (unifiedData.patient_visits || []).concat(source.patient_visits);
        if (source.admission_records) unifiedData.admission_records = (unifiedData.admission_records || []).concat(source.admission_records);
      }
    }
    if (cachedSummary) {
      // In background, refresh cache with consent context
      refreshSummaryCache(req.params.id, unifiedData, consent).catch((error) => {
        console.error('Failed to refresh summary:', error);
      });
      return res.json(cachedSummary);
    }

    const payload = await refreshSummaryCache(req.params.id, unifiedData, consent);
    res.json(payload);
  } catch (error) {
    console.error('Failed to fetch summary:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/patient/:id/intelligence', async (req, res) => {
  try {
    const consent = req.body?.consent || {};
    const consentFlags = {
      risk_signals: consent.risk_signals !== false,
      treatment_patterns: consent.treatment_patterns !== false,
      clinical_context: consent.clinical_context !== false,
      consent_status: consent.consent_status !== false,
    };

    const isRefresh = req.body?.refresh === true;
    const cachedIntelligence = isRefresh ? null : getCacheValue(intelligenceCache, req.params.id);
    if (cachedIntelligence) {
      return res.json({
        risk_signals: consentFlags.risk_signals ? cachedIntelligence.risk_signals : [],
        treatment_patterns: consentFlags.treatment_patterns ? cachedIntelligence.treatment_patterns : [],
        clinical_context: consentFlags.clinical_context ? cachedIntelligence.clinical_context : 'Hidden by consent.',
        consent_status: consentFlags.consent_status ? cachedIntelligence.consent_status : 'Hidden by consent.',
      });
    }

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
    const intelligence = await generateAgenticSynthesis(fhirData);

    setCacheValue(intelligenceCache, req.params.id, intelligence);

    res.json({
      risk_signals: consentFlags.risk_signals ? intelligence.risk_signals : [],
      treatment_patterns: consentFlags.treatment_patterns ? intelligence.treatment_patterns : [],
      clinical_context: consentFlags.clinical_context ? intelligence.clinical_context : 'Hidden by consent.',
      consent_status: consentFlags.consent_status ? intelligence.consent_status : 'Hidden by consent.',
    });
  } catch (error) {
    console.error('Failed to generate intelligence:', error);
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
    if (!entry) {
      if (req.accepts('html')) {
        return res.status(401).send(`
          <!DOCTYPE html>
          <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
              body { font-family: system-ui, sans-serif; background: #0f172a; color: white; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; text-align: center; }
              .box { background: rgba(30, 41, 59, 0.8); padding: 2rem; border-radius: 16px; max-width: 400px; border: 1px solid rgba(255,255,255,0.1); }
              h1 { color: #f43f5e; margin-top: 0; }
            </style>
          </head>
          <body>
            <div class="box">
              <h1>Not Authorized</h1>
              <p>This secure health session has ended or the link is invalid.</p>
            </div>
          </body>
          </html>
        `);
      }
      return res.status(404).json({ error: 'Share not found or session ended' });
    }

    if (req.accepts('html')) {
      const html = renderShareHtml(entry.data);
      return res.send(html);
    }
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

    res.json({ share_url: shareUrl, qr_data_url: qrDataUrl, share_id: shareId });
  } catch (error) {
    console.error('Failed to generate QR:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/revoke-share', (req, res) => {
  try {
    const { share_id } = req.body || {};
    if (share_id) {
      shareVault.delete(share_id);
    }
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
