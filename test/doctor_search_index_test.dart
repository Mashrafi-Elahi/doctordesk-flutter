import 'package:flutter_test/flutter_test.dart';
import 'package:doctordesk/services/doctor_search_index.dart';

void main() {
  // Helper: build a fake doctor map with pre-computed search index fields
  Map<String, dynamic> doctor({
    required String name,
    List<String> specialities = const [],
    List<String> education = const [],
    List<String> concentrations = const [],
    List<Map<String, String>> chambers = const [],
    int ratingCount = 0,
    String? designation,
  }) {
    final data = <String, dynamic>{
      'name': name,
      'specialities': specialities,
      'education': education,
      'concentrations': concentrations,
      'chambers': chambers,
      'ratingCount': ratingCount,
      if (designation != null) 'designation': designation,
    };
    return {...data, ...DoctorSearchIndex.fieldsFor(data)};
  }

  // ────────────────────────────────────────────────────────────────────────────
  // EXISTING TESTS (unchanged behaviour)
  // ────────────────────────────────────────────────────────────────────────────

  test('ranks an exact multiword name before a partial match', () {
    final exact = doctor(name: 'Dr. Md. Kamrul Islam', ratingCount: 2);
    final partial = doctor(name: 'Dr. Kamrul Hasan Islam', ratingCount: 99);

    final ranked = DoctorSearchIndex.rank([partial, exact], 'Kamrul Islam');

    expect(ranked.first['name'], exact['name']);
  });

  test('matches a name prefix after doctor titles', () {
    final record = doctor(name: 'Dr. Mowsumi Akter Saathi');

    expect(DoctorSearchIndex.queryPrefixes('mowsum'), contains('mowsum'));
    expect(DoctorSearchIndex.score(record, 'mowsum'), greaterThan(0));
  });

  test('matches partial multiword specialty and chamber terms', () {
    final record = doctor(
      name: 'Dr. Farzana Rahman',
      specialities: ['Medicine Specialist'],
      education: ['MBBS, FCPS'],
      chambers: [
        {'hospitalName': 'Square Hospital', 'area': 'Panthapath'},
      ],
    );

    expect(DoctorSearchIndex.score(record, 'medicine spec'), greaterThan(0));
    expect(DoctorSearchIndex.score(record, 'square pantha'), greaterThan(0));
    expect(DoctorSearchIndex.score(record, 'fcps'), greaterThan(0));
  });

  test('preserves Bangla text while matching multiword and partial queries', () {
    final record = doctor(
      name: 'ডা. মাহমুদ হাসান',
      specialities: ['মেডিসিন বিশেষজ্ঞ'],
    );

    expect(DoctorSearchIndex.score(record, 'মাহমুদ হাস'), greaterThan(0));
    expect(DoctorSearchIndex.score(record, 'মেডিসিন বিশেষ'), greaterThan(0));
  });

  test('returns no match when a query token is absent and no symptom bridge', () {
    final record = doctor(name: 'Dr. Farzana Rahman');
    // This doctor has no specialty so "cardiology specialist" should not match
    expect(DoctorSearchIndex.score(record, 'cardiology specialist'), -1);
  });

  test('matches any doctor-name word and honorific titles', () {
    final saima = doctor(
      name: 'Dr. Nuzhat Saima',
      specialities: ['General Medicine'],
      chambers: [
        {'hospitalName': 'Bup Medical', 'area': 'Mirpur', 'location': 'Dhaka'},
      ],
    );

    expect(DoctorSearchIndex.score(saima, 'Saima'), greaterThan(0));
    expect(DoctorSearchIndex.score(saima, 'Nuzhat'), greaterThan(0));
    expect(DoctorSearchIndex.score(saima, 'saim'), greaterThan(0));
    expect(DoctorSearchIndex.score(saima, 'Doctor Saima'), greaterThan(0));
    expect(DoctorSearchIndex.score(saima, 'Doc Saima'), greaterThan(0));
    expect(DoctorSearchIndex.score(saima, 'Dr. Saima'), greaterThan(0));
    expect(DoctorSearchIndex.score(saima, 'Doctor Nuzhat'), greaterThan(0));
    expect(DoctorSearchIndex.score(saima, 'Saima Bup'), greaterThan(0));
    expect(DoctorSearchIndex.score(saima, 'Saima Medicine'), greaterThan(0));

    final plainName = doctor(name: 'Nuzhat Saima');
    expect(DoctorSearchIndex.score(plainName, 'Dr Saima'), greaterThan(0));
    expect(DoctorSearchIndex.score(plainName, 'Doctor Saima'), greaterThan(0));
  });

  test('understands Bangladeshi name aliases like Md and Mohammad', () {
    final kamrul = doctor(name: 'Dr. Md. Kamrul Islam');
    expect(DoctorSearchIndex.score(kamrul, 'Mohammad Kamrul'), greaterThan(0));
    expect(DoctorSearchIndex.score(kamrul, 'Md Kamrul'), greaterThan(0));
    expect(DoctorSearchIndex.score(kamrul, 'Kamrul'), greaterThan(0));
    expect(DoctorSearchIndex.score(kamrul, 'Islam'), greaterThan(0));
  });

  test('understands medical abbreviations', () {
    final entDoc = doctor(
      name: 'Dr. Alim Chowdhury',
      specialities: ['Otolaryngology'],
    );
    expect(DoctorSearchIndex.score(entDoc, 'ent'), greaterThan(0));
    expect(DoctorSearchIndex.score(entDoc, 'ent doctor'), greaterThan(0));

    final gynDoc = doctor(
      name: 'Dr. Selina Banu',
      specialities: ['Gynecology and Obstetrics'],
    );
    expect(DoctorSearchIndex.score(gynDoc, 'gynae'), greaterThan(0));
    expect(DoctorSearchIndex.score(gynDoc, 'obgyn'), greaterThan(0));
    expect(DoctorSearchIndex.score(gynDoc, 'obs'), greaterThan(0));

    final dermDoc = doctor(
      name: 'Dr. Kamal Hossain',
      specialities: ['Dermatology'],
    );
    expect(DoctorSearchIndex.score(dermDoc, 'skin'), greaterThan(0));
    expect(DoctorSearchIndex.score(dermDoc, 'derm'), greaterThan(0));

    final eyeDoc = doctor(
      name: 'Dr. Tanvir Ahmed',
      specialities: ['Ophthalmology'],
    );
    expect(DoctorSearchIndex.score(eyeDoc, 'eye'), greaterThan(0));
    expect(DoctorSearchIndex.score(eyeDoc, 'ophth'), greaterThan(0));

    final medDoc = doctor(
      name: 'Dr. Nuzhat Saima',
      specialities: ['General Medicine'],
    );
    expect(DoctorSearchIndex.score(medDoc, 'med'), greaterThan(0));
    expect(DoctorSearchIndex.score(medDoc, 'gen med'), greaterThan(0));
    expect(DoctorSearchIndex.score(medDoc, 'gp'), greaterThan(0));

    final pedsDoc = doctor(
      name: 'Dr. Shamim Ara',
      specialities: ['Pediatrics'],
    );
    expect(DoctorSearchIndex.score(pedsDoc, 'peds'), greaterThan(0));
    expect(DoctorSearchIndex.score(pedsDoc, 'paed'), greaterThan(0));

    final cardioDoc = doctor(
      name: 'Dr. Jahangir Kabir',
      specialities: ['Cardiology'],
    );
    expect(DoctorSearchIndex.score(cardioDoc, 'cardio'), greaterThan(0));
    expect(DoctorSearchIndex.score(cardioDoc, 'heart'), greaterThan(0));
  });

  test('expands prefixes for Firestore array query', () {
    final prefixes = DoctorSearchIndex.queryPrefixes('Doctor Saima ENT');
    expect(prefixes, contains('doctor'));
    expect(prefixes, contains('saima'));
    expect(prefixes, contains('ent'));
    expect(DoctorSearchIndex.queryPrefixes('gynae'), contains('gynae'));
  });

  // ────────────────────────────────────────────────────────────────────────────
  // NEW: SYMPTOM → SPECIALTY SEARCH
  // ────────────────────────────────────────────────────────────────────────────

  group('Symptom → Specialty indexing', () {
    test('cardiologist is found via "chest pain"', () {
      final cardio = doctor(
        name: 'Dr. Jahangir Kabir',
        specialities: ['Cardiology'],
      );
      expect(DoctorSearchIndex.score(cardio, 'chest pain'), greaterThan(0));
      expect(DoctorSearchIndex.score(cardio, 'heart attack'), greaterThan(0));
      expect(DoctorSearchIndex.score(cardio, 'blood pressure'), greaterThan(0));
      expect(DoctorSearchIndex.score(cardio, 'palpitation'), greaterThan(0));
    });

    test('dermatologist is found via "hair loss" and "rash"', () {
      final derm = doctor(
        name: 'Dr. Mowsumi Akter Saathi',
        specialities: ['Dermatology'],
      );
      expect(DoctorSearchIndex.score(derm, 'hair loss'), greaterThan(0));
      expect(DoctorSearchIndex.score(derm, 'hair fall'), greaterThan(0));
      expect(DoctorSearchIndex.score(derm, 'skin rash'), greaterThan(0));
      expect(DoctorSearchIndex.score(derm, 'acne'), greaterThan(0));
      expect(DoctorSearchIndex.score(derm, 'itching'), greaterThan(0));
    });

    test('pulmonologist is found via "cough" and "asthma"', () {
      final pulmo = doctor(
        name: 'Dr. Rafiq Uddin',
        specialities: ['Pulmonology'],
      );
      expect(DoctorSearchIndex.score(pulmo, 'cough'), greaterThan(0));
      expect(DoctorSearchIndex.score(pulmo, 'dry cough'), greaterThan(0));
      expect(DoctorSearchIndex.score(pulmo, 'asthma'), greaterThan(0));
      expect(DoctorSearchIndex.score(pulmo, 'breathing problem'), greaterThan(0));
    });

    test('neurologist is found via "migraine" and "vertigo"', () {
      final neuro = doctor(
        name: 'Dr. Sultana Nahar',
        specialities: ['Neurology'],
      );
      expect(DoctorSearchIndex.score(neuro, 'migraine'), greaterThan(0));
      expect(DoctorSearchIndex.score(neuro, 'dizziness'), greaterThan(0));
      expect(DoctorSearchIndex.score(neuro, 'vertigo'), greaterThan(0));
      expect(DoctorSearchIndex.score(neuro, 'seizure'), greaterThan(0));
    });

    test('orthopedist is found via "knee pain" and "joint pain"', () {
      final ortho = doctor(
        name: 'Dr. Md. Meshke Alam Johnny',
        specialities: ['Orthopedic Surgery'],
      );
      expect(DoctorSearchIndex.score(ortho, 'knee pain'), greaterThan(0));
      expect(DoctorSearchIndex.score(ortho, 'joint pain'), greaterThan(0));
      expect(DoctorSearchIndex.score(ortho, 'back pain'), greaterThan(0));
      expect(DoctorSearchIndex.score(ortho, 'fracture'), greaterThan(0));
    });

    test('gastroenterologist is found via "stomach pain" and "acidity"', () {
      final gastro = doctor(
        name: 'Dr. Tania Sultana',
        specialities: ['Gastroenterology'],
      );
      expect(DoctorSearchIndex.score(gastro, 'stomach pain'), greaterThan(0));
      expect(DoctorSearchIndex.score(gastro, 'acidity'), greaterThan(0));
      expect(DoctorSearchIndex.score(gastro, 'vomiting'), greaterThan(0));
      expect(DoctorSearchIndex.score(gastro, 'gastric'), greaterThan(0));
    });

    test('gynecologist found via "pregnancy" and "period pain"', () {
      final gyn = doctor(
        name: 'Dr. Ferdousi Begum',
        specialities: ['Gynecology'],
      );
      expect(DoctorSearchIndex.score(gyn, 'pregnancy'), greaterThan(0));
      expect(DoctorSearchIndex.score(gyn, 'period pain'), greaterThan(0));
      expect(DoctorSearchIndex.score(gyn, 'pcos'), greaterThan(0));
    });

    test('ENT specialist found via "ear pain", "sore throat", "sinus"', () {
      final ent = doctor(
        name: 'Dr. Alim Chowdhury',
        specialities: ['ENT'],
      );
      expect(DoctorSearchIndex.score(ent, 'ear pain'), greaterThan(0));
      expect(DoctorSearchIndex.score(ent, 'sore throat'), greaterThan(0));
      expect(DoctorSearchIndex.score(ent, 'sinus'), greaterThan(0));
      expect(DoctorSearchIndex.score(ent, 'tonsil'), greaterThan(0));
    });

    test('endocrinologist found via "diabetes" and "thyroid"', () {
      final endo = doctor(
        name: 'Dr. Reza Hossain',
        specialities: ['Endocrinology'],
      );
      expect(DoctorSearchIndex.score(endo, 'diabetes'), greaterThan(0));
      expect(DoctorSearchIndex.score(endo, 'thyroid'), greaterThan(0));
      expect(DoctorSearchIndex.score(endo, 'blood sugar'), greaterThan(0));
    });

    test('psychiatrist found via "depression" and "anxiety"', () {
      final psych = doctor(
        name: 'Dr. Kamrun Nahar',
        specialities: ['Psychiatry'],
      );
      expect(DoctorSearchIndex.score(psych, 'depression'), greaterThan(0));
      expect(DoctorSearchIndex.score(psych, 'anxiety'), greaterThan(0));
      expect(DoctorSearchIndex.score(psych, 'insomnia'), greaterThan(0));
    });

    test('Bangla symptom "বুকে ব্যথা" finds cardiologist', () {
      final cardio = doctor(
        name: 'Dr. Kamrul Islam',
        specialities: ['Cardiology'],
      );
      expect(DoctorSearchIndex.score(cardio, 'বুকে ব্যথা'), greaterThan(0));
    });

    test('Bangla symptom "কাশি" finds pulmonologist', () {
      final pulmo = doctor(
        name: 'Dr. Ali Hossain',
        specialities: ['Pulmonology'],
      );
      expect(DoctorSearchIndex.score(pulmo, 'কাশি'), greaterThan(0));
    });

    test('symptom query tokens injected into Firestore queryPrefixes', () {
      final prefixes = DoctorSearchIndex.queryPrefixes('chest pain');
      // Should contain the raw tokens + specialty tokens (cardiologist/cardiology)
      expect(prefixes, contains('chest'));
      expect(prefixes, contains('pain'));
      // Must also include specialty-derived tokens so Firestore can find cardiologists
      final hasSpecialtyToken = prefixes.any((p) =>
          p.contains('cardio') || p.contains('cardiologist') || p.contains('heart'));
      expect(hasSpecialtyToken, isTrue,
          reason: 'queryPrefixes should expand symptom → specialty tokens');
    });

    test('symptom query "hair loss" expands to dermatology tokens', () {
      final prefixes = DoctorSearchIndex.queryPrefixes('hair loss');
      final hasDermToken = prefixes.any((p) =>
          p.contains('derm') || p.contains('skin') || p.contains('dermatolog'));
      expect(hasDermToken, isTrue);
    });

    test('symptom query "migraine" expands to neurology tokens', () {
      final prefixes = DoctorSearchIndex.queryPrefixes('migraine');
      final hasNeuroToken = prefixes.any((p) =>
          p.contains('neuro') || p.contains('neurol'));
      expect(hasNeuroToken, isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // NEW: MULTIPLE SPECIALTY DOCTORS
  // ────────────────────────────────────────────────────────────────────────────

  group('Multiple specialties indexed together', () {
    test('medicine specialist cardiologist matches both symptom sets', () {
      final dual = doctor(
        name: 'Dr. Assoc. Prof. Ganesh Chandra',
        specialities: ['Medicine Specialist', 'Cardiology'],
      );
      // Medicine queries
      expect(DoctorSearchIndex.score(dual, 'fever'), greaterThan(0));
      expect(DoctorSearchIndex.score(dual, 'medicine'), greaterThan(0));
      // Cardiology queries
      expect(DoctorSearchIndex.score(dual, 'chest pain'), greaterThan(0));
      expect(DoctorSearchIndex.score(dual, 'heart attack'), greaterThan(0));
      // Abbreviations
      expect(DoctorSearchIndex.score(dual, 'cardio'), greaterThan(0));
      expect(DoctorSearchIndex.score(dual, 'gp'), greaterThan(0));
    });

    test('doctor with 3 specialties matches all three via abbreviation', () {
      final triple = doctor(
        name: 'Dr. Rahela Khatun',
        specialities: ['Gynecology', 'Obstetrics', 'Infertility'],
      );
      expect(DoctorSearchIndex.score(triple, 'gynae'), greaterThan(0));
      expect(DoctorSearchIndex.score(triple, 'obgyn'), greaterThan(0));
      expect(DoctorSearchIndex.score(triple, 'pregnancy'), greaterThan(0));
      expect(DoctorSearchIndex.score(triple, 'period pain'), greaterThan(0));
    });

    test('multi-specialty doctor ranked higher than single match', () {
      final cardiac = doctor(
        name: 'Dr. Ali Hossain',
        specialities: ['Cardiology'],
        ratingCount: 5,
      );
      final medicineCardiac = doctor(
        name: 'Dr. Bashir Ahmed',
        specialities: ['Medicine Specialist', 'Cardiology'],
        ratingCount: 2,
      );
      // Both should match "chest pain"
      final cardiacScore = DoctorSearchIndex.score(cardiac, 'chest pain');
      final dualScore = DoctorSearchIndex.score(medicineCardiac, 'chest pain');
      expect(cardiacScore, greaterThan(0));
      expect(dualScore, greaterThan(0));
    });

    test('queryPrefixes returns up to 30 tokens for complex multi-specialty query', () {
      final prefixes = DoctorSearchIndex.queryPrefixes('medicine cardiologist gynae');
      expect(prefixes.length, lessThanOrEqualTo(30));
      expect(prefixes, contains('medicine'));
      expect(prefixes, contains('gynae'));
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // NEW: SEARCH INDEX FIELD VERIFICATION
  // ────────────────────────────────────────────────────────────────────────────

  group('fieldsFor() index field content', () {
    test('searchText includes symptom keywords for a cardiologist', () {
      final cardio = doctor(
        name: 'Dr. Kamrul Islam',
        specialities: ['Cardiology'],
      );
      final searchText = cardio['searchText'] as String;
      expect(searchText, contains('chest'));
      expect(searchText, contains('heart'));
    });

    test('searchText includes abbreviation expansions for ENT doctor', () {
      final ent = doctor(
        name: 'Dr. Alim Chowdhury',
        specialities: ['Otolaryngology'],
      );
      final searchText = ent['searchText'] as String;
      // Abbreviation "ent" should appear from the expansion
      expect(searchText, contains('ent'));
    });

    test('searchPrefixes list is non-empty for a simple doctor', () {
      final rec = doctor(name: 'Dr. Rahman', specialities: ['Dermatology']);
      final prefixes = rec['searchPrefixes'] as List;
      expect(prefixes, isNotEmpty);
      // Should at minimum have "ra" (prefix of "rahman")
      expect(prefixes, contains('ra'));
    });

    test('searchTokens includes specialty tokens for multi-specialty doctor', () {
      final dual = doctor(
        name: 'Dr. Ferdousi',
        specialities: ['Gynecology', 'Obstetrics'],
      );
      final tokens = (dual['searchTokens'] as List).cast<String>();
      expect(tokens.any((t) => t.contains('gyn')), isTrue);
      expect(tokens.any((t) => t.contains('obs')), isTrue);
    });
  });
}
