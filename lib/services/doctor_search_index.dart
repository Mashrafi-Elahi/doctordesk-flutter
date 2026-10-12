/// Search-index helpers shared by Firestore directory writes and reads.
/// Bengali code points are intentionally preserved; only separators and
/// punctuation are normalized for consistent token matching.
///
/// INDEXING STRATEGY
/// -----------------
/// Each doctor document gets three parallel search fields:
///   searchText    – full normalized string for contains() matching
///   searchTokens  – individual tokens for equality matching
///   searchPrefixes– every 2-to-16 char prefix for startsWith / arrayContainsAny
///
/// The index is enriched with:
///   • Doctor name tokens + all known aliases (Md ↔ Mohammad, Dr ↔ Doctor, etc.)
///   • Specialty canonical names + all known abbreviations (ENT, Gynae, Ortho…)
///   • Symptom keywords mapped to the doctor's specialty (chest pain → Cardiology)
///   • Chamber hospital name, area, location
///   • Education / degree tokens
///   • Hard-coded doctor title tokens (dr, doc, ডা…)
class DoctorSearchIndex {
  DoctorSearchIndex._();

  static final RegExp _separators = RegExp(r'[^a-z0-9\u0980-\u09ff]+');

  /// Common doctor titles and honorifics in English and Bangla.
  static const Set<String> titleTokens = {
    'dr',
    'doc',
    'doctor',
    'physician',
    'prof',
    'professor',
    'asst',
    'assoc',
    'ডা',
    'ডাঃ',
    'ডাক্তার',
    'প্রফেসর',
    'চিকিৎসক',
  };

  /// Common Bangladeshi name aliases and spelling variants.
  static const Map<String, List<String>> _nameAliases = {
    'md': ['mohammad', 'mohammed', 'muhammad'],
    'mohammad': ['md'],
    'mohammed': ['md'],
    'muhammad': ['md'],
    'dr': ['doctor', 'doc', 'ডা', 'ডাক্তার'],
    'doctor': ['dr', 'doc', 'ডা', 'ডাক্তার'],
    'doc': ['dr', 'doctor'],
    'prof': ['professor', 'প্রফেসর'],
    'professor': ['prof', 'প্রফেসর'],
    'ডা': ['dr', 'doctor', 'ডাক্তার'],
    'ডাক্তার': ['dr', 'doctor', 'ডা'],
  };

  /// Bidirectional specialty abbreviation / synonym map.
  /// Keys and values are lowercase normalized tokens.
  static const Map<String, List<String>> specialtyAbbreviations = {
    'ent': [
      'otolaryngology', 'otolaryngologist', 'otolaryngologists', 'ent specialist',
      'ear nose throat', 'ear', 'nose', 'throat', 'ইএনটি', 'নাক কান গলা',
    ],
    'ent specialist': [
      'ent', 'otolaryngology', 'otolaryngologist', 'otolaryngologists',
      'ear nose throat', 'ইএনটি',
    ],
    'otolaryngology': ['ent', 'ent specialist', 'ear nose throat', 'otolaryngologist', 'otolaryngologists', 'ইএনটি'],
    'otolaryngologist': ['ent', 'ent specialist', 'ear nose throat', 'otolaryngology', 'otolaryngologists', 'ইএনটি'],
    'otolaryngologists': ['ent', 'ent specialist', 'ear nose throat', 'otolaryngology', 'otolaryngologist', 'ইএনটি'],
    'gyn': [
      'gynecology', 'obstetrics', 'gynecologist', 'obstetrician',
      'obgyn', 'obs', 'gynae', 'গায়নি', 'স্ত্রী রোগ',
    ],
    'gynae': [
      'gynecology', 'obstetrics', 'gynecologist', 'obstetrician',
      'obgyn', 'obs', 'gyn', 'গায়নি',
    ],
    'gyne': ['gynecology', 'obstetrics', 'gynecologist', 'obgyn', 'gynae'],
    'obgyn': ['gynecology', 'obstetrics', 'gynecologist', 'gynae', 'obs', 'gyn'],
    'obs': ['obstetrics', 'gynecology', 'obgyn', 'gynae', 'gyn'],
    'gynecology': ['gyn', 'gynae', 'gyne', 'obgyn', 'obs', 'gynecologist', 'গায়নি'],
    'gynecologist': ['gyn', 'gynae', 'gyne', 'obgyn', 'obs', 'gynecology', 'গায়নি'],
    'gynecologists': ['gyn', 'gynae', 'obgyn', 'gynecology', 'gynecologist', 'গায়নি'],
    'ortho': ['orthopedics', 'orthopedic', 'orthopedist', 'orthopaedic', 'অর্থোপেডিক'],
    'orthopedics': ['ortho', 'orthopedic', 'orthopedist', 'orthopaedic', 'অর্থোপেডিক'],
    'orthopedic': ['ortho', 'orthopedics', 'orthopedist'],
    'orthopedist': ['ortho', 'orthopedics', 'orthopedic'],
    'cardio': ['cardiology', 'cardiologist', 'heart', 'কার্ডিওলজি', 'হৃদরোগ'],
    'cardiology': ['cardio', 'cardiologist', 'heart', 'হৃদরোগ'],
    'cardiologist': ['cardio', 'cardiology', 'heart', 'হৃদরোগ'],
    'heart': ['cardiology', 'cardiologist', 'cardio', 'হৃদরোগ'],
    'derm': ['dermatology', 'dermatologist', 'skin', 'derma', 'চর্মরোগ'],
    'derma': ['dermatology', 'dermatologist', 'skin', 'derm', 'চর্মরোগ'],
    'skin': ['dermatology', 'dermatologist', 'derm', 'derma', 'চর্মরোগ'],
    'dermatology': ['derm', 'derma', 'skin', 'dermatologist', 'চর্মরোগ'],
    'dermatologist': ['derm', 'derma', 'skin', 'dermatology', 'চর্মরোগ'],
    'peds': ['pediatrics', 'pediatrician', 'ped', 'paed', 'paeds', 'child', 'শিশু'],
    'ped': ['pediatrics', 'pediatrician', 'peds', 'paed', 'paeds', 'child', 'শিশু'],
    'paed': ['pediatrics', 'pediatrician', 'peds', 'ped', 'paeds', 'child', 'শিশু'],
    'paeds': ['pediatrics', 'pediatrician', 'peds', 'ped', 'paed', 'child', 'শিশু'],
    'pediatrics': ['peds', 'ped', 'paed', 'paeds', 'child', 'pediatrician', 'শিশু'],
    'pediatrician': ['peds', 'ped', 'paed', 'paeds', 'child', 'pediatrics', 'শিশু'],
    'child': ['pediatrics', 'pediatrician', 'peds', 'paed', 'শিশু'],
    'eye': ['ophthalmology', 'ophthalmologist', 'ophth', 'ophthal', 'চক্ষু'],
    'ophth': ['ophthalmology', 'ophthalmologist', 'eye', 'ophthal', 'চক্ষু'],
    'ophthal': ['ophthalmology', 'ophthalmologist', 'eye', 'ophth', 'চক্ষু'],
    'ophthalmology': ['eye', 'ophth', 'ophthal', 'ophthalmologist', 'চক্ষু'],
    'ophthalmologist': ['eye', 'ophth', 'ophthal', 'ophthalmology', 'চক্ষু'],
    'dent': ['dentistry', 'dentist', 'dental', 'দাঁত', 'ডেন্টাল'],
    'dental': ['dentistry', 'dentist', 'dent', 'দাঁত', 'ডেন্টাল'],
    'dentistry': ['dent', 'dental', 'dentist', 'দাঁত', 'ডেন্টাল'],
    'dentist': ['dent', 'dental', 'dentistry', 'দাঁত', 'ডেন্টাল'],
    'med': ['general medicine', 'medicine', 'internal medicine', 'gp', 'gen med', 'মেডিসিন'],
    'gen med': ['general medicine', 'medicine', 'internal medicine', 'gp', 'med', 'মেডিসিন'],
    'gp': ['general medicine', 'medicine', 'general physician', 'gen med', 'med', 'মেডিসিন'],
    'medicine': ['general medicine', 'med', 'gen med', 'internal medicine', 'মেডিসিন'],
    'general medicine': ['med', 'gen med', 'gp', 'medicine', 'internal medicine', 'মেডিসিন'],
    'internal medicine': ['general medicine', 'med', 'gen med', 'medicine', 'মেডিসিন'],
    'medicine specialist': ['med', 'gen med', 'medicine', 'internal medicine', 'মেডিসিন'],
    'neuro': ['neurology', 'neurologist', 'neurosurgery', 'neurosurgeon', 'স্নায়ুরোগ'],
    'neurology': ['neuro', 'neurologist', 'neurosurgery', 'স্নায়ুরোগ'],
    'neurologist': ['neuro', 'neurology', 'neurosurgery', 'স্নায়ুরোগ'],
    'psych': ['psychiatry', 'psychiatrist', 'mental', 'psy', 'মানসিক'],
    'psy': ['psychiatry', 'psychiatrist', 'psych', 'mental', 'মানসিক'],
    'psychiatry': ['psych', 'psy', 'psychiatrist', 'mental', 'মানসিক'],
    'psychiatrist': ['psych', 'psy', 'psychiatry', 'mental', 'মানসিক'],
    'onco': ['oncology', 'oncologist', 'cancer', 'ক্যান্সার'],
    'cancer': ['oncology', 'oncologist', 'onco', 'ক্যান্সার'],
    'oncology': ['onco', 'oncologist', 'cancer', 'ক্যান্সার'],
    'oncologist': ['onco', 'oncology', 'cancer', 'ক্যান্সার'],
    'gastro': ['gastroenterology', 'gastroenterologist', 'liver', 'hepatology', 'লিভার'],
    'liver': ['gastroenterology', 'gastroenterologist', 'gastro', 'hepatology', 'লিভার'],
    'gastroenterology': ['gastro', 'liver', 'gastroenterologist', 'hepatology', 'লিভার'],
    'gastroenterologist': ['gastro', 'liver', 'gastroenterology', 'hepatology', 'লিভার'],
    'nephro': ['nephrology', 'nephrologist', 'kidney', 'কিডনি'],
    'kidney': ['nephrology', 'nephrologist', 'nephro', 'কিডনি'],
    'nephrology': ['nephro', 'kidney', 'nephrologist', 'কিডনি'],
    'nephrologist': ['nephro', 'kidney', 'nephrology', 'কিডনি'],
    'pulmo': ['pulmonology', 'pulmonologist', 'chest', 'respiratory', 'বক্ষব্যাধি'],
    'chest': ['pulmonology', 'pulmonologist', 'pulmo', 'respiratory', 'বক্ষব্যাধি'],
    'pulmonology': ['pulmo', 'chest', 'pulmonologist', 'respiratory', 'বক্ষব্যাধি'],
    'pulmonologist': ['pulmo', 'chest', 'pulmonology', 'respiratory', 'বক্ষব্যাধি'],
    'uro': ['urology', 'urologist'],
    'urology': ['uro', 'urologist'],
    'urologist': ['uro', 'urology'],
    'endo': ['endocrinology', 'endocrinologist', 'diabetes', 'diabetology', 'ডায়াবেটিস'],
    'diabetes': ['endocrinology', 'endocrinologist', 'endo', 'diabetology', 'ডায়াবেটিস'],
    'diabetology': ['endocrinology', 'endocrinologist', 'endo', 'diabetes', 'ডায়াবেটিস'],
    'endocrinology': ['endo', 'diabetes', 'endocrinologist', 'diabetology', 'ডায়াবেটিস'],
    'endocrinologist': ['endo', 'diabetes', 'endocrinology', 'diabetology', 'ডায়াবেটিস'],
    'rheum': ['rheumatology', 'rheumatologist', 'rheuma', 'বাতরোগ'],
    'rheuma': ['rheumatology', 'rheumatologist', 'rheum', 'বাতরোগ'],
    'rheumatology': ['rheum', 'rheuma', 'rheumatologist', 'বাতরোগ'],
    'rheumatologist': ['rheum', 'rheuma', 'rheumatology', 'বাতরোগ'],
    'physio': ['physiotherapy', 'physical medicine', 'physical medicine specialist'],
    'physiotherapy': ['physio', 'physical medicine', 'physical medicine specialist'],
    'physical medicine': ['physio', 'physiotherapy', 'physical medicine specialist'],
    'physical medicine specialist': ['physio', 'physiotherapy', 'physical medicine'],
    'hepatologist': ['hepatology', 'liver', 'jaundice', 'hepatitis'],
    'hepatology': ['hepatologist', 'liver', 'jaundice', 'hepatitis'],
    'hematologist': ['hematology', 'blood', 'anemia', 'thalassemia'],
    'hematology': ['hematologist', 'blood', 'anemia', 'thalassemia'],
    'allergist': ['allergy', 'allergic', 'immunology'],
    'colorectal surgeon': ['colorectal', 'piles', 'hemorrhoids', 'fistula'],
    'colorectal': ['colorectal surgeon', 'piles', 'hemorrhoids'],
    'general surgeon': ['surgery', 'surgeon', 'operation', 'surgical'],
    'surgeon': ['general surgeon', 'surgery', 'surgical'],
    'general physician': ['gp', 'med', 'medicine', 'fever', 'general medicine'],
  };

  // =========================================================================
  // SYMPTOM → SPECIALTY MAP
  // Maps normalized symptom keywords/phrases to their canonical specialty name.
  // Used during indexing so that a patient searching for "chest pain" can find
  // cardiologists, "hair loss" → dermatologist, etc.
  // =========================================================================
  static const Map<String, String> _symptomToSpecialty = {
    // Heart / Cardiology
    'chest pain': 'Cardiologist',
    'heart pain': 'Cardiologist',
    'heart problem': 'Cardiologist',
    'chest tightness': 'Cardiologist',
    'palpitation': 'Cardiologist',
    'heart attack': 'Cardiologist',
    'cardiac': 'Cardiologist',
    'high blood pressure': 'Cardiologist',
    'hypertension': 'Cardiologist',
    'blood pressure': 'Cardiologist',
    'hridrog': 'Cardiologist',
    'বুকে ব্যথা': 'Cardiologist',
    'হৃদরোগ': 'Cardiologist',
    'হার্ট': 'Cardiologist',

    // General / Fever
    'fever': 'General Physician',
    'viral fever': 'General Physician',
    'body ache': 'General Physician',
    'weakness': 'General Physician',
    'জ্বর': 'General Physician',
    'দুর্বলতা': 'General Physician',

    // Diabetes / Endocrinology
    'diabetes': 'Endocrinologist',
    'blood sugar': 'Endocrinologist',
    'diabetic': 'Endocrinologist',
    'insulin': 'Endocrinologist',
    'thyroid': 'Endocrinologist',
    'goiter': 'Endocrinologist',
    'ডায়াবেটিস': 'Endocrinologist',
    'থাইরয়েড': 'Endocrinologist',

    // Skin / Dermatology
    'skin rash': 'Dermatologist',
    'rash': 'Dermatologist',
    'itching': 'Dermatologist',
    'eczema': 'Dermatologist',
    'psoriasis': 'Dermatologist',
    'fungal': 'Dermatologist',
    'acne': 'Dermatologist',
    'pimple': 'Dermatologist',
    'hair loss': 'Dermatologist',
    'hair fall': 'Dermatologist',
    'dandruff': 'Dermatologist',
    'চুলকানি': 'Dermatologist',
    'চামড়ার সমস্যা': 'Dermatologist',
    'চুল পড়া': 'Dermatologist',

    // Eye / Ophthalmology
    'eye problem': 'Ophthalmologist',
    'eye pain': 'Ophthalmologist',
    'blurry vision': 'Ophthalmologist',
    'cataract': 'Ophthalmologist',
    'red eye': 'Ophthalmologist',
    'vision loss': 'Ophthalmologist',
    'glaucoma': 'Ophthalmologist',
    'চোখের সমস্যা': 'Ophthalmologist',
    'ছানি': 'Ophthalmologist',

    // Dental
    'toothache': 'Dentist',
    'tooth pain': 'Dentist',
    'bleeding gum': 'Dentist',
    'cavity': 'Dentist',
    'দাঁতের ব্যথা': 'Dentist',
    'দাঁতের সমস্যা': 'Dentist',

    // Stomach / Gastro
    'stomach pain': 'Gastroenterologist',
    'acidity': 'Gastroenterologist',
    'heartburn': 'Gastroenterologist',
    'diarrhea': 'Gastroenterologist',
    'vomiting': 'Gastroenterologist',
    'nausea': 'Gastroenterologist',
    'indigestion': 'Gastroenterologist',
    'gastric': 'Gastroenterologist',
    'constipation': 'Gastroenterologist',
    'পেটে ব্যথা': 'Gastroenterologist',
    'গ্যাসের সমস্যা': 'Gastroenterologist',

    // Neuro
    'migraine': 'Neurologist',
    'dizziness': 'Neurologist',
    'numbness': 'Neurologist',
    'seizure': 'Neurologist',
    'stroke': 'Neurologist',
    'vertigo': 'Neurologist',
    'মাইগ্রেন': 'Neurologist',
    'মাথা ঘোরা': 'Neurologist',

    // Ortho
    'back pain': 'Orthopedist',
    'joint pain': 'Orthopedist',
    'bone pain': 'Orthopedist',
    'arthritis': 'Orthopedist',
    'knee pain': 'Orthopedist',
    'fracture': 'Orthopedist',
    'পিঠের ব্যথা': 'Orthopedist',
    'কোমর ব্যথা': 'Orthopedist',
    'হাড়ের ব্যথা': 'Orthopedist',

    // Lung / Pulmonology
    'breathing problem': 'Pulmonologist',
    'shortness of breath': 'Pulmonologist',
    'asthma': 'Pulmonologist',
    'cough': 'Pulmonologist',
    'dry cough': 'Pulmonologist',
    'bronchitis': 'Pulmonologist',
    'শ্বাসকষ্ট': 'Pulmonologist',
    'কাশি': 'Pulmonologist',

    // Kidney / Nephrology
    'kidney problem': 'Nephrologist',
    'kidney stone': 'Nephrologist',
    'renal': 'Nephrologist',
    'কিডনির সমস্যা': 'Nephrologist',

    // Mental / Psychiatry
    'depression': 'Psychiatrist',
    'anxiety': 'Psychiatrist',
    'insomnia': 'Psychiatrist',
    'mental problem': 'Psychiatrist',
    'panic attack': 'Psychiatrist',
    'মানসিক সমস্যা': 'Psychiatrist',
    'ঘুম হয় না': 'Psychiatrist',

    // Child / Pediatrics
    'child health': 'Pediatrician',
    'infant': 'Pediatrician',
    'baby sickness': 'Pediatrician',
    'শিশু রোগ': 'Pediatrician',
    'বাচ্চার জ্বর': 'Pediatrician',

    // Pregnancy / Gynecology
    'pregnancy': 'Gynecologist',
    'pregnant': 'Gynecologist',
    'period pain': 'Gynecologist',
    'irregular period': 'Gynecologist',
    'pcos': 'Gynecologist',
    'গর্ভবতী': 'Gynecologist',
    'মাসিক সমস্যা': 'Gynecologist',

    // ENT
    'ear problem': 'ENT Specialist',
    'ear pain': 'ENT Specialist',
    'hearing loss': 'ENT Specialist',
    'sinus': 'ENT Specialist',
    'throat pain': 'ENT Specialist',
    'sore throat': 'ENT Specialist',
    'tonsil': 'ENT Specialist',
    'কানের সমস্যা': 'ENT Specialist',
    'গলা ব্যথা': 'ENT Specialist',
    'নাক বন্ধ': 'ENT Specialist',

    // Cancer / Oncology
    'cancer': 'Oncologist',
    'tumor': 'Oncologist',
    'chemotherapy': 'Oncologist',
    'ক্যান্সার': 'Oncologist',

    // Liver / Hepatology
    'liver problem': 'Hepatologist',
    'jaundice': 'Hepatologist',
    'hepatitis': 'Hepatologist',
    'জন্ডিস': 'Hepatologist',

    // Surgery
    'hernia': 'General Surgeon',
    'appendicitis': 'General Surgeon',
    'gallstone': 'General Surgeon',

    // Urology
    'burning urination': 'Urologist',
    'blood in urine': 'Urologist',
    'prostate': 'Urologist',
    'প্রস্রাবের সমস্যা': 'Urologist',

    // Allergy
    'allergy': 'Allergist',
    'sneezing': 'Allergist',
    'dust allergy': 'Allergist',
    'অ্যালার্জি': 'Allergist',

    // Blood / Hematology
    'anemia': 'Hematologist',
    'thalassemia': 'Hematologist',
    'রক্তস্বল্পতা': 'Hematologist',

    // Physical Medicine
    'neck pain': 'Physical Medicine Specialist',
    'shoulder pain': 'Physical Medicine Specialist',
    'muscle pain': 'Physical Medicine Specialist',
    'paralysis': 'Physical Medicine Specialist',
    'ঘাড় ব্যথা': 'Physical Medicine Specialist',

    // Colorectal
    'piles': 'Colorectal Surgeon',
    'hemorrhoids': 'Colorectal Surgeon',
    'fistula': 'Colorectal Surgeon',
    'পাইলস': 'Colorectal Surgeon',
  };

  // =========================================================================
  // SPECIALTY → SYMPTOMS MAP (inverse, built once at startup)
  // Lets us add symptom keywords to a doctor's index purely from their specialty.
  // =========================================================================
  static late final Map<String, List<String>> _specialtyToSymptoms = _buildSpecialtyToSymptoms();

  static Map<String, List<String>> _buildSpecialtyToSymptoms() {
    final result = <String, List<String>>{};
    _symptomToSpecialty.forEach((symptom, specialty) {
      final key = specialty.toLowerCase();
      result.putIfAbsent(key, () => []).add(symptom);
    });
    return result;
  }

  // =========================================================================
  // PUBLIC API
  // =========================================================================

  static String normalize(String value) =>
      value.toLowerCase().replaceAll(_separators, ' ').trim();

  static List<String> tokens(String value) => normalize(value)
      .split(' ')
      .where((token) => token.isNotEmpty)
      .toSet()
      .toList();

  /// Builds the three index fields to store on each Firestore doctor document.
  static Map<String, dynamic> fieldsFor(Map<String, dynamic> doctor) {
    final sources = _sourceValues(doctor);
    final text = sources.join(' ');
    final searchText = normalize(text);
    final searchTokens = tokens(searchText);
    return {
      'searchText': searchText,
      'searchTokens': searchTokens,
      'searchPrefixes': _prefixes(searchTokens),
    };
  }

  /// Builds query tokens for a Firestore `arrayContainsAny` search.
  ///
  /// Expansion order (priority):
  ///   1. Raw query tokens (direct match)
  ///   2. Symptom → specialty expansion (e.g. "chest pain" → "cardiologist")
  ///   3. Specialty abbreviation expansion (e.g. "ent" → "otolaryngology")
  ///   4. Name alias expansion (e.g. "md" → "mohammad")
  ///   5. Title expansion (dr/doc/ডা)
  ///
  /// Firestore's `arrayContainsAny` limit is 30 values (raised from 10 in 2024).
  /// We cap at 30 and prefer higher-signal tokens first.
  static List<String> queryPrefixes(String query) {
    final queryToks = tokens(query).where((t) => t.length >= 2).toList();
    if (queryToks.isEmpty) return const [];

    final result = <String>{};

    // 1. Raw tokens first (highest priority)
    for (final tok in queryToks) {
      result.add(tok);
    }

    // 2. Symptom phrase detection: check if the full query (or 2-3 word slices)
    //    matches a symptom key and inject the mapped specialty tokens.
    final normalizedQuery = normalize(query);
    _symptomToSpecialty.forEach((symptomPhrase, specialty) {
      if (normalizedQuery.contains(normalize(symptomPhrase))) {
        // Add specialty tokens so Firestore finds the right doctor type
        for (final st in tokens(specialty)) {
          if (st.length >= 2) result.add(st);
        }
        // Also add canonical abbreviations for that specialty
        final specKey = normalize(specialty);
        final abbrevs = specialtyAbbreviations[specKey];
        if (abbrevs != null) {
          for (final a in abbrevs) {
            for (final at in tokens(a).where((t) => t.length >= 2)) {
              result.add(at);
              if (result.length >= 30) return;
            }
          }
        }
      }
    });

    if (result.length >= 30) return result.take(30).toList();

    // 3. Specialty abbreviation expansion for each raw token
    for (final tok in queryToks) {
      final abbrevs = specialtyAbbreviations[tok];
      if (abbrevs != null) {
        for (final abbrev in abbrevs) {
          for (final at in tokens(abbrev).where((t) => t.length >= 2)) {
            result.add(at);
            if (result.length >= 30) return result.take(30).toList();
          }
        }
      }
    }

    // 4. Name alias expansion
    for (final tok in queryToks) {
      final aliases = _nameAliases[tok];
      if (aliases != null) {
        for (final alias in aliases) {
          if (alias.length >= 2) result.add(alias);
          if (result.length >= 30) return result.take(30).toList();
        }
      }
    }

    // 5. Title expansion
    for (final tok in queryToks) {
      if (titleTokens.contains(tok)) {
        for (final title in ['dr', 'doctor', 'doc', 'ডা']) {
          if (title.length >= 2) result.add(title);
          if (result.length >= 30) return result.take(30).toList();
        }
      }
    }

    return result.take(30).toList();
  }

  /// Scores a doctor record against a query.
  /// Returns -1 if any query token cannot be satisfied (no match).
  /// Higher positive values = better match.
  static int score(Map<String, dynamic> doctor, String query) {
    final normalizedQuery = normalize(query);
    final queryTokens = tokens(normalizedQuery);
    if (queryTokens.isEmpty) return 0;

    final rawName = doctor['name']?.toString() ?? '';
    final normName = normalize(rawName);
    final nameTokens = tokens(normName);
    final coreNameWords =
        nameTokens.where((t) => !titleTokens.contains(t)).toList();

    final text = doctor['searchText']?.toString().isNotEmpty == true
        ? normalize(doctor['searchText'].toString())
        : normalize(_sourceValues(doctor).join(' '));

    final specialities = _stringList(doctor['specialities'])
        .map(normalize)
        .where((s) => s.isNotEmpty)
        .toList();

    // Detect symptom phrases in the query and resolve to specialty names
    final symptomMatchedSpecialties = <String>{};
    _symptomToSpecialty.forEach((symptomPhrase, specialty) {
      if (normalizedQuery.contains(normalize(symptomPhrase))) {
        symptomMatchedSpecialties.add(normalize(specialty));
      }
    });

    // Check if this doctor's specialties match any symptom-derived specialty
    bool isSymptomMatch = false;
    if (symptomMatchedSpecialties.isNotEmpty) {
      for (final docSpec in specialities) {
        // Direct match
        if (symptomMatchedSpecialties.contains(docSpec)) {
          isSymptomMatch = true;
          break;
        }
        // Abbreviation / synonym match
        for (final specTok in tokens(docSpec)) {
          final abbrevs = specialtyAbbreviations[specTok];
          if (abbrevs != null) {
            for (final matched in symptomMatchedSpecialties) {
              if (abbrevs.any((a) => normalize(a).contains(matched) ||
                  matched.contains(normalize(a)))) {
                isSymptomMatch = true;
                break;
              }
            }
          }
          if (isSymptomMatch) break;
        }
        if (isSymptomMatch) break;
      }
    }

    // Verify every query token is satisfied by at least one mechanism
    for (final token in queryTokens) {
      final isTitle = titleTokens.contains(token);
      final isExactNameWord = coreNameWords.contains(token);
      final isPrefixNameWord = coreNameWords.any((w) => w.startsWith(token));
      final isNameAlias = _nameAliases[token]?.any(nameTokens.contains) ?? false;
      final isTextContains = text.contains(token);

      // Abbreviation match: token maps to something in doctor's text/specialty,
      // OR a doctor's specialty token maps to this query token
      final isAbbreviationMatch =
          (specialtyAbbreviations[token]?.any((alt) => text.contains(normalize(alt))) ?? false) ||
          specialities.any((spec) =>
              tokens(spec).any((specTok) =>
                  specialtyAbbreviations[specTok]?.contains(token) ?? false));

      // Symptom match: if we've resolved a symptom phrase and this doctor fits
      // (we allow the entire symptom phrase to satisfy all its constituent tokens)
      final isPartOfSymptomPhrase = isSymptomMatch &&
          _symptomToSpecialty.keys.any((phrase) =>
              normalize(phrase).contains(token) &&
              normalizedQuery.contains(normalize(phrase)));

      if (!isTitle &&
          !isExactNameWord &&
          !isPrefixNameWord &&
          !isNameAlias &&
          !isTextContains &&
          !isAbbreviationMatch &&
          !isPartOfSymptomPhrase) {
        return -1;
      }
    }

    // ── Scoring ──────────────────────────────────────────────────────────────
    var s = queryTokens.length * 20;

    if (normName == normalizedQuery) {
      s += 1000;
    } else if (normName.startsWith(normalizedQuery)) {
      s += 800;
    } else if (coreNameWords.contains(normalizedQuery)) {
      s += 750;
    } else if (coreNameWords.any((w) => w.startsWith(normalizedQuery))) {
      s += 600;
    } else if (text.contains(normalizedQuery)) {
      s += 500;
    }

    // Symptom-to-specialty match bonus
    if (isSymptomMatch) s += 400;

    for (final token in queryTokens) {
      final isDirectSpecialtyMatch = specialities.any((spec) =>
          tokens(spec).contains(token) ||
          spec.contains(token) ||
          (specialtyAbbreviations[token]?.any((alt) => spec.contains(normalize(alt))) ?? false));

      if (coreNameWords.contains(token)) {
        s += 250;
      } else if (coreNameWords.any((w) => w.startsWith(token))) {
        s += 150;
      } else if (_nameAliases[token]?.any(nameTokens.contains) ?? false) {
        s += 180;
      } else if (isDirectSpecialtyMatch) {
        s += 350;
      } else if (titleTokens.contains(token)) {
        s += 60;
      } else if (specialtyAbbreviations.containsKey(token)) {
        s += 120;
      } else if (text.contains(token)) {
        s += 40;
      } else if (isSymptomMatch) {
        // Part of a matched symptom phrase – give partial credit
        s += 30;
      }
    }

    return s;
  }

  /// Ranks a list of raw doctor maps by query relevance.
  /// Doctors with score < 0 are excluded entirely.
  static List<Map<String, dynamic>> rank(
    Iterable<Map<String, dynamic>> doctors,
    String query,
  ) {
    final scored = doctors
        .map((doctor) => (doctor: doctor, score: score(doctor, query)))
        .where((item) => item.score >= 0)
        .toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final aRatings = (a.doctor['ratingCount'] as num?)?.toInt() ?? 0;
        final bRatings = (b.doctor['ratingCount'] as num?)?.toInt() ?? 0;
        return bRatings.compareTo(aRatings);
      });
    return scored.map((item) => item.doctor).toList();
  }

  // =========================================================================
  // PRIVATE HELPERS
  // =========================================================================

  static List<String> _prefixes(Iterable<String> values) {
    final prefixes = <String>{};
    for (final value in values) {
      for (var length = 2; length <= value.length && length <= 16; length++) {
        prefixes.add(value.substring(0, length));
      }
    }
    return prefixes.toList();
  }

  /// Collects all text values that should be indexed for a doctor document.
  /// Order matters — higher priority sources come first.
  static List<String> _sourceValues(Map<String, dynamic> doctor) {
    final rawName = doctor['name']?.toString() ?? '';
    final nameTokens = tokens(rawName);
    final specialities = _stringList(doctor['specialities']);
    final concentrations = _stringList(doctor['concentrations']);

    final values = <String>[
      rawName,
      doctor['designation']?.toString() ?? '',
      ...specialities,
      ...concentrations,
      ..._stringList(doctor['education']),
    ];

    // Always include standard doctor title tokens
    values.addAll(['dr', 'doctor', 'doc', 'ডা', 'ডাক্তার']);

    // Expand name aliases (Md ↔ Mohammad, Prof ↔ Professor…)
    for (final tok in nameTokens) {
      final aliases = _nameAliases[tok];
      if (aliases != null) values.addAll(aliases);
    }

    // For each specialty, add:
    //   a) All abbreviation/synonym expansions
    //   b) All symptom keywords that map to this specialty (via any alias)
    final allSpecTerms = [...specialities, ...concentrations];
    for (final spec in allSpecTerms) {
      final normSpec = normalize(spec);
      final specTokens = tokens(normSpec);

      // Collect all canonical names this specialty resolves to.
      // e.g. 'ENT' → tokens ['ent'] → abbrevs → ['otolaryngology', 'ent specialist', ...]
      // e.g. 'Medicine Specialist' → tokens ['medicine', 'specialist']
      //      'medicine' → abbrevs → ['general medicine', 'general physician', ...]
      final canonicalNames = <String>{normSpec, ...specTokens};

      // a) Full-phrase abbreviation expansions
      final fullAbbrevs = specialtyAbbreviations[normSpec];
      if (fullAbbrevs != null) {
        values.addAll(fullAbbrevs);
        for (final a in fullAbbrevs) {
          canonicalNames.add(normalize(a));
        }
      }

      // b) Token-level abbreviation expansions (with one recursion)
      for (final st in specTokens) {
        final abbrevs = specialtyAbbreviations[st];
        if (abbrevs != null) {
          values.addAll(abbrevs);
          for (final exp in abbrevs) {
            final normExp = normalize(exp);
            canonicalNames.add(normExp);
            final expAbbrevs = specialtyAbbreviations[normExp];
            if (expAbbrevs != null) {
              values.addAll(expAbbrevs);
              expAbbrevs.forEach((e) => canonicalNames.add(normalize(e)));
            }
          }
        }
      }

      // c) Symptom injection via all resolved canonical names.
      //    Strategy: direct lookup + substring match + one extra expansion step.
      //    The extra expansion step bridges chains like:
      //      'medicine specialist' → 'gp' → 'general physician' → fever/weakness/...
      //      'ENT' → 'ent' → 'ent specialist' → ear pain/sinus/...
      final allCanonicals = List<String>.from(canonicalNames);
      // Extra expansion: expand each canonical one more level
      final expanded = <String>{};
      for (final canonical in allCanonicals) {
        final extra = specialtyAbbreviations[canonical];
        if (extra != null) {
          expanded.addAll(extra.map(normalize));
        }
      }
      allCanonicals.addAll(expanded);

      for (final canonical in allCanonicals) {
        // Direct key hit (exact match)
        final directSymps = _specialtyToSymptoms[canonical];
        if (directSymps != null) values.addAll(directSymps);

        // Substring match: finds 'ent' inside 'ent specialist' key,
        // or 'general physician' when canonical is 'general physician'.
        // Length guard >= 3 avoids 'or'/'in'/'at' false positives.
        if (canonical.length >= 3) {
          _specialtyToSymptoms.forEach((key, symptoms) {
            if (key != canonical &&
                (key.contains(canonical) || canonical.contains(key))) {
              values.addAll(symptoms);
            }
          });
        }
      }
    }

    // Chambers: hospital name, area, location
    for (final chamber in [
      ..._mapList(doctor['chambers']),
      ..._mapList(doctor['chamber'] == null ? null : [doctor['chamber']]),
    ]) {
      values.addAll([
        chamber['hospitalName']?.toString() ?? '',
        chamber['area']?.toString() ?? '',
        chamber['location']?.toString() ?? '',
      ]);
    }

    return values.where((v) => v.trim().isNotEmpty).toList();
  }

  static List<String> _stringList(dynamic value) =>
      (value as List? ?? const []).map((item) => item.toString()).toList();

  static List<Map<String, dynamic>> _mapList(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
}
