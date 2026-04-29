const express = require('express');
const crypto = require('crypto');
const qrcode = require('qrcode');
const db = require('../db/sqlite');
const { mapToFHIR, mapReportToFHIR } = require('../services/openai-mapper');

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
    const row = await getRow('SELECT raw_json FROM patients WHERE abha_id = ?', [req.params.id]);
    if (!row) return res.status(404).json({ error: 'Patient not found' });

    const rawData = JSON.parse(row.raw_json);
    const fhirData = await mapToFHIR(rawData);
    res.json(fhirData);
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

    const rows = await getAll('SELECT raw_json FROM patients');
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

    const row = await getRow('SELECT raw_json FROM patients WHERE abha_id = ?', [abhaId]);
    if (!row) return res.status(404).json({ error: 'Patient not found' });

    otpStore.delete(abhaId);
    const token = crypto.randomUUID();
    const rawData = JSON.parse(row.raw_json);

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

    res.json({ share_url: `/share/${shareId}` });
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
    const row = await getRow('SELECT raw_json FROM patients WHERE abha_id = ?', [req.params.id]);
    if (!row) return res.status(404).json({ error: 'Patient not found' });

    const rawData = JSON.parse(row.raw_json);
    res.json({ patient: rawData, sources: ['legacy_db'] });
  } catch (error) {
    console.error('Failed to fetch timeline:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/generate-qr', async (req, res) => {
  try {
    const { data } = req.body || {};
    if (!data) return res.status(400).json({ error: 'data is required' });

    const shareId = crypto.randomUUID();
    shareVault.set(shareId, { data, createdAt: Date.now() });

    const shareUrl = `/share/${shareId}`;
    const qrDataUrl = await qrcode.toDataURL(shareUrl);

    res.json({ share_url: shareUrl, qr_data_url: qrDataUrl });
  } catch (error) {
    console.error('Failed to generate QR:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
