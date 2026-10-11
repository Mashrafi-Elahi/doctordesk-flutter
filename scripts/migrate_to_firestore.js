require('dotenv').config();
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { parse } = require('csv-parse/sync');
const admin = require('firebase-admin');
const geofire = require('geofire-common');

// 1. Locate dataset files (works from backend or flutter folder)
const candidateCsvDirs = [
  path.join(__dirname, '..', 'doctordirectory'),
  path.join(__dirname, '..', '..', 'doctordesk-flutter', 'doctordirectory'),
  path.join(__dirname, '..', '..', 'doctordesk-backend', 'doctordirectory'),
];

let csvPath = null;
let geocodedPath = null;

for (const dir of candidateCsvDirs) {
  const pCsv = path.join(dir, 'doctors_processed_data.csv');
  const pGeo = path.join(dir, 'chambers_geocoded.json');
  if (fs.existsSync(pCsv)) {
    csvPath = pCsv;
    geocodedPath = pGeo;
    break;
  }
}

if (!csvPath || !fs.existsSync(csvPath)) {
  console.error('ERROR: Could not find doctors_processed_data.csv in any expected directory.');
  process.exit(1);
}

// 2. Initialize Firebase Admin SDK idempotently
const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!serviceAccountPath) {
  console.error('ERROR: GOOGLE_APPLICATION_CREDENTIALS environment variable is not set.');
  console.error('Please set it to the path of your Firebase service account JSON key:');
  console.error('  $env:GOOGLE_APPLICATION_CREDENTIALS="C:\\path\\to\\serviceAccountKey.json"');
  process.exit(1);
}

if (!fs.existsSync(serviceAccountPath)) {
  console.error('ERROR: Service account file not found at path in GOOGLE_APPLICATION_CREDENTIALS.');
  process.exit(1);
}

if (!admin.apps.length) {
  try {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccountPath),
    });
  } catch (err) {
    console.error('Failed to initialize Firebase Admin SDK:', err.message);
    process.exit(1);
  }
}

const db = admin.firestore();

function safeParseList(str) {
  if (!str) return [];
  try {
    return str
      .replace(/^\[|\]$/g, '')
      .split("', '")
      .map((s) => s.replace(/^'|'$/g, '').replace(/^"|"$/g, '').trim())
      .filter(Boolean);
  } catch {
    return [];
  }
}

function extractDesignation(name) {
  const regex = /^(Prof\.|Assoc\. Prof\.|Asst\. Prof\.|Dr\.|Consultant|Professor|Asst\.|Assoc\.|Dr)\s+/i;
  const match = name.match(regex);
  return match ? match[0].trim() : null;
}

// Helper to commit batched writes (Firestore limit: 500 ops per batch)
class FirestoreBatchWriter {
  constructor(db, maxBatchSize = 450) {
    this.db = db;
    this.maxBatchSize = maxBatchSize;
    this.batch = db.batch();
    this.opCount = 0;
    this.totalCommitted = 0;
  }

  set(docRef, data, options = { merge: true }) {
    this.batch.set(docRef, data, options);
    this.opCount++;
    if (this.opCount >= this.maxBatchSize) {
      return this.commit();
    }
    return Promise.resolve();
  }

  async commit() {
    if (this.opCount === 0) return;
    await this.batch.commit();
    this.totalCommitted += this.opCount;
    this.opCount = 0;
    this.batch = this.db.batch();
  }

  async flush() {
    if (this.opCount > 0) {
      await this.commit();
    }
    return this.totalCommitted;
  }
}

async function main() {
  console.log('Reading CSV and geocoded chambers dataset...');
  const csvRaw = fs.readFileSync(csvPath, 'utf-8');
  const rows = parse(csvRaw, { columns: true, skip_empty_lines: true });

  let geocoded = {};
  if (geocodedPath && fs.existsSync(geocodedPath)) {
    try {
      geocoded = JSON.parse(fs.readFileSync(geocodedPath, 'utf-8'));
    } catch (e) {
      console.warn('Warning: Failed to parse chambers_geocoded.json, continuing with empty geo cache.');
    }
  }

  const doctorMap = new Map();
  const specialtyCounts = new Map();

  for (const row of rows) {
    const rawId = (row['Doctor ID'] || '').trim();
    if (!rawId) continue;
    const docId = `doctor_${rawId}`;
    const name = (row['Doctor Name'] || '').trim();
    const chamberRaw = (row['Chamber'] || '').trim();
    const location = (row['Location'] || '').trim();
    const geo = geocoded[chamberRaw];

    const [hospitalName = '', area = ''] = chamberRaw.split('|').map((s) => s.trim());

    const chamber = {
      hospitalName,
      area,
      location,
      wheelchairEntrance: false,
      wheelchairParking: false,
      liftAvailable: false,
      accessibleToilet: false,
    };

    if (geo && typeof geo.lat === 'number' && typeof geo.lng === 'number' && geo.lat !== null && geo.lng !== null) {
      chamber.lat = geo.lat;
      chamber.lng = geo.lng;
    }

    const exp = parseFloat(row['Experience']) || 0;
    const speciality = (row['Speciality'] || '').trim();
    const education = safeParseList(row['Education']);
    const concentrations = safeParseList(row['Concentration']);

    if (speciality) {
      specialtyCounts.set(speciality, (specialtyCounts.get(speciality) || 0) + 1);
    }

    if (!doctorMap.has(docId)) {
      doctorMap.set(docId, {
        id: docId,
        rawId,
        name,
        name_lower: name.toLowerCase(),
        designation: extractDesignation(name),
        education: new Set(),
        specialities: new Set(),
        experienceYears: 0,
        concentrations: new Set(),
        chambers: [],
        chamberKeys: new Set(),
        bmdcRegNumber: null,
        isBmdcVerified: false,
        isClaimed: false,
        claimedByUid: null,
        certificateImageUrl: null,
        ratingAverage: 0,
        ratingCount: 0,
        bayesianRating: 4.25, // Default Bayesian prior
      });
    }

    const doc = doctorMap.get(docId);
    education.forEach((e) => doc.education.add(e));
    if (speciality) doc.specialities.add(speciality);
    concentrations.forEach((c) => doc.concentrations.add(c));

    if (exp > doc.experienceYears) {
      doc.experienceYears = exp;
    }

    const chamberKey = `${hospitalName}|${location}`;
    if (!doc.chamberKeys.has(chamberKey)) {
      doc.chamberKeys.add(chamberKey);
      doc.chambers.push(chamber);
    }
  }

  const doctorsList = Array.from(doctorMap.values()).map((doc) => ({
    id: doc.id,
    name: doc.name,
    name_lower: doc.name_lower,
    designation: doc.designation,
    education: Array.from(doc.education),
    specialities: Array.from(doc.specialities),
    experienceYears: doc.experienceYears,
    concentrations: Array.from(doc.concentrations),
    chambers: doc.chambers,
    bmdcRegNumber: doc.bmdcRegNumber,
    isBmdcVerified: doc.isBmdcVerified,
    isClaimed: doc.isClaimed,
    claimedByUid: doc.claimedByUid,
    certificateImageUrl: doc.certificateImageUrl,
    ratingAverage: doc.ratingAverage,
    ratingCount: doc.ratingCount,
    bayesianRating: doc.bayesianRating,
  }));

  console.log(`Parsed ${doctorsList.length} distinct doctors from CSV.`);

  // Prepare top-level chambers with geohashes (skip null lat/lng as required)
  const chambersList = [];
  for (const doc of doctorsList) {
    doc.chambers.forEach((ch, idx) => {
      if (typeof ch.lat === 'number' && typeof ch.lng === 'number') {
        const hashStr = crypto.createHash('md5').update(`${doc.id}_${ch.hospitalName}_${ch.location}`).digest('hex').substring(0, 16);
        const chamberDocId = `${doc.id}_chamber_${hashStr}`;
        const geohash = geofire.geohashForLocation([ch.lat, ch.lng]);

        chambersList.push({
          id: chamberDocId,
          doctorId: doc.id,
          hospitalName: ch.hospitalName,
          area: ch.area,
          location: ch.location,
          lat: ch.lat,
          lng: ch.lng,
          geohash,
          wheelchairEntrance: ch.wheelchairEntrance || false,
          wheelchairParking: ch.wheelchairParking || false,
          liftAvailable: ch.liftAvailable || false,
          accessibleToilet: ch.accessibleToilet || false,
        });
      }
    });
  }

  console.log(`Prepared ${chambersList.length} geocoded chambers with geohashes.`);

  // Prepare meta/specialities list
  const specialitiesArray = Array.from(specialtyCounts.entries())
    .map(([speciality, count]) => ({ speciality, count }))
    .sort((a, b) => b.count - a.count);

  console.log(`Prepared meta/specialities with ${specialitiesArray.length} distinct specialties.`);

  // Write to Firestore in batches
  const writer = new FirestoreBatchWriter(db);

  console.log('Writing doctors to Firestore collection "doctors"...');
  let docCount = 0;
  for (const doctor of doctorsList) {
    const docRef = db.collection('doctors').doc(doctor.id);
    await writer.set(docRef, doctor, { merge: true });
    docCount++;
    if (docCount % 500 === 0) {
      console.log(`  Buffered/committed ${docCount} / ${doctorsList.length} doctors...`);
    }
  }

  console.log('Writing geocoded chambers to Firestore collection "chambers"...');
  for (const chamber of chambersList) {
    const chamberRef = db.collection('chambers').doc(chamber.id);
    await writer.set(chamberRef, chamber, { merge: true });
  }

  console.log('Writing meta/specialities document...');
  const metaRef = db.collection('meta').doc('specialities');
  await writer.set(metaRef, {
    list: specialitiesArray,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  console.log('Writing config/specialty_rules document (grouped by specialty arrays)...');
  const configRef = db.collection('config').doc('specialty_rules');
  await writer.set(configRef, {
    version: 1,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    rules: {
      "Cardiologist": [
        "chest pain", "heart pain", "heart problem", "chest tightness", "chest pressure",
        "palpitation", "heart attack", "cardiac", "buk e batha", "buke batha", "buk batha",
        "buker batha", "buke chap", "buke jala", "hrider shomossha", "hridrog", "harte shomossha",
        "হার্ট", "বুকে ব্যথা", "বুকের ব্যথা", "বুকে চাপ", "বুকে জ্বালা", "হৃদরোগ", "হার্টের সমস্যা",
        "high blood pressure", "hypertension", "high bp", "pressure problem", "blood pressure",
        "uccho rokto chap", "high pressure", "preshar beshi", "উচ্চ রক্তচাপ", "হাই প্রেসার", "রক্তচাপ"
      ],
      "General Physician": [
        "fever", "high temperature", "chills", "body ache", "viral fever", "weakness",
        "jwor", "jor", "gae jor", "shorir batha", "gae batha", "kapuni", "durbolota",
        "headache", "matha batha", "mathar batha", "জ্বর", "গায়ে জ্বর", "শরীর ব্যথা",
        "দুর্বলতা", "মাথা ব্যথা", "মাথার ব্যথা"
      ],
      "Endocrinologist": [
        "diabetes", "sugar problem", "high sugar", "thyroid", "thyroid problem", "hormone problem",
        "shugare shomossha", "ডায়াবেটিস", "সুগার", "থাইরয়েড"
      ],
      "Gastroenterologist": [
        "acidity", "gas", "gastric", "stomach pain", "pet batha", "pete batha", "vomiting", "bomi",
        "গ্যাস", "গ্যাস্ট্রিক", "পেট ব্যথা", "বমি"
      ],
      "Dermatologist": [
        "skin problem", "rash", "itching", "acne", "chulkani", "chamra", "দাদ", "চুলকানি", "ব্রণ"
      ],
      "Orthopedic": [
        "bone fracture", "joint pain", "back pain", "haddi", "komor batha", "হাড়", "কোমর ব্যথা"
      ],
      "ENT Specialist": [
        "ear pain", "throat pain", "kan batha", "gola batha", "hearing problem", "কান ব্যথা", "গলা ব্যথা"
      ],
      "Neurologist": [
        "migraine", "stroke", "seizure", "paralysis", "epilepsy", "mirgi", "মাইগ্রেন", "স্ট্রোক"
      ],
      "Pediatrician": [
        "child doctor", "baby fever", "shishu", "baccha", "বাচ্চা", "শিশু"
      ],
      "Gynecologist": [
        "pregnancy", "period problem", "gynae", "mashik", "গর্ভবতী", "মাসিক"
      ]
    }
  }, { merge: true });

  // Flush remaining batch
  const total = await writer.flush();
  console.log(`\n======================================================`);
  console.log(`Migration Complete (Idempotent)!`);
  console.log(`Total Firestore operations committed: ${total}`);
  console.log(`  - Doctors: ${doctorsList.length} documents in 'doctors'`);
  console.log(`  - Chambers: ${chambersList.length} documents in 'chambers'`);
  console.log(`  - Meta: 'meta/specialities' created with ${specialitiesArray.length} specialities`);
  console.log(`======================================================`);
}

main().catch((err) => {
  console.error('Fatal migration error:', err);
  process.exit(1);
});
