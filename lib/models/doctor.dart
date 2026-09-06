import '../widgets/chamber_accessibility.dart';

class Chamber {
  final String? hospitalName;
  final String? area;
  final String? location;
  final ChamberAccessibility? accessibility;

  Chamber({
    this.hospitalName,
    this.area,
    this.location,
    this.accessibility,
  });

  factory Chamber.fromJson(Map<String, dynamic> json) {
    ChamberAccessibility? accessibility;
    if (json['accessibility'] != null && json['accessibility'] is Map<String, dynamic>) {
      accessibility = ChamberAccessibility.fromJson(json['accessibility'] as Map<String, dynamic>);
    } else if (json['wheelchairEntrance'] != null) {
      accessibility = ChamberAccessibility.fromJson(json);
    }

    return Chamber(
      hospitalName: json['hospitalName'] as String?,
      area: json['area'] as String?,
      location: json['location'] as String?,
      accessibility: accessibility,
    );
  }

  Map<String, dynamic> toJson() => {
    'hospitalName': hospitalName,
    'area': area,
    'location': location,
    'accessibility': accessibility?.toJson(),
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
      id: json['_id'] ?? '',
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
