class Chamber {
  final String? hospitalName;
  final String? area;
  final String? location;

  Chamber({
    this.hospitalName,
    this.area,
    this.location,
  });

  factory Chamber.fromJson(Map<String, dynamic> json) {
    return Chamber(
      hospitalName: json['hospitalName'] as String?,
      area: json['area'] as String?,
      location: json['location'] as String?,
    );
  }
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
      bayesianRating: (json['bayesianRating'] as num?)?.toDouble(),
      ratingAverage: (json['ratingAverage'] as num?)?.toDouble(),
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      chambers: parsedChambers,
      chamber: parsedChamber,
      distance: (json['distance'] as num?)?.toDouble(),
    );
  }
}
