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
const callOpenAI = async ({ systemPrompt, userContent, supportsJsonMode = true }) => {
  const apiKey = process.env.OPENAI_API_KEY;
  const baseUrl = process.env.OPENAI_BASE_URL || 'https://api.openai.com/v1';
  const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';

  if (!apiKey) {
    throw new Error('OPENAI_API_KEY is not set');
  }

  const body = {
    model,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userContent },
    ],
    temperature: 0,
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

/**
 * Converts messy/legacy patient data into a valid HL7 FHIR R4 Patient bundle.
 */
const mapToFHIR = async (messyData) => {
  const systemPrompt = [
    'You are a medical data translator.',
    'Convert the input into a valid HL7 FHIR R4 Bundle of type "collection".',
    'Include the primary Patient resource as the first entry.',
    'You MUST extract all historical data and include them as entries in the bundle. The output MUST have this structure: {"resourceType": "Bundle", "type": "collection", "entry": [ {"resource": { "resourceType": "Patient", ... } }, {"resource": { "resourceType": "Encounter", ... } }, {"resource": { "resourceType": "Observation", ... } }, {"resource": { "resourceType": "MedicationStatement", ... } } ]}.',
    'Extract visits as Encounters, prescriptions as MedicationStatements, vitals and lab reports as Observations, and diagnoses as Conditions.',
    'Return ONLY raw JSON. No markdown, no explanation, no code fences.',
  ].join(' ');

  return callOpenAI({
    systemPrompt,
    userContent: JSON.stringify(messyData),
  });
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
    `Analyze the provided patient FHIR record and answer the clinical query: "${query}"`,
    'Return a JSON object with this structure: {"summary": string, "matches": [{"entry_index": number, "summary": string, "resource_type": string, "title": string}]}.',
    'Use entry_index to point to the matching resource in the bundle entry array (0-based).',
    'Each match summary should be a short, patient-friendly sentence for that resource.',
    'If nothing matches, return an empty matches array and summary "No relevant data found in timeline."',
    'Return ONLY raw JSON. No markdown, no explanation.'
  ].join(' ');

  return callOpenAI({
    systemPrompt,
    userContent: JSON.stringify(fhirBundle),
  });
};

const generateClinicalSummary = async (fhirBundle) => {
  const systemPrompt = [
    'You are an AI Clinical Summarization Agent.',
    'Review the provided patient FHIR record (which may contain data merged from multiple hospitals) and provide a concise, 2-3 sentence executive summary of their overall health status, major chronic conditions, and recent critical events.',
    'Output a JSON object with a single key "clinical_summary". Return ONLY raw JSON.'
  ].join(' ');

  return callOpenAI({
    systemPrompt,
    userContent: JSON.stringify(fhirBundle),
  });
};

module.exports = { mapToFHIR, mapReportToFHIR, searchTimeline, generateClinicalSummary };
