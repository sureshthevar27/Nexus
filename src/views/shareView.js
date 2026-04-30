const renderShareHtml = (fhirData) => {
  // Extract patient
  const entries = fhirData.entry || [];
  let patient = null;
  const records = [];

  entries.forEach(entry => {
    if (entry.resource) {
      if (entry.resource.resourceType === 'Patient' && !patient) {
        patient = entry.resource;
      } else {
        records.push(entry.resource);
      }
    }
  });

  if (!patient && fhirData.resourceType === 'Patient') {
    patient = fhirData;
  }
  if (!patient && fhirData.contained) {
    patient = fhirData.contained.find(r => r.resourceType === 'Patient');
  }

  // Get patient details safely
  const getName = (p) => {
    if (!p) return 'Unknown Patient';
    if (p.name && p.name[0]) {
      if (p.name[0].text) return p.name[0].text;
      const first = p.name[0].given ? p.name[0].given.join(' ') : '';
      const last = p.name[0].family || '';
      return `${first} ${last}`.trim() || 'Unknown Patient';
    }
    return 'Unknown Patient';
  };

  const name = getName(patient);
  const dob = patient?.birthDate || 'Unknown DOB';
  const gender = patient?.gender || 'Unknown Gender';
  const aiSummary = fhirData.ai_summary || '';
  
  // Format records
  const formatRecord = (res, i) => {
    let title = 'Record';
    let subtitle = '';
    let details = '';
    let icon = '📄';
    let colorClass = 'blue';

    if (res.resourceType === 'Observation') {
      title = res.code?.text || res.code?.coding?.[0]?.display || 'Observation';
      const val = res.valueQuantity ? `${res.valueQuantity.value} ${res.valueQuantity.unit || ''}` : (res.valueString || '');
      subtitle = 'Vital / Lab';
      details = val;
      icon = '🧪';
      colorClass = 'teal';
    } else if (res.resourceType === 'Condition') {
      title = res.code?.text || 'Diagnosis';
      subtitle = res.clinicalStatus?.coding?.[0]?.code || 'Condition';
      details = res.onsetDateTime ? `Onset: ${res.onsetDateTime}` : '';
      icon = '❤️';
      colorClass = 'red';
    } else if (res.resourceType === 'MedicationStatement' || res.resourceType === 'MedicationRequest') {
      title = res.medicationCodeableConcept?.text || 'Medication';
      subtitle = res.dosage?.[0]?.text || 'Prescription';
      details = res.status || '';
      icon = '💊';
      colorClass = 'purple';
    } else if (res.resourceType === 'Encounter') {
      title = res.type?.[0]?.text || 'Clinical Visit';
      subtitle = res.period?.start || 'Visit';
      details = res.status || '';
      icon = '🏥';
      colorClass = 'orange';
    }

    return `
      <div class="card card-${colorClass}" onclick="openModal(${i})" style="cursor: pointer;">
        <div class="card-icon">${icon}</div>
        <div class="card-content">
          <h3 class="card-title">${title}</h3>
          <p class="card-subtitle">${subtitle}</p>
        </div>
        ${details ? `<div class="card-trailing">${details}</div>` : ''}
      </div>
    `;
  };

  const recordsHtml = records.length > 0 
    ? records.map((res, i) => formatRecord(res, i)).join('') 
    : '<div class="empty-state">No clinical records shared.</div>';

  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Health Passport - ${name}</title>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #F8FAFC; /* Clean Slate White */
      --accent-gold: #D4AF37;
      --navy-primary: #001B3D;
      --card-bg: #FFFFFF;
      --text-main: #001B3D;
      --text-sub: #64748B;
      --glass-border: #E2E8F0;
      
      --c-blue: #2563EB;
      --c-teal: #059669;
      --c-red: #DC2626;
      --c-purple: #7C3AED;
      --c-orange: #D97706;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }
    
    body {
      font-family: 'Outfit', 'Inter', system-ui, sans-serif;
      background: var(--bg);
      background-image: 
        radial-gradient(at 0% 0%, rgba(212, 175, 55, 0.03) 0px, transparent 50%),
        radial-gradient(at 100% 100%, rgba(0, 27, 61, 0.02) 0px, transparent 50%);
      color: var(--text-main);
      min-height: 100vh;
      line-height: 1.6;
      padding-bottom: 4rem;
    }

    .container {
      max-width: 650px;
      margin: 0 auto;
      padding: 2rem 1.5rem;
    }

    /* Hero Section */
    .hero {
      background: var(--navy-primary);
      border-top: 6px solid var(--accent-gold);
      border-radius: 24px;
      padding: 2.5rem;
      margin-bottom: 2.5rem;
      box-shadow: 0 20px 40px rgba(0, 27, 61, 0.15);
      animation: slideDown 0.8s cubic-bezier(0.16, 1, 0.3, 1) forwards;
      opacity: 0;
      position: relative;
      overflow: hidden;
      color: white;
    }
    .hero::before {
      content: 'NEXUS';
      position: absolute;
      top: -10px; right: -10px;
      font-size: 5rem;
      font-weight: 900;
      color: rgba(255,255,255,0.03);
      pointer-events: none;
    }

    .hero-header {
      display: flex;
      align-items: center;
      gap: 1.5rem;
      margin-bottom: 2rem;
    }

    .avatar {
      width: 72px;
      height: 72px;
      background: var(--accent-gold);
      border-radius: 20px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 32px;
      box-shadow: 0 8px 20px rgba(212, 175, 55, 0.3);
      color: white;
    }

    .hero h1 {
      font-size: 2.2rem;
      font-weight: 800;
      letter-spacing: -1px;
    }
    
    .hero-badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 0.4rem 1rem;
      background: rgba(255, 255, 255, 0.1);
      border: 1px solid rgba(255, 255, 255, 0.2);
      border-radius: 100px;
      font-size: 0.75rem;
      color: #FFFFFF;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 1px;
      margin-bottom: 1rem;
    }

    .hero-meta {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 1.5rem;
      border-top: 1px solid rgba(255,255,255,0.1);
      padding-top: 1.5rem;
    }

    .meta-item {
      display: flex;
      flex-direction: column;
    }

    .meta-label {
      font-size: 0.7rem;
      color: rgba(255,255,255,0.6);
      text-transform: uppercase;
      letter-spacing: 1.5px;
      margin-bottom: 0.25rem;
    }

    .meta-val {
      font-weight: 700;
      font-size: 1.2rem;
      color: #FFFFFF;
    }

    /* Section Title */
    .section-title {
      font-size: 1rem;
      font-weight: 800;
      margin-bottom: 1.5rem;
      display: flex;
      align-items: center;
      gap: 0.75rem;
      color: var(--navy-primary);
      text-transform: uppercase;
      letter-spacing: 2px;
    }
    .section-title::after {
      content: '';
      flex: 1;
      height: 2px;
      background: #E2E8F0;
    }

    /* Cards */
    .card-list {
      display: flex;
      flex-direction: column;
      gap: 1rem;
    }

    .card {
      background: var(--card-bg);
      border: 1px solid #E2E8F0;
      border-radius: 20px;
      padding: 1.5rem;
      display: flex;
      align-items: center;
      gap: 1.25rem;
      transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
      opacity: 0;
      transform: translateY(20px);
      animation: fadeUp 0.6s forwards cubic-bezier(0.16, 1, 0.3, 1);
      box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);
    }
    .card:hover {
      transform: translateY(-4px);
      border-color: var(--accent-gold);
      box-shadow: 0 10px 25px rgba(0, 27, 61, 0.08);
    }

    /* Staggered card animation */
    ${records.map((_, i) => `.card:nth-child(${i + 1}) { animation-delay: ${0.2 + (i * 0.06)}s; }`).join('\n')}

    .card-icon {
      width: 56px;
      height: 56px;
      border-radius: 16px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 28px;
      background: #F1F5F9;
      flex-shrink: 0;
      border: 1px solid #E2E8F0;
    }

    .card-blue .card-icon { color: var(--c-blue); background: #EFF6FF; }
    .card-teal .card-icon { color: var(--c-teal); background: #ECFDF5; }
    .card-red .card-icon { color: var(--c-red); background: #FEF2F2; }
    .card-purple .card-icon { color: var(--c-purple); background: #F5F3FF; }
    .card-orange .card-icon { color: var(--c-orange); background: #FFFBEB; }

    .card-content {
      flex: 1;
      min-width: 0;
    }

    .card-title {
      font-size: 1.15rem;
      font-weight: 700;
      color: var(--navy-primary);
    }

    .card-subtitle {
      font-size: 0.9rem;
      color: var(--text-sub);
      margin-top: 0.25rem;
    }

    .card-trailing {
      font-weight: 800;
      font-size: 1.15rem;
      text-align: right;
      padding: 0.5rem 1rem;
      background: #F8FAFC;
      border-radius: 12px;
      color: var(--navy-primary);
    }

    @keyframes slideDown {
      to { opacity: 1; transform: translateY(0); }
    }
    @keyframes fadeUp {
      to { opacity: 1; transform: translateY(0); }
    }

    /* Modal Styles */
    .modal-backdrop {
      position: fixed;
      top: 0; left: 0; width: 100%; height: 100%;
      background: rgba(0, 27, 61, 0.4);
      backdrop-filter: blur(8px);
      display: flex;
      align-items: center;
      justify-content: center;
      opacity: 0;
      pointer-events: none;
      transition: opacity 0.4s;
      z-index: 100;
      padding: 1.5rem;
    }
    .modal-backdrop.open {
      opacity: 1;
      pointer-events: all;
    }
    .modal-content {
      background: #FFFFFF;
      border-radius: 24px;
      width: 100%;
      max-width: 550px;
      max-height: 85vh;
      display: flex;
      flex-direction: column;
      transform: translateY(30px);
      transition: all 0.4s cubic-bezier(0.16, 1, 0.3, 1);
      box-shadow: 0 30px 60px rgba(0, 27, 61, 0.2);
    }
    .modal-backdrop.open .modal-content {
      transform: translateY(0);
    }
    .modal-header {
      padding: 1.75rem;
      border-bottom: 1px solid #F1F5F9;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .modal-header h2 { font-size: 1.4rem; color: var(--navy-primary); font-weight: 800; }
    .close-btn {
      background: #F1F5F9;
      border: none;
      color: var(--navy-primary);
      width: 36px;
      height: 36px;
      border-radius: 12px;
      cursor: pointer;
      font-size: 1.5rem;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: background 0.2s;
    }
    .close-btn:hover { background: #E2E8F0; }
    .modal-body {
      padding: 1.75rem;
      overflow-y: auto;
      font-family: 'Inter', sans-serif;
    }
    .data-object { display: flex; flex-direction: column; gap: 0.75rem; }
    .data-row { display: flex; flex-direction: column; padding: 1rem; background: #F8FAFC; border-radius: 12px; border: 1px solid #F1F5F9; }
    .data-key { font-size: 0.7rem; text-transform: uppercase; letter-spacing: 1.5px; color: var(--text-sub); margin-bottom: 0.4rem; font-weight: 700; }
    .data-val { font-size: 1rem; color: var(--navy-primary); line-height: 1.5; font-weight: 500; }
    .data-array-item { border-left: 3px solid var(--accent-gold); padding-left: 1rem; margin: 0.5rem 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="hero">
      <div class="hero-badge">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path><polyline points="22 4 12 14.01 9 11.01"></polyline></svg>
        NEXUS SECURE GATEWAY
      </div>
      <div class="hero-header">
        <div class="avatar">👤</div>
        <div>
          <h1>${name}</h1>
        </div>
      </div>
      <div class="hero-meta">
        <div class="meta-item">
          <span class="meta-label">Date of Birth</span>
          <span class="meta-val">${dob}</span>
        </div>
        <div class="meta-item">
          <span class="meta-label">Gender</span>
          <span class="meta-val" style="text-transform: capitalize;">${gender}</span>
        </div>
      </div>
    </div>

    ${aiSummary ? `
    <h2 class="section-title">✨ Clinical Insights</h2>
    <div class="card" style="margin-bottom: 2.5rem; border-left: 6px solid var(--accent-gold); background: #FFFFFF;">
      <div class="card-content">
        <p style="font-size: 1.1rem; line-height: 1.8; color: var(--navy-primary); font-weight: 500;">${aiSummary}</p>
      </div>
    </div>
    ` : ''}

    <h2 class="section-title">Clinical History</h2>
    <div class="card-list">
      ${recordsHtml}
    </div>
  </div>

  <div class="modal-backdrop" id="modal" onclick="closeModal(event)">
    <div class="modal-content" onclick="event.stopPropagation()">
      <div class="modal-header">
        <h2 id="modal-title">Record Details</h2>
        <button class="close-btn" onclick="closeModal(event)">&times;</button>
      </div>
      <div class="modal-body" id="modal-body"></div>
    </div>
  </div>

  <script>
    const rawRecords = ${JSON.stringify(records)};

    function renderObjectToHtml(obj) {
      if (obj === null || obj === undefined) return '<span class="val-empty">-</span>';
      if (typeof obj !== 'object') {
        return '<span class="val-primitive">' + String(obj) + '</span>';
      }
      
      if (Array.isArray(obj)) {
        if (obj.length === 0) return '<span class="val-empty">Empty</span>';
        let html = '<div class="data-array">';
        obj.forEach((item) => {
          html += '<div class="data-array-item">' + renderObjectToHtml(item) + '</div>';
        });
        html += '</div>';
        return html;
      }

      let html = '<div class="data-object">';
      for (const key in obj) {
        if (Object.hasOwnProperty.call(obj, key)) {
          // Format key cleanly (e.g. "resourceType" -> "Resource Type")
          const cleanKey = key.replace(/([A-Z])/g, ' $1').trim();
          html += '<div class="data-row"><div class="data-key">' + cleanKey + '</div><div class="data-val">' + renderObjectToHtml(obj[key]) + '</div></div>';
        }
      }
      html += '</div>';
      return html;
    }

    function openModal(index) {
      const record = rawRecords[index];
      document.getElementById('modal-title').innerText = record.resourceType + ' Details';
      document.getElementById('modal-body').innerHTML = renderObjectToHtml(record);
      document.getElementById('modal').classList.add('open');
      document.body.style.overflow = 'hidden';
    }

    function closeModal(e) {
      if (e) e.stopPropagation();
      document.getElementById('modal').classList.remove('open');
      document.body.style.overflow = '';
    }

    setInterval(() => {
      fetch(window.location.href, { headers: { 'Accept': 'application/json' } })
        .then(res => {
          if (!res.ok) {
            document.body.innerHTML = \`<div style="display:flex;height:100vh;align-items:center;justify-content:center"><div style="background:rgba(30,41,59,0.8);padding:2rem;border-radius:16px;max-width:400px;border:1px solid rgba(255,255,255,0.1);text-align:center;"><h1 style="color:#f43f5e;margin-top:0;">Not Authorized</h1><p>This secure health session has ended.</p></div></div>\`;
          }
        }).catch(() => {});
    }, 3000);
  </script>
</body>
</html>
  `;
};

module.exports = renderShareHtml;
