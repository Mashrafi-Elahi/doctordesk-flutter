const fs = require('fs');
const path = require('path');
const { parse } = require('csv-parse/sync');

const csvPath = path.join(__dirname, '..', 'doctordirectory', 'doctors_processed_data.csv');
const geoPath = path.join(__dirname, '..', 'doctordirectory', 'chambers_geocoded.json');

const content = fs.readFileSync(csvPath, 'utf8');
const records = parse(content, { columns: true, skip_empty_lines: true });

let geocoded = {};
if (fs.existsSync(geoPath)) {
  geocoded = JSON.parse(fs.readFileSync(geoPath, 'utf8'));
}

console.log('Total CSV rows parsed:', records.length);

const doctorMap = new Map();

// Seed Dr. Nuzhat Saima first so she appears in Top Doctors & BUP Medical searches
doctorMap.set('doctor_nuzhat_saima', {
  _id: 'doctor_nuzhat_saima',
  name: 'Dr. Nuzhat Saima',
  specialities: ['General Medicine', 'MEDICINE SPECIALIST'],
  experienceYears: 5,
  education: ['MBBS'],
  designation: 'Consultant Physician',
  bmdcRegNumber: '',
  isBmdcVerified: false,
  ratingAverage: 4.9,
  ratingCount: 4,
  chambers: [{
    id: 'chamber-bup-1',
    hospitalName: 'Bup Medical',
    area: 'Mirpur Cantonment',
    location: 'Dhaka',
    lat: 23.8398,
    lng: 90.3582,
    visitingHours: '9:00 AM - 5:00 PM',
    fee: 500,
    isAccessible: true,
    accessibilityFeatures: ['Ramp', 'Ground floor', 'Accessible washroom'],
    wheelchairEntrance: true,
    accessibleToilet: true,
  }],
});

records.forEach((r, index) => {
  const id = 'doc_' + (r['Doctor ID'] || (index + 1)).toString().trim();
  const rawName = (r['Doctor Name'] || '').trim();
  const specs = (r['Speciality'] || 'General Medicine')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  const exp = parseFloat(r['Experience']) || 5.0;

  let edu = [];
  try {
    const rawEdu = r['Education'] || '';
    if (rawEdu.startsWith('[')) {
      edu = JSON.parse(rawEdu.replace(/'/g, '"'));
    } else {
      edu = rawEdu.split(',').map((s) => s.trim()).filter(Boolean);
    }
  } catch (_) {
    edu = ['MBBS'];
  }

  const chamberRaw = (r['Chamber'] || '').trim();
  const [hospitalPart = '', areaPart = ''] = chamberRaw.split('|').map((s) => s.trim());
  const loc = (r['Location'] || 'Dhaka').trim();

  let lat = null;
  let lng = null;
  let area = areaPart || loc;

  if (geocoded[chamberRaw] && typeof geocoded[chamberRaw].lat === 'number') {
    lat = geocoded[chamberRaw].lat;
    lng = geocoded[chamberRaw].lng;
    area = geocoded[chamberRaw].location || area;
  } else {
    for (const [key, val] of Object.entries(geocoded)) {
      if (chamberRaw.toLowerCase().includes(key.toLowerCase().trim())) {
        lat = val.lat;
        lng = val.lng;
        area = val.location || area;
        break;
      }
    }
  }

  if (!lat || !lng) {
    const lowerCh = chamberRaw.toLowerCase();
    const lowerLoc = loc.toLowerCase();
    if (lowerCh.includes('mirpur') || lowerLoc.includes('mirpur')) {
      lat = 23.8223; lng = 90.3654; area = 'Mirpur';
    } else if (lowerCh.includes('dhanmondi') || lowerLoc.includes('dhanmondi')) {
      lat = 23.7465; lng = 90.3760; area = 'Dhanmondi';
    } else if (lowerCh.includes('gulshan') || lowerLoc.includes('gulshan')) {
      lat = 23.7925; lng = 90.4078; area = 'Gulshan';
    } else if (lowerCh.includes('uttara') || lowerLoc.includes('uttara')) {
      lat = 23.8759; lng = 90.3795; area = 'Uttara';
    } else if (lowerCh.includes('banani') || lowerLoc.includes('banani')) {
      lat = 23.7937; lng = 90.4066; area = 'Banani';
    } else if (lowerCh.includes('bup') || lowerLoc.includes('cantonment')) {
      lat = 23.8398; lng = 90.3582; area = 'Mirpur Cantonment';
    } else {
      lat = 23.7806; lng = 90.4150;
    }
  }

  let formattedName = rawName;
  if (
    !formattedName.startsWith('Dr.') &&
    !formattedName.startsWith('Prof.') &&
    !formattedName.startsWith('Asst.') &&
    !formattedName.startsWith('Assoc.')
  ) {
    formattedName = 'Dr. ' + formattedName;
  }

  const chamberObj = {
    hospitalName: hospitalPart || chamberRaw || 'Dhaka Central Consultation Chamber',
    area: area,
    location: loc,
    lat: lat,
    lng: lng,
    visitingHours: '5:00 PM - 9:00 PM',
    fee: 800,
    isAccessible: (index % 4 === 0),
    accessibilityFeatures: (index % 4 === 0) ? ['Lift/Elevator', 'Ramp'] : [],
    wheelchairEntrance: (index % 4 === 0),
  };

  if (!doctorMap.has(id)) {
    doctorMap.set(id, {
      _id: id,
      name: formattedName,
      specialities: [...new Set(specs.length ? specs : ['General Medicine'])],
      experienceYears: exp,
      education: [...new Set(edu.length ? edu : ['MBBS'])],
      designation: r['Designation'] || 'Specialist Consultant',
      bmdcRegNumber: '',
      isBmdcVerified: false,
      ratingAverage: Number((4.3 + ((index % 7) * 0.1)).toFixed(1)),
      ratingCount: (index % 15) + 1,
      chambers: [chamberObj],
    });
  } else {
    // Merge multiple entries (multiple specialties / chambers) for the same doctor
    const existing = doctorMap.get(id);
    for (const s of specs) {
      if (!existing.specialities.includes(s)) {
        existing.specialities.push(s);
      }
    }
    for (const e of edu) {
      if (!existing.education.includes(e)) {
        existing.education.push(e);
      }
    }
    if (exp > existing.experienceYears) {
      existing.experienceYears = exp;
    }
    const chKey = `${chamberObj.hospitalName}|${chamberObj.location}`;
    const hasChamber = existing.chambers.some(
      (c) => `${c.hospitalName}|${c.location}` === chKey
    );
    if (!hasChamber) {
      existing.chambers.push(chamberObj);
    }
  }
});

const doctors = Array.from(doctorMap.values());

const outDir = path.join(__dirname, '..', 'assets', 'data');
if (!fs.existsSync(outDir)) {
  fs.mkdirSync(outDir, { recursive: true });
}

const outPath = path.join(outDir, 'bundled_doctors.json');
fs.writeFileSync(outPath, JSON.stringify(doctors));
const stat = fs.statSync(outPath);
console.log(
  `Successfully generated ${outPath} with ${doctors.length} unique merged doctors. Size: ${(
    stat.size /
    1024 /
    1024
  ).toFixed(2)} MB`
);
