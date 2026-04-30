const axios = require('axios');

/**
 * Strips markdown code fences that OpenAI sometimes wraps JSON in,
 * e.g. ```json\n{...}\n``` even when instructed not to.
 */
const stripMarkdownFences = (text) => {
  return text
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/, '')
    .trim();
};

/**
 * Shared OpenAI chat completion call with error surfacing and
 * reliable JSON output via response_format.
 */
const callOpenAI = async ({ systemPrompt, userContent, supportsJsonMode = true, temperature = 0 }) => {
  const apiKey = process.env.OPENAI_API_KEY;
  const baseUrl = process.env.OPENAI_BASE_URL || 'https://api.openai.com/v1';
  const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';
  const maxTokens = Number(process.env.OPENAI_MAX_TOKENS || 2048);

  if (!apiKey) {
    throw new Error('OPENAI_API_KEY is not set');
  }

  const body = {
    model,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userContent },
    ],
    temperature,
    max_tokens: maxTokens,
  };

  // json_object mode guarantees valid JSON output — supported on gpt-4o, gpt-4o-mini, gpt-3.5-turbo-1106+
  if (supportsJsonMode) {
    body.response_format = { type: 'json_object' };
  }

  let response;
  try {
    response = await axios.post(`${baseUrl}/chat/completions`, body, {
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
    });
  } catch (err) {
    const status = err.response?.status;
    const message = err.response?.data?.error?.message || err.message;
    throw new Error(`OpenAI API error (HTTP ${status}): ${message}`);
  }

  const content = response.data?.choices?.[0]?.message?.content;
  if (!content) {
    throw new Error('OpenAI returned an empty response');
  }

  const cleaned = stripMarkdownFences(content);

  try {
    return JSON.parse(cleaned);
  } catch (_parseErr) {
    console.error('JSON Parse Error:', _parseErr.message);
    const fs = require('fs');
    fs.writeFileSync('failed_openai_response.txt', cleaned);
    throw new Error(
      `Failed to parse OpenAI response as JSON. Error: ${_parseErr.message}. Raw content saved to failed_openai_response.txt`
    );
  }
};

const buildPatientName = (record) => {
  const name = record.name || '';
  if (name) return name.trim();
  const first = record.f_name || record.fname || record.patient_first_name || '';
  const last = record.l_name || record.lname || record.patient_last_name || '';
  return `${first} ${last}`.trim();
};

const buildPatientDob = (record) => record.b_day || record.dob || record.date_of_birth || '';

const buildPatientGender = (record) => {
  const gender = (record.gender || record.sex || '').toString().toLowerCase();
  if (gender.startsWith('m')) return 'male';
  if (gender.startsWith('f')) return 'female';
  return gender || 'unknown';
};

const asNumber = (value) => {
  if (value == null) return null;
  const num = Number(value);
  return Number.isFinite(num) ? num : null;
};

const createObservation = ({ id, text, value, unit, status, subjectId }) => ({
  resourceType: 'Observation',
  id,
  status: 'final',
  code: { text },
  subject: { reference: `Patient/${subjectId}` },
  valueQuantity: value != null ? { value, unit } : undefined,
  interpretation: status ? [{ text: status }] : undefined,
});

const fallbackMapToFHIR = (messyData) => {
  if (messyData?.resourceType === 'Bundle') return messyData;

  const record = messyData || {};
  const abhaId = record.abha_id || record.abhaId || record.id || 'unknown';

  const patient = {
    resourceType: 'Patient',
    id: abhaId,
    name: [
      {
        text: buildPatientName(record) || 'Unknown',
      },
    ],
    gender: buildPatientGender(record),
    birthDate: buildPatientDob(record) || undefined,
    telecom: [
      record.phone || record.contact_number || record.mobile_number
        ? { system: 'phone', value: record.phone || record.contact_number || record.mobile_number }
        : null,
      record.email || record.email_id
        ? { system: 'email', value: record.email || record.email_id }
        : null,
    ].filter(Boolean),
    address: record.address || record.residential_address
      ? [{ text: record.address || record.residential_address }]
      : undefined,
  };

  const entries = [{ resource: patient }];
  const visits = [
    ...(record.visits || []),
    ...(record.patient_visits || []),
    ...(record.admission_records || [])
  ];

  visits.forEach((visit, index) => {
    const encounterId = visit.visit_id || visit.visit_number || visit.admission_id || `visit-${index + 1}`;
    entries.push({
      resource: {
        resourceType: 'Encounter',
        id: encounterId,
        status: 'finished',
        type: [{ text: visit.visit_type || visit.type_of_visit || visit.admission_reason || 'Visit' }],
        period: { start: visit.visit_date || visit.date_of_visit || visit.admission_date || undefined },
        reasonCode: [{ text: visit.symptoms || visit.chief_complaint || visit.presenting_complaint || visit.reason || '' }].filter((r) => r.text),
        subject: { reference: `Patient/${abhaId}` },
      },
    });

    const diagnoses = visit.diagnosis || visit.provisional_diagnosis || visit.confirmed_diagnosis || [];
    diagnoses.forEach((diag, diagIndex) => {
      entries.push({
        resource: {
          resourceType: 'Condition',
          id: `${encounterId}-cond-${diagIndex + 1}`,
          clinicalStatus: { text: 'active' },
          code: { text: diag },
          subject: { reference: `Patient/${abhaId}` },
        },
      });
    });

    const labs = visit.lab_tests || visit.investigations || visit.diagnostic_tests || [];
    labs.forEach((lab, labIndex) => {
      entries.push({
        resource: createObservation({
          id: `${encounterId}-lab-${labIndex + 1}`,
          text: lab.test_name || lab.investigation_name || lab.test_title || 'Lab Test',
          value: asNumber(lab.result) ?? asNumber(lab.result_value) ?? asNumber(lab.values?.wbc),
          unit: lab.unit || lab.measurement_unit || lab.values?.unit,
          status: lab.status || lab.remarks || lab.interpretation,
          subjectId: abhaId,
        }),
      });
    });

    const vitals = visit.vitals || visit.vital_signs || visit.vital_measurements || {};
    Object.entries(vitals).forEach(([key, val], vitalIndex) => {
      const value = asNumber(val) ?? val?.toString?.();
      entries.push({
        resource: createObservation({
          id: `${encounterId}-vital-${vitalIndex + 1}`,
          text: key.replace(/_/g, ' '),
          value: typeof value === 'number' ? value : undefined,
          unit: typeof value === 'number' ? undefined : null,
          status: undefined,
          subjectId: abhaId,
        }),
      });
    });
  });

  return {
    resourceType: 'Bundle',
    type: 'collection',
    entry: entries,
  };
};

const reduceFhirBundle = (bundle, maxEntries = 30) => {
  if (!bundle || bundle.resourceType !== 'Bundle') return bundle;
  const entries = Array.isArray(bundle.entry) ? bundle.entry : [];
  const trimmed = entries.slice(0, maxEntries).map((entry) => {
    const resource = entry.resource || {};
    const minimal = {
      resourceType: resource.resourceType,
      id: resource.id,
      status: resource.status,
      code: resource.code,
      type: resource.type,
      category: resource.category,
      medicationCodeableConcept: resource.medicationCodeableConcept,
      dosage: resource.dosage,
      period: resource.period,
      reasonCode: resource.reasonCode,
      clinicalStatus: resource.clinicalStatus,
      verificationStatus: resource.verificationStatus,
      valueQuantity: resource.valueQuantity,
      valueString: resource.valueString,
      interpretation: resource.interpretation,
      onsetDateTime: resource.onsetDateTime,
      recordedDate: resource.recordedDate,
      subject: resource.subject,
      // PII REMOVED: Name, Telecom, and Address stripped for privacy [cite: 366]
      gender: resource.gender,
      birthDate: resource.birthDate,
    };
    return { resource: minimal };
  });

  return {
    resourceType: 'Bundle',
    type: bundle.type || 'collection',
    entry: trimmed,
  };
};

/**
 * Converts messy/legacy patient data into a valid HL7 FHIR R4 Patient bundle.
 */
const mapToFHIR = async (messyData) => {
  const useOpenAi = String(process.env.USE_OPENAI_FHIR || '').toLowerCase() === 'true';
  if (!useOpenAi) {
    return fallbackMapToFHIR(messyData);
  }

  const systemPrompt = [
    'You are a medical data translator.',
    'Convert the input into a valid HL7 FHIR R4 Bundle of type "collection".',
    'Include the primary Patient resource as the first entry.',
    'You MUST extract all historical data and include them as entries in the bundle. The output MUST have this structure: {"resourceType": "Bundle", "type": "collection", "entry": [ {"resource": { "resourceType": "Patient", ... } }, {"resource": { "resourceType": "Encounter", ... } }, {"resource": { "resourceType": "Observation", ... } }, {"resource": { "resourceType": "MedicationStatement", ... } } ]}.',
    'Extract visits as Encounters, prescriptions as MedicationStatements, vitals and lab reports as Observations, and diagnoses as Conditions.',
    'Return ONLY raw JSON. No markdown, no explanation, no code fences.',
  ].join(' ');

  try {
    return await callOpenAI({
      systemPrompt,
      userContent: JSON.stringify(messyData),
    });
  } catch (error) {
    console.error('OpenAI mapping failed, using fallback mapper:', error.message);
    return fallbackMapToFHIR(messyData);
  }
};

/**
 * Converts free-text lab report into a valid HL7 FHIR R4 Observation JSON.
 */
const mapReportToFHIR = async (reportText) => {
  const systemPrompt = [
    'You are a medical data translator.',
    'Convert the input lab report text into valid HL7 FHIR R4 Observation JSON.',
    'Return ONLY raw JSON. No markdown, no explanation, no code fences.',
  ].join(' ');

  return callOpenAI({
    systemPrompt,
    userContent: reportText,
  });
};

const searchTimeline = async (fhirBundle, query) => {
  const systemPrompt = [
    'You are an AI Clinical Search Agent.',
    `Analyze the provided patient FHIR record and provide a detailed, analytical answer to the clinical query: "${query}"`,
    'Your summary should explain correlations, specific values, and trends found across the matching records. Don\'t just list them; synthesize the meaning.',
    'Return a JSON object with this structure: {"summary": string, "matches": [{"entry_index": number, "summary": string, "resource_type": string, "title": string}]}.',
    'Use entry_index to point to the matching resource in the bundle entry array (0-based).',
    'Each individual match summary should be a concise, patient-friendly sentence.',
    'If nothing matches, return an empty matches array and summary "No relevant data found in timeline."',
    'Return ONLY raw JSON. No markdown, no explanation.'
  ].join(' ');

  return callOpenAI({
    systemPrompt,
    userContent: JSON.stringify(reduceFhirBundle(fhirBundle, 25)),
  }).catch((error) => {
    console.error('Search AI failed, returning empty result:', error.message);
    return { summary: 'No relevant data found in timeline.', matches: [] };
  });
};

const generateClinicalSummary = async (fhirBundle, consent = {}) => {
  const systemPrompt = [
    'You are an AI Clinical Summarization Agent.',
    'Review the provided patient FHIR record (which may contain data merged from multiple hospitals) and provide a comprehensive, detailed executive summary (4-6 sentences).',
    consent.risk_signals !== false ? 'Include specific data trends and risk signals found in the record.' : 'Do NOT include risk signals or acute clinical warnings.',
    consent.treatment_patterns !== false ? 'Explain treatment-response patterns and medication efficacy.' : 'Do NOT analyze treatment patterns or long-term efficacy.',
    `IMPORTANT: Calculate the patient's age based on their birthDate relative to the current time. Generation Time: ${new Date().toISOString()}`,
    'Output a JSON object with a single key "clinical_summary" whose value is a detailed narrative STRING (paragraph). Return ONLY raw JSON.'
  ].join(' ');

  return callOpenAI({
    systemPrompt,
    userContent: JSON.stringify(reduceFhirBundle(fhirBundle, 20)),
    temperature: 0.7,
  }).catch((error) => {
    console.error('Summary AI failed, returning default summary:', error.message);
    return { clinical_summary: 'No notable findings.' };
  });
};

const generateAgenticSynthesis = async (fhirBundle) => {
  const systemPrompt = [
    'You are a Clinical Intelligence Engine.',
    'Act as a network of four specialized agents: Risk Sentinel, Pattern Miner, Context Mapper, and Governance Officer.',
    'Analyze the provided FHIR Bundle and output a JSON object with these keys:',
    'risk_signals: array of short bullet strings,',
    'treatment_patterns: array of short bullet strings,',
    'clinical_context: string summary,',
    'consent_status: string summary (The Governance Officer must explain the current state of data privacy, compliance, and consent. Examples: "All records de-identified per clinical protocols," "Unified cross-hospital synthesis active," "Patient consent verified for current clinical query").',
    `IMPORTANT: Calculate the patient's age based on their birthDate relative to the current time. Generation Time: ${new Date().toISOString()}`,
    'Return ONLY raw JSON. No markdown, no explanation.'
  ].join(' ');

  return callOpenAI({
    systemPrompt,
    userContent: JSON.stringify(reduceFhirBundle(fhirBundle, 20)),
  }).catch((error) => {
    console.error('Agentic AI failed, returning default response:', error.message);
    return {
      risk_signals: [],
      treatment_patterns: [],
      clinical_context: 'No notable findings.',
      consent_status: 'No notable findings.',
    };
  });
};

module.exports = {
  mapToFHIR,
  mapReportToFHIR,
  searchTimeline,
  generateClinicalSummary,
  generateAgenticSynthesis,
  fallbackMapToFHIR,
  reduceFhirBundle,
};
