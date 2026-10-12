import '../widgets/chamber_accessibility.dart';

class Chamber {
  final String? id;
  final String? hospitalName;
  final String? area;
  final String? location;
  final String? visitingHours;
  final int? fee;
  final ChamberAccessibility? accessibility;
  final bool isAccessible;
  final List<String> accessibilityFeatures;

  Chamber({
    this.id,
    this.hospitalName,
    this.area,
    this.location,
    this.visitingHours,
    this.fee,
    this.accessibility,
    this.isAccessible = false,
    this.accessibilityFeatures = const [],
  });

  factory Chamber.fromJson(Map<String, dynamic> json) {
    ChamberAccessibility? accessibility;
    if (json['accessibility'] != null && json['accessibility'] is Map<String, dynamic>) {
      accessibility = ChamberAccessibility.fromJson(json['accessibility'] as Map<String, dynamic>);
    } else if (json['wheelchairEntrance'] != null) {
      accessibility = ChamberAccessibility.fromJson(json);
    }

    final bool rawIsAccessible = (json['isAccessible'] as bool?) ??
        (accessibility?.wheelchairEntrance == true);

    final List<String> features = [];
    if (json['accessibilityFeatures'] != null && json['accessibilityFeatures'] is List) {
      features.addAll((json['accessibilityFeatures'] as List).map((e) => e.toString()));
    } else {
      if (json['wheelchairEntrance'] == true) features.add('Ramp');
      if (json['liftAvailable'] == true) features.add('Lift/Elevator');
      if (json['accessibleToilet'] == true) features.add('Accessible washroom');
    }

    return Chamber(
      id: json['id'] as String?,
      hospitalName: (json['hospitalName'] ?? json['name']) as String?,
      area: json['area'] as String?,
      location: json['location'] as String?,
      visitingHours: json['visitingHours'] as String?,
      fee: (json['fee'] as num?)?.toInt(),
      accessibility: accessibility,
      isAccessible: rawIsAccessible,
      accessibilityFeatures: features,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'hospitalName': hospitalName,
    'area': area,
    'location': location,
    if (visitingHours != null) 'visitingHours': visitingHours,
    if (fee != null) 'fee': fee,
    'accessibility': accessibility?.toJson(),
    'isAccessible': isAccessible,
    'accessibilityFeatures': accessibilityFeatures,
  };
}

class Doctor {
  final String id;
  final String name;
  final List<String> specialities;
  final double experienceYears;
  final List<String> education;
  final List<String> concentrations;
  final String? designation;
  final String? bmdcRegNumber;
  final bool isBmdcVerified;
  final bool isClaimed;
  final String? claimedByUid;
  final String? certificateImageUrl;
  final double? bayesianRating;
  final double? ratingAverage;
  final int ratingCount;
  final List<Chamber> chambers;
  final Chamber? chamber;
  final double? distance;

  Doctor({
    required this.id,
    required this.name,
    required this.specialities,
    required this.experienceYears,
    required this.education,
    required this.concentrations,
    this.designation,
    this.bmdcRegNumber,
    required this.isBmdcVerified,
    this.isClaimed = false,
    this.claimedByUid,
    this.certificateImageUrl,
    this.bayesianRating,
    this.ratingAverage,
    required this.ratingCount,
    required this.chambers,
    this.chamber,
    this.distance,
  });

  bool get hasAccessibleChamber {
    if (chamber?.isAccessible == true) return true;
    return chambers.any((c) => c.isAccessible);
  }

  factory Doctor.fromJson(Map<String, dynamic> json) {
    List<Chamber> parsedChambers = [];
    if (json['chambers'] != null) {
      parsedChambers = (json['chambers'] as List)
          .map((c) => Chamber.fromJson(c))
          .toList();
    }

    Chamber? parsedChamber;
    if (json['chamber'] != null) {
      parsedChamber = Chamber.fromJson(json['chamber']);
      if (parsedChambers.isEmpty) {
        parsedChambers.add(parsedChamber);
      }
    } else if (parsedChambers.isNotEmpty) {
      parsedChamber = parsedChambers.first;
    }

    return Doctor(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: json['name'] ?? '',
      specialities: (json['specialities'] as List?)?.map((e) => e.toString()).toList() ?? [],
      experienceYears: (json['experienceYears'] as num?)?.toDouble() ?? 0.0,
      education: (json['education'] as List?)?.map((e) => e.toString()).toList() ?? [],
      concentrations: (json['concentrations'] as List?)?.map((e) => e.toString()).toList() ?? [],
      designation: json['designation'],
      bmdcRegNumber: json['bmdcRegNumber'],
      isBmdcVerified: json['isBmdcVerified'] ?? false,
      isClaimed: json['isClaimed'] ?? false,
      claimedByUid: json['claimedByUid'],
      certificateImageUrl: json['certificateImageUrl'],
      bayesianRating: (json['bayesianRating'] as num?)?.toDouble(),
      ratingAverage: (json['ratingAverage'] as num?)?.toDouble(),
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      chambers: parsedChambers,
      chamber: parsedChamber,
      distance: (json['distance'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    'name': name,
    'specialities': specialities,
    'experienceYears': experienceYears,
    'education': education,
    'concentrations': concentrations,
    'designation': designation,
    'bmdcRegNumber': bmdcRegNumber,
    'isBmdcVerified': isBmdcVerified,
    'isClaimed': isClaimed,
    'claimedByUid': claimedByUid,
    'certificateImageUrl': certificateImageUrl,
    'bayesianRating': bayesianRating,
    'ratingAverage': ratingAverage,
    'ratingCount': ratingCount,
    'chambers': chambers.map((c) => c.toJson()).toList(),
    'chamber': chamber?.toJson(),
    'distance': distance,
  };
}
