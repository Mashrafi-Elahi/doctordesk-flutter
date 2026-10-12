/// Offline Dhaka-area shortcuts used when GPS or Nominatim is unavailable.
/// Coordinates are approximate centroids and are only used to search nearby
/// chambers; an exact GPS position still wins when available.
class DhakaLocation {
  final String name;
  final double lat;
  final double lng;

  const DhakaLocation(this.name, this.lat, this.lng);

  Map<String, dynamic> toSuggestion() => {
        'displayName': '$name, Dhaka, Bangladesh',
        'lat': lat,
        'lng': lng,
      };
}

class DhakaLocations {
  DhakaLocations._();

  static const all = <DhakaLocation>[
    DhakaLocation('Dhanmondi', 23.7465, 90.3760),
    DhakaLocation('Gulshan', 23.7925, 90.4078),
    DhakaLocation('Banani', 23.7937, 90.4066),
    DhakaLocation('Baridhara', 23.7957, 90.4234),
    DhakaLocation('Bashundhara', 23.8151, 90.4256),
    DhakaLocation('Uttara', 23.8759, 90.3795),
    DhakaLocation('Airport', 23.8510, 90.4027),
    DhakaLocation('Mirpur', 23.8223, 90.3654),
    DhakaLocation('Kalyanpur', 23.7788, 90.3582),
    DhakaLocation('Pallabi', 23.8280, 90.3655),
    DhakaLocation('Agargaon', 23.7786, 90.3783),
    DhakaLocation('Shewrapara', 23.7938, 90.3743),
    DhakaLocation('Kazipara', 23.8014, 90.3748),
    DhakaLocation('Mohammadpur', 23.7679, 90.3585),
    DhakaLocation('Shyamoli', 23.7764, 90.3655),
    DhakaLocation('Mohakhali', 23.7776, 90.4054),
    DhakaLocation('Tejgaon', 23.7639, 90.3912),
    DhakaLocation('Farmgate', 23.7577, 90.3883),
    DhakaLocation('Badda', 23.7806, 90.4255),
    DhakaLocation('Rampura', 23.7639, 90.4253),
    DhakaLocation('Khilgaon', 23.7508, 90.4256),
    DhakaLocation('Malibagh', 23.7478, 90.4148),
    DhakaLocation('Motijheel', 23.7333, 90.4176),
    DhakaLocation('Paltan', 23.7364, 90.4126),
    DhakaLocation('Shahbag', 23.7388, 90.3957),
    DhakaLocation('Old Dhaka', 23.7161, 90.3968),
    DhakaLocation('Lalbagh', 23.7182, 90.3887),
    DhakaLocation('Wari', 23.7168, 90.4173),
    DhakaLocation('Jatrabari', 23.7104, 90.4351),
    DhakaLocation('Demra', 23.7221, 90.4673),
    DhakaLocation('Banasree', 23.7632, 90.4379),
    DhakaLocation('Cantonment', 23.8193, 90.3996),
    DhakaLocation('Mirpur Cantonment', 23.8398, 90.3582),
    DhakaLocation('BUP Medical', 23.8398, 90.3582),
  ];

  static List<Map<String, dynamic>> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    return all
        .where((location) => location.name.toLowerCase().contains(normalized))
        .take(6)
        .map((location) => location.toSuggestion())
        .toList();
  }
}
