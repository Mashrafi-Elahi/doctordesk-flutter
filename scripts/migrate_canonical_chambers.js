const admin = require('firebase-admin');
const path = require('path');
const sa = require('../tools/serviceAccount.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(sa),
    projectId: 'docdesk-1e4cc',
  });
}
const db = admin.firestore();

const isApply = process.argv.includes('--apply');
const isDryRun = !isApply || process.argv.includes('--dry-run');

function parseStructuredHours(text) {
  if (!text || typeof text !== 'string') {
    return {
      days: [1, 2, 3, 4, 6, 7],
      start: '17:00',
      end: '21:00',
      display: 'Visiting hours not set',
    };
  }
  const clean = text.trim();
  
  // Default days: Sat-Thu (DateTime.weekday: Mon=1..Sun=7; Sat=6, Sun=7, Mon=1, Tue=2, Wed=3, Thu=4)
  let days = [1, 2, 3, 4, 6, 7];
  const lower = clean.toLowerCase();
  if (lower.includes('everyday') || lower.includes('daily')) {
    days = [1, 2, 3, 4, 5, 6, 7];
  } else if (lower.includes('sat') && lower.includes('thu')) {
    days = [1, 2, 3, 4, 6, 7];
  } else if (lower.includes('sun') && lower.includes('thu')) {
    days = [1, 2, 3, 4, 7];
  }

  // Parse time
  const match = clean.match(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:–|—|-|\bto\b)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/i);
  let startStr = '17:00';
  let endStr = '21:00';

  if (match) {
    let startH = parseInt(match[1], 10);
    let startM = match[2] ? parseInt(match[2], 10) : 0;
    const startP = match[3] ? match[3].toLowerCase() : null;

    let endH = parseInt(match[4], 10);
    let endM = match[5] ? parseInt(match[5], 10) : 0;
    const endP = match[6] ? match[6].toLowerCase() : null;

    if (startP === 'pm' && startH < 12) startH += 12;
    if (startP === 'am' && startH === 12) startH = 0;
    if (endP === 'pm' && endH < 12) endH += 12;
    if (endP === 'am' && endH === 12) endH = 0;

    if (!startP && endP === 'pm' && startH < 12 && endH >= 12) {
      startH += 12;
    }
    if (!startP && !endP && startH >= 1 && startH <= 7 && endH <= 11) {
      startH += 12;
      endH += 12;
    }

    startStr = `${String(startH).padStart(2, '0')}:${String(startM).padStart(2, '0')}`;
    endStr = `${String(endH).padStart(2, '0')}:${String(endM).padStart(2, '0')}`;
  }

  return {
    days,
    start: startStr,
    end: endStr,
    display: clean,
  };
}

async function runMigration() {
  console.log(`====================================================`);
  console.log(`CANONICAL CHAMBER MIGRATION`);
  console.log(`Mode: ${isDryRun ? 'DRY RUN (Read-only, NO changes will be written)' : 'APPLY (Writing changes to Firestore)'}`);
  console.log(`====================================================\n`);

  // Target Canonical Chambers definition
  // 1. Chamber Bup:
  //    Canonical ID: chamber-1793458283033
  //    Owner Doctor: Dr. Mashrafi Elahi (doctor_mMOqrPAdtIRH5a76t7Fx1ky8Bp83)
  //    Visiting Doctor: Dr. Nuzhat Saima (doctor_nuzhat_saima)
  //    Aliases: ['chamber-1793458283033', 'Bup', 'chamber-bup-1', 'Bup Medical']
  //    Hours: 5:00 PM – 9:00 PM (Sat–Thu)
  //    slotMinutes: 10
  //    fee: 800
  //    area: Mirpur Cantonment
  //    address: Mirpur Cantonment, Dhaka
  //    isAccessible: true

  const plannedWrites = [];

  // 1. Canonical Bup Chamber
  const bupCanonicalId = 'chamber-1793458283033';
  const bupStructuredHours = parseStructuredHours('5:00 PM – 9:00 PM (Sat–Thu)');
  const bupDoc = {
    id: bupCanonicalId,
    chamberId: bupCanonicalId,
    name: 'Bup',
    hospitalName: 'Bup',
    address: 'Mirpur Cantonment, Dhaka',
    area: 'Mirpur Cantonment',
    location: 'Dhaka',
    lat: 23.8398,
    lng: 90.3582,
    visitingHours: bupStructuredHours,
    visitingHoursDisplay: bupStructuredHours.display,
    slotMinutes: 10,
    ownerDoctorId: 'doctor_mMOqrPAdtIRH5a76t7Fx1ky8Bp83',
    doctorIds: ['doctor_mMOqrPAdtIRH5a76t7Fx1ky8Bp83', 'doctor_nuzhat_saima'],
    members: {
      'doctor_mMOqrPAdtIRH5a76t7Fx1ky8Bp83': 'owner',
      'doctor_nuzhat_saima': 'visiting',
    },
    isAccessible: true,
    accessibilityFeatures: ['Ramp', 'Accessible washroom', 'Lift/Elevator', 'Wheelchair entrance'],
    fee: 800,
    aliases: ['chamber-1793458283033', 'Bup', 'chamber-bup-1', 'Bup Medical'],
    hasOperator: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  plannedWrites.push({
    collection: 'chambers',
    docId: bupCanonicalId,
    data: bupDoc,
    action: 'SET (merge)',
    reason: 'Canonical chamber doc for Bup with structured hours, owner & visiting doctors',
  });

  // 2. Alias document for chamber-bup-1 (keeps existing ID, points to canonical record)
  const bupAliasDoc = {
    id: 'chamber-bup-1',
    chamberId: 'chamber-bup-1',
    canonicalChamberId: bupCanonicalId,
    name: 'Bup Medical',
    hospitalName: 'Bup Medical',
    area: 'Mirpur Cantonment',
    location: 'Dhaka',
    ownerDoctorId: 'doctor_mMOqrPAdtIRH5a76t7Fx1ky8Bp83',
    doctorIds: ['doctor_mMOqrPAdtIRH5a76t7Fx1ky8Bp83', 'doctor_nuzhat_saima'],
    visitingHours: bupStructuredHours,
    visitingHoursDisplay: bupStructuredHours.display,
    slotMinutes: 10,
    fee: 800,
    isAccessible: true,
    aliases: ['chamber-1793458283033', 'Bup', 'chamber-bup-1', 'Bup Medical'],
    isAlias: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  plannedWrites.push({
    collection: 'chambers',
    docId: 'chamber-bup-1',
    data: bupAliasDoc,
    action: 'SET (merge)',
    reason: 'Alias document keeping chamber-bup-1 ID and mapping to canonical Bup',
  });

  // 3. Update existing top-level chambers to conform to canonical schema
  const existingChambersSnap = await db.collection('chambers').get();
  console.log(`Scanned ${existingChambersSnap.size} existing chambers in chambers collection.`);
  
  for (const cDoc of existingChambersSnap.docs) {
    if (cDoc.id === bupCanonicalId || cDoc.id === 'chamber-bup-1') continue;

    const d = cDoc.data();
    // Only update if missing doctorIds or visitingHours
    const docId = d.doctorId || null;
    const existingHours = d.visitingHours || d.hours || null;
    const structuredHours = typeof existingHours === 'object' && existingHours?.days
      ? existingHours
      : parseStructuredHours(typeof existingHours === 'string' ? existingHours : null);

    const docIds = d.doctorIds || (docId ? [docId] : []);
    const members = d.members || (docId ? { [docId]: 'owner' } : {});
    const aliases = [...new Set([cDoc.id, d.name, d.hospitalName, d.chamberName, ...(d.aliases || [])].filter(Boolean))];

    plannedWrites.push({
      collection: 'chambers',
      docId: cDoc.id,
      data: {
        id: cDoc.id,
        name: d.name || d.hospitalName || 'Chamber',
        address: d.location || d.address || '',
        area: d.area || '',
        visitingHours: structuredHours,
        visitingHoursDisplay: structuredHours.display,
        slotMinutes: d.slotMinutes || 10,
        ownerDoctorId: d.ownerDoctorId || docId || null,
        doctorIds: docIds,
        members: members,
        isAccessible: d.isAccessible ?? false,
        fee: d.fee ?? 500,
        aliases: aliases,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      action: 'SET (merge)',
      reason: `Upgrade existing chamber ${cDoc.id} to canonical model`,
    });
  }

  // Print Summary of Planned Writes
  console.log(`\n================== MIGRATION PLAN SUMMARY ==================`);
  console.log(`Total Planned Writes: ${plannedWrites.length}`);
  console.log(`Sample Canonical Chamber (Bup - ${bupCanonicalId}):`);
  console.log(JSON.stringify(bupDoc, null, 2));
  console.log(`\nSample Alias Chamber (chamber-bup-1):`);
  console.log(JSON.stringify(bupAliasDoc, null, 2));
  console.log(`\nOther Chambers to upgrade: ${plannedWrites.length - 2} documents.`);

  if (isDryRun) {
    console.log(`\n[DRY RUN COMPLETE] No documents were written or modified. Use --apply to execute after confirmation.`);
    return;
  }

  // Execute writes in batches of 400
  console.log(`\nApplying ${plannedWrites.length} writes to Firestore...`);
  const batchSize = 400;
  for (let i = 0; i < plannedWrites.length; i += batchSize) {
    const chunk = plannedWrites.slice(i, i + batchSize);
    const batch = db.batch();
    for (const item of chunk) {
      const ref = db.collection(item.collection).doc(item.docId);
      batch.set(ref, item.data, { merge: true });
    }
    await batch.commit();
    console.log(`Committed chunk ${i + 1} - ${Math.min(i + batchSize, plannedWrites.length)}`);
  }
  console.log(`\n[SUCCESS] Canonical chamber migration completed successfully!`);
}

runMigration().catch(console.error).finally(() => process.exit(0));
