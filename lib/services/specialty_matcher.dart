/// Result of a specialty match query.
class MatchResult {
  final String? topSpecialty;
  final List<String> alternatives;
  final bool isVague;

  const MatchResult({
    this.topSpecialty,
    this.alternatives = const [],
    this.isVague = false,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is String) return topSpecialty == other;
    if (other is MatchResult) return topSpecialty == other.topSpecialty;
    return false;
  }

  @override
  int get hashCode => topSpecialty.hashCode;

  @override
  String toString() => topSpecialty ?? '';
}

/// Rule-based specialty matcher for common complaints in English,
/// Bangla script (বাংলা), and Banglish (romanized Bangla).
///
/// NOTE: Banglish spelling is not standardized — this matcher will miss
/// unusual phrasings. That is an expected, explainable limitation of a
/// rule-based system.
class SpecialtyMatcher {
  static final Map<String, String> _complaintMap = {
    // 1. Chest pain / Heart -> Cardiologist
    'chest pain': 'Cardiologist',
    'heart pain': 'Cardiologist',
    'heart problem': 'Cardiologist',
    'chest tightness': 'Cardiologist',
    'chest pressure': 'Cardiologist',
    'palpitation': 'Cardiologist',
    'heart attack': 'Cardiologist',
    'cardiac': 'Cardiologist',
    'buk e batha': 'Cardiologist',
    'buke batha': 'Cardiologist',
    'buk batha': 'Cardiologist',
    'buker batha': 'Cardiologist',
    'buke chap': 'Cardiologist',
    'buke jala': 'Cardiologist',
    'hrider shomossha': 'Cardiologist',
    'hridrog': 'Cardiologist',
    'harte shomossha': 'Cardiologist',
    'হার্ট': 'Cardiologist',
    'বুকে ব্যথা': 'Cardiologist',
    'বুকের ব্যথা': 'Cardiologist',
    'বুকে চাপ': 'Cardiologist',
    'বুকে জ্বালা': 'Cardiologist',
    'হৃদরোগ': 'Cardiologist',
    'হার্টের সমস্যা': 'Cardiologist',

    // 2. High Blood Pressure -> Cardiologist
    'high blood pressure': 'Cardiologist',
    'hypertension': 'Cardiologist',
    'high bp': 'Cardiologist',
    'pressure problem': 'Cardiologist',
    'blood pressure': 'Cardiologist',
    'uccho rokto chap': 'Cardiologist',
    'high pressure': 'Cardiologist',
    'preshar beshi': 'Cardiologist',
    'উচ্চ রক্তচাপ': 'Cardiologist',
    'হাই প্রেসার': 'Cardiologist',
    'রক্তচাপ': 'Cardiologist',

    // 3. Fever & General -> General Physician
    'fever': 'General Physician',
    'high temperature': 'General Physician',
    'chills': 'General Physician',
    'body ache': 'General Physician',
    'viral fever': 'General Physician',
    'weakness': 'General Physician',
    'jwor': 'General Physician',
    'jor': 'General Physician',
    'gae jor': 'General Physician',
    'shorir batha': 'General Physician',
    'gae batha': 'General Physician',
    'kapuni': 'General Physician',
    'durbolota': 'General Physician',
    'headache': 'General Physician',
    'matha batha': 'General Physician',
    'mathar batha': 'General Physician',
    'জ্বর': 'General Physician',
    'গায়ে জ্বর': 'General Physician',
    'শরীর ব্যথা': 'General Physician',
    'দুর্বলতা': 'General Physician',
    'মাথা ব্যথা': 'General Physician',
    'মাথার ব্যথা': 'General Physician',

    // 4. Diabetes & Thyroid -> Endocrinologist
    'diabetes': 'Endocrinologist',
    'blood sugar': 'Endocrinologist',
    'high sugar': 'Endocrinologist',
    'insulin': 'Endocrinologist',
    'diabetic': 'Endocrinologist',
    'shugar': 'Endocrinologist',
    'chini rog': 'Endocrinologist',
    'bohumutro': 'Endocrinologist',
    'rokte chini': 'Endocrinologist',
    'ডায়াবেটিস': 'Endocrinologist',
    'সুগার': 'Endocrinologist',
    'বহুমূত্র': 'Endocrinologist',
    'thyroid': 'Endocrinologist',
    'goiter': 'Endocrinologist',
    'thairoid': 'Endocrinologist',
    'gola fula': 'Endocrinologist',
    'থাইরয়েড': 'Endocrinologist',
    'গলগণ্ড': 'Endocrinologist',

    // 5. Skin & Dermatology -> Dermatologist
    'skin rash': 'Dermatologist',
    'rash': 'Dermatologist',
    'skin problem': 'Dermatologist',
    'itching': 'Dermatologist',
    'eczema': 'Dermatologist',
    'psoriasis': 'Dermatologist',
    'fungal': 'Dermatologist',
    'dermatitis': 'Dermatologist',
    'chamrar shomossha': 'Dermatologist',
    'chulkani': 'Dermatologist',
    'chulkay': 'Dermatologist',
    'daud': 'Dermatologist',
    'pachra': 'Dermatologist',
    'chamra utha': 'Dermatologist',
    'চামড়ার সমস্যা': 'Dermatologist',
    'চুলকানি': 'Dermatologist',
    'দাদ': 'Dermatologist',
    'পাঁচড়া': 'Dermatologist',

    // 6. Acne & Hair -> Dermatologist
    'acne': 'Dermatologist',
    'pimple': 'Dermatologist',
    'pimples': 'Dermatologist',
    'bron': 'Dermatologist',
    'mukhe bron': 'Dermatologist',
    'ব্রণ': 'Dermatologist',
    'মুখের ব্রণ': 'Dermatologist',
    'hair loss': 'Dermatologist',
    'hair fall': 'Dermatologist',
    'dandruff': 'Dermatologist',
    'chul pora': 'Dermatologist',
    'chuler shomossha': 'Dermatologist',
    'khushki': 'Dermatologist',
    'চুল পড়া': 'Dermatologist',
    'খুশকি': 'Dermatologist',

    // 7. Eye -> Ophthalmologist
    'eye problem': 'Ophthalmologist',
    'eye pain': 'Ophthalmologist',
    'blurry vision': 'Ophthalmologist',
    'cataract': 'Ophthalmologist',
    'red eye': 'Ophthalmologist',
    'vision loss': 'Ophthalmologist',
    'glaucoma': 'Ophthalmologist',
    'chokhe shomossha': 'Ophthalmologist',
    'chokh batha': 'Ophthalmologist',
    'chokh lal': 'Ophthalmologist',
    'jhapsha dekha': 'Ophthalmologist',
    'chokhe pani': 'Ophthalmologist',
    'চোখের সমস্যা': 'Ophthalmologist',
    'চোখে ব্যথা': 'Ophthalmologist',
    'চোখ লাল': 'Ophthalmologist',
    'ঝাপসা দেখা': 'Ophthalmologist',
    'ছানি': 'Ophthalmologist',

    // 8. Dental -> Dentist
    'toothache': 'Dentist',
    'tooth pain': 'Dentist',
    'tooth': 'Dentist',
    'teeth': 'Dentist',
    'dental': 'Dentist',
    'bleeding gum': 'Dentist',
    'cavity': 'Dentist',
    'swollen gum': 'Dentist',
    'danter batha': 'Dentist',
    'dat batha': 'Dentist',
    'mare batha': 'Dentist',
    'dat diye rokto': 'Dentist',
    'dater shomossha': 'Dentist',
    'danter': 'Dentist',
    'দাঁতের ব্যথা': 'Dentist',
    'দাঁত ব্যথা': 'Dentist',
    'মাড়ি ব্যথা': 'Dentist',
    'দাঁতের সমস্যা': 'Dentist',
    'দাঁতের': 'Dentist',
    'দাঁত': 'Dentist',

    // 9. Stomach / Gastro -> Gastroenterologist
    'stomach pain': 'Gastroenterologist',
    'abdominal pain': 'Gastroenterologist',
    'acidity': 'Gastroenterologist',
    'heartburn': 'Gastroenterologist',
    'gas problem': 'Gastroenterologist',
    'diarrhea': 'Gastroenterologist',
    'vomiting': 'Gastroenterologist',
    'nausea': 'Gastroenterologist',
    'indigestion': 'Gastroenterologist',
    'gastric': 'Gastroenterologist',
    'constipation': 'Gastroenterologist',
    'pete batha': 'Gastroenterologist',
    'pet batha': 'Gastroenterologist',
    'gaser shomossha': 'Gastroenterologist',
    'pet kharap': 'Gastroenterologist',
    'bomi': 'Gastroenterologist',
    'kosthokathinno': 'Gastroenterologist',
    'badhojom': 'Gastroenterologist',
    'পেটে ব্যথা': 'Gastroenterologist',
    'পেট ব্যথা': 'Gastroenterologist',
    'গ্যাসের সমস্যা': 'Gastroenterologist',
    'এসিডিটি': 'Gastroenterologist',
    'বমি': 'Gastroenterologist',
    'কোষ্ঠকাঠিন্য': 'Gastroenterologist',
    'বদহজম': 'Gastroenterologist',

    // 10. Headache / Neuro -> Neurologist
    // Specific compound phrases reserved for Neurologist (bare "headache" mapped to General Physician)
    'severe headache with blurred vision': 'Neurologist',
    'chronic migraine': 'Neurologist',
    'one-sided weakness headache': 'Neurologist',
    'severe headache': 'Neurologist',
    'migraine': 'Neurologist',
    'dizziness': 'Neurologist',
    'numbness': 'Neurologist',
    'seizure': 'Neurologist',
    'stroke': 'Neurologist',
    'nerve pain': 'Neurologist',
    'vertigo': 'Neurologist',
    'matha ghora': 'Neurologist',
    'obosh': 'Neurologist',
    'mirgi': 'Neurologist',
    'মাইগ্রেন': 'Neurologist',
    'মাথা ঘোরা': 'Neurologist',
    'অবশ': 'Neurologist',
    'মৃগী': 'Neurologist',

    // 11. Back & Spine -> Orthopedist
    'back pain': 'Orthopedist',
    'spine pain': 'Orthopedist',
    'sciatica': 'Orthopedist',
    'lower back pain': 'Orthopedist',
    'pither batha': 'Orthopedist',
    'pit batha': 'Orthopedist',
    'komor batha': 'Orthopedist',
    'komorer batha': 'Orthopedist',
    'merudondo batha': 'Orthopedist',
    'পিঠের ব্যথা': 'Orthopedist',
    'পিঠে ব্যথা': 'Orthopedist',
    'কোমর ব্যথা': 'Orthopedist',
    'কোমরে ব্যথা': 'Orthopedist',
    'মেরুদণ্ডে ব্যথা': 'Orthopedist',

    // 12. Joint & Bone -> Orthopedist
    'joint pain': 'Orthopedist',
    'bone pain': 'Orthopedist',
    'arthritis': 'Orthopedist',
    'knee pain': 'Orthopedist',
    'fracture': 'Orthopedist',
    'sprain': 'Orthopedist',
    'harer batha': 'Orthopedist',
    'har batha': 'Orthopedist',
    'hatur batha': 'Orthopedist',
    'gora batha': 'Orthopedist',
    'joint batha': 'Orthopedist',
    'bat batha': 'Orthopedist',
    'হাড়ের ব্যথা': 'Orthopedist',
    'হাড় ব্যথা': 'Orthopedist',
    'হাঁটুর ব্যথা': 'Orthopedist',
    'বাতের ব্যথা': 'Orthopedist',
    'জয়েন্টে ব্যথা': 'Orthopedist',

    // 13. Breathing & Lung -> Pulmonologist
    'breathing problem': 'Pulmonologist',
    'shortness of breath': 'Pulmonologist',
    'asthma': 'Pulmonologist',
    'wheezing': 'Pulmonologist',
    'respiratory': 'Pulmonologist',
    'shas koshto': 'Pulmonologist',
    'shasher shomossha': 'Pulmonologist',
    'hapani': 'Pulmonologist',
    'shash nite koshto': 'Pulmonologist',
    'শ্বাসকষ্ট': 'Pulmonologist',
    'শ্বাসের সমস্যা': 'Pulmonologist',
    'হাঁপানি': 'Pulmonologist',
    'শ্বাস নিতে কষ্ট': 'Pulmonologist',

    // 14. Cough -> Pulmonologist
    'cough': 'Pulmonologist',
    'coughing': 'Pulmonologist',
    'dry cough': 'Pulmonologist',
    'phlegm': 'Pulmonologist',
    'bronchitis': 'Pulmonologist',
    'kashi': 'Pulmonologist',
    'shordi kashi': 'Pulmonologist',
    'shukna kashi': 'Pulmonologist',
    'kof': 'Pulmonologist',
    'kaashi': 'Pulmonologist',
    'কাশি': 'Pulmonologist',
    'সর্দি কাশি': 'Pulmonologist',
    'শুকনো কাশি': 'Pulmonologist',
    'কফ': 'Pulmonologist',

    // 15. Kidney -> Nephrologist
    'kidney problem': 'Nephrologist',
    'kidney pain': 'Nephrologist',
    'kidney stone': 'Nephrologist',
    'renal': 'Nephrologist',
    'dialysis': 'Nephrologist',
    'kidney shomossha': 'Nephrologist',
    'kidney er shomossha': 'Nephrologist',
    'kidney batha': 'Nephrologist',
    'kidney te pathor': 'Nephrologist',
    'কিডনির সমস্যা': 'Nephrologist',
    'কিডনি ব্যথা': 'Nephrologist',
    'কিডনিতে পাথর': 'Nephrologist',

    // 16. Mental Health -> Psychiatrist
    'depression': 'Psychiatrist',
    'anxiety': 'Psychiatrist',
    'panic attack': 'Psychiatrist',
    'mental problem': 'Psychiatrist',
    'insomnia': 'Psychiatrist',
    'sleep problem': 'Psychiatrist',
    'stress': 'Psychiatrist',
    'moner shomossha': 'Psychiatrist',
    'manoshik shomossha': 'Psychiatrist',
    'ghum hoy na': 'Psychiatrist',
    'chinta': 'Psychiatrist',
    'tension': 'Psychiatrist',
    'voy lage': 'Psychiatrist',
    'মনের সমস্যা': 'Psychiatrist',
    'মানসিক সমস্যা': 'Psychiatrist',
    'ঘুম হয় না': 'Psychiatrist',
    'দুশ্চিন্তা': 'Psychiatrist',
    'হতাশা': 'Psychiatrist',

    // 17. Child Health -> Pediatrician
    'child health': 'Pediatrician',
    'baby sickness': 'Pediatrician',
    'infant': 'Pediatrician',
    'pediatrics': 'Pediatrician',
    'pediatric': 'Pediatrician',
    'shishu': 'Pediatrician',
    'shishu rog': 'Pediatrician',
    'baccader shomossha': 'Pediatrician',
    'bacchar jor': 'Pediatrician',
    'shishur batha': 'Pediatrician',
    'শিশু': 'Pediatrician',
    'শিশু রোগ': 'Pediatrician',
    'বাচ্চাদের সমস্যা': 'Pediatrician',
    'বাচ্চার জ্বর': 'Pediatrician',
    'শিশুর সমস্যা': 'Pediatrician',

    // 18. Pregnancy -> Gynecologist
    'pregnancy': 'Gynecologist',
    'pregnant': 'Gynecologist',
    'delivery': 'Gynecologist',
    'prenatal': 'Gynecologist',
    'gorbhoboti': 'Gynecologist',
    'gorbha': 'Gynecologist',
    'baccha hobe': 'Gynecologist',
    'gorbhavastha': 'Gynecologist',
    'proshob': 'Gynecologist',
    'গর্ভবতী': 'Gynecologist',
    'গর্ভাবস্থা': 'Gynecologist',
    'বাচ্চা হবে': 'Gynecologist',
    'প্রসব': 'Gynecologist',

    // 19. Women Health -> Gynecologist
    'women health': 'Gynecologist',
    'period pain': 'Gynecologist',
    'menstrual problem': 'Gynecologist',
    'irregular period': 'Gynecologist',
    'pcos': 'Gynecologist',
    'mohilar shomossha': 'Gynecologist',
    'masik shomossha': 'Gynecologist',
    'period er batha': 'Gynecologist',
    'oniyomito masik': 'Gynecologist',
    'jorayu': 'Gynecologist',
    'মহিলার সমস্যা': 'Gynecologist',
    'মাসিক সমস্যা': 'Gynecologist',
    'পিরিয়ডের ব্যথা': 'Gynecologist',
    'অনিয়মিত মাসিক': 'Gynecologist',
    'জরায়ু': 'Gynecologist',

    // 20. Ear -> ENT Specialist
    'ear problem': 'ENT Specialist',
    'ear pain': 'ENT Specialist',
    'ear infection': 'ENT Specialist',
    'hearing loss': 'ENT Specialist',
    'tinnitus': 'ENT Specialist',
    'kaner shomossha': 'ENT Specialist',
    'kan batha': 'ENT Specialist',
    'kane shune na': 'ENT Specialist',
    'kan paka': 'ENT Specialist',
    'কানের সমস্যা': 'ENT Specialist',
    'কান ব্যথা': 'ENT Specialist',
    'কানে শোনে না': 'ENT Specialist',
    'কান পাকা': 'ENT Specialist',

    // 21. Nose -> ENT Specialist
    'nose problem': 'ENT Specialist',
    'blocked nose': 'ENT Specialist',
    'sinus': 'ENT Specialist',
    'sinusitis': 'ENT Specialist',
    'nose bleeding': 'ENT Specialist',
    'runny nose': 'ENT Specialist',
    'polyp': 'ENT Specialist',
    'naker shomossha': 'ENT Specialist',
    'nak bondho': 'ENT Specialist',
    'nak diye rokto': 'ENT Specialist',
    'nake pani': 'ENT Specialist',
    'নাকের সমস্যা': 'ENT Specialist',
    'নাক বন্ধ': 'ENT Specialist',
    'সাইনাস': 'ENT Specialist',
    'নাক দিয়ে রক্ত': 'ENT Specialist',

    // 22. Throat -> ENT Specialist
    'throat pain': 'ENT Specialist',
    'sore throat': 'ENT Specialist',
    'tonsil': 'ENT Specialist',
    'tonsillitis': 'ENT Specialist',
    'difficulty swallowing': 'ENT Specialist',
    'gola batha': 'ENT Specialist',
    'golar shomossha': 'ENT Specialist',
    'gola bhenge geche': 'ENT Specialist',
    'gilte koshto': 'ENT Specialist',
    'গলা ব্যথা': 'ENT Specialist',
    'গলার সমস্যা': 'ENT Specialist',
    'টনসিল': 'ENT Specialist',
    'গিলতে কষ্ট': 'ENT Specialist',

    // 23. Cancer -> Oncologist
    'cancer': 'Oncologist',
    'tumor': 'Oncologist',
    'tumour': 'Oncologist',
    'chemotherapy': 'Oncologist',
    'oncology': 'Oncologist',
    'kensar': 'Oncologist',
    'ক্যান্সার': 'Oncologist',
    'টিউমার': 'Oncologist',
    'কেমোথেরাপি': 'Oncologist',

    // 24. Liver -> Hepatologist
    'liver problem': 'Hepatologist',
    'jaundice': 'Hepatologist',
    'fatty liver': 'Hepatologist',
    'hepatitis': 'Hepatologist',
    'liver cirrhosis': 'Hepatologist',
    'liver er shomossha': 'Hepatologist',
    'jondis': 'Hepatologist',
    'holud chokh': 'Hepatologist',
    'লিভারের সমস্যা': 'Hepatologist',
    'জন্ডিস': 'Hepatologist',
    'হেপাটাইটিস': 'Hepatologist',

    // 25. Surgery -> General Surgeon
    'surgery': 'General Surgeon',
    'operation': 'General Surgeon',
    'hernia': 'General Surgeon',
    'appendix': 'General Surgeon',
    'appendicitis': 'General Surgeon',
    'gallstone': 'General Surgeon',
    'abscess': 'General Surgeon',
    'apendiks': 'General Surgeon',
    'pitta pathor': 'General Surgeon',
    'fura': 'General Surgeon',
    'সার্জারি': 'General Surgeon',
    'অপারেশন': 'General Surgeon',
    'হার্নিয়া': 'General Surgeon',
    'পিত্তপাথর': 'General Surgeon',
    'ফোড়া': 'General Surgeon',

    // 26. Urine / Urology -> Urologist
    'urine problem': 'Urologist',
    'burning urination': 'Urologist',
    'frequent urination': 'Urologist',
    'blood in urine': 'Urologist',
    'prostate': 'Urologist',
    'urinary tract infection': 'Urologist',
    'uti': 'Urologist',
    'peshab er shomossha': 'Urologist',
    'peshab jala pora': 'Urologist',
    'bar bar peshab': 'Urologist',
    'peshabe rokto': 'Urologist',
    'prosrab': 'Urologist',
    'প্রস্রাবের সমস্যা': 'Urologist',
    'প্রস্রাবে জ্বালাপোড়া': 'Urologist',
    'ঘন ঘন প্রস্রাব': 'Urologist',
    'প্রস্রাবে রক্ত': 'Urologist',

    // 27. Allergy -> Allergist
    'allergy': 'Allergist',
    'allergic': 'Allergist',
    'sneezing': 'Allergist',
    'dust allergy': 'Allergist',
    'food allergy': 'Allergist',
    'ellargi': 'Allergist',
    'elargi': 'Allergist',
    'hachi': 'Allergist',
    'dhula te shomossha': 'Allergist',
    'অ্যালার্জি': 'Allergist',
    'এলার্জি': 'Allergist',
    'হাঁচি': 'Allergist',

    // 28. Blood / Hematology -> Hematologist
    'anemia': 'Hematologist',
    'low hemoglobin': 'Hematologist',
    'blood disorder': 'Hematologist',
    'leukemia': 'Hematologist',
    'thalassemia': 'Hematologist',
    'roktosholpota': 'Hematologist',
    'rokter shomossha': 'Hematologist',
    'rokto kom': 'Hematologist',
    'রক্তস্বল্পতা': 'Hematologist',
    'রক্তের সমস্যা': 'Hematologist',
    'রক্ত কম': 'Hematologist',
    'থ্যালাসেমিয়া': 'Hematologist',

    // 29. Pain & Physical Medicine -> Physical Medicine Specialist
    'body pain': 'Physical Medicine Specialist',
    'neck pain': 'Physical Medicine Specialist',
    'shoulder pain': 'Physical Medicine Specialist',
    'muscle pain': 'Physical Medicine Specialist',
    'paralysis': 'Physical Medicine Specialist',
    'physical therapy': 'Physical Medicine Specialist',
    'shorir betha': 'Physical Medicine Specialist',
    'ghar batha': 'Physical Medicine Specialist',
    'kadher batha': 'Physical Medicine Specialist',
    'mashol batha': 'Physical Medicine Specialist',
    'batha bedona': 'Physical Medicine Specialist',
    'শরীরে ব্যথা': 'Physical Medicine Specialist',
    'ঘাড় ব্যথা': 'Physical Medicine Specialist',
    'কাঁধ ব্যথা': 'Physical Medicine Specialist',
    'পেশীর ব্যথা': 'Physical Medicine Specialist',
    'ব্যথা বেদনা': 'Physical Medicine Specialist',

    // 30. Piles / Colorectal -> Colorectal Surgeon
    'piles': 'Colorectal Surgeon',
    'hemorrhoids': 'Colorectal Surgeon',
    'anal fissure': 'Colorectal Surgeon',
    'fistula': 'Colorectal Surgeon',
    'rectal bleeding': 'Colorectal Surgeon',
    'pails': 'Colorectal Surgeon',
    'feshula': 'Colorectal Surgeon',
    'molodware batha': 'Colorectal Surgeon',
    'rokto pora': 'Colorectal Surgeon',
    'পাইলস': 'Colorectal Surgeon',
    'ফিস্টুলা': 'Colorectal Surgeon',
    'মলদ্বারে ব্যথা': 'Colorectal Surgeon',
  };

  /// Normalizes input by lowercasing and stripping punctuation.
  static String normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s\u0980-\u09FF]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Preloads or initializes specialty symptom dictionary.
  static Future<void> load() async {
    // Fast in-memory map initialized; ready instantly.
  }

  /// Detects whether input is English ('en'), Bengali script ('bn'), Banglish ('banglish'), or 'unknown'.
  static String detectLanguage(String input) {
    if (RegExp(r'[\u0980-\u09FF]').hasMatch(input)) {
      return 'bn';
    }
    const banglishStems = [
      'batha', 'shomossha', 'jwor', 'jor', 'kashi', 'har', 'pet', 'chul', 'matha',
      'peshab', 'komor', 'kan', 'nak', 'gola', 'chokh', 'dat', 'danter', 'gae',
      'buke', 'chap', 'buk', 'hrid', 'rokto', 'shas', 'dam', 'bomi', 'daud', 'bron'
    ];
    final lower = input.toLowerCase();
    for (final stem in banglishStems) {
      if (lower.contains(stem)) return 'banglish';
    }
    if (RegExp(r'[a-zA-Z]').hasMatch(input)) {
      return 'en';
    }
    return 'unknown';
  }

  /// Matches user symptom complaint to a medical specialty using 'contains' matching.
  /// Returns MatchResult or null if no match found.
  static MatchResult? match(String input) {
    final cleaned = normalize(input);
    if (cleaned.isEmpty) return null;

    // Check longest matches first to prioritize specific multi-word complaints
    final sortedKeys = _complaintMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    final matches = <String>{};
    for (final key in sortedKeys) {
      if (cleaned.contains(key)) {
        matches.add(_complaintMap[key]!);
      }
    }

    if (matches.isEmpty) return null;

    final top = matches.first;
    final alts = matches.toList();
    return MatchResult(
      topSpecialty: top,
      alternatives: alts,
      isVague: alts.length > 1,
    );
  }
}
