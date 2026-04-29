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
    throw new Error(
      `Failed to parse OpenAI response as JSON. Raw content: ${cleaned.slice(0, 300)}`
    );
  }
};

/**
 * Converts messy/legacy patient data into a valid HL7 FHIR R4 Patient bundle.
 */
const mapToFHIR = async (messyData) => {
  const systemPrompt = [
    'You are a medical data translator.',
    'Convert the input into a valid HL7 FHIR R4 Patient JSON object.',
    'Include related Observation and Condition resources when present.',
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

module.exports = { mapToFHIR, mapReportToFHIR };
