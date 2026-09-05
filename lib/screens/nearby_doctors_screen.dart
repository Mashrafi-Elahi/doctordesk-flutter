import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/doctor.dart';
import '../services/api_service.dart';
import 'doctor_detail_screen.dart';

class NearbyDoctorsScreen extends StatefulWidget {
  const NearbyDoctorsScreen({super.key});

  @override
  State<NearbyDoctorsScreen> createState() => _NearbyDoctorsScreenState();
}

class _NearbyDoctorsScreenState extends State<NearbyDoctorsScreen> {
  final TextEditingController _addressController = TextEditingController();

  List<Doctor> _doctors = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;
  bool _isSearchingSuggestions = false;
  String? _error;
  String? _locationLabel;
  bool _showManualInput = false;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    _requestLocationAndSearch();
  }

  Future<void> _requestLocationAndSearch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLoading = false;
          _showManualInput = true;
          _error = 'Location services are disabled. Please enter your address manually.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLoading = false;
            _showManualInput = true;
            _error = 'Location permission denied. Please enter your address manually.';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLoading = false;
          _showManualInput = true;
          _error = 'Location permission permanently denied. Please enter your address manually.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _lat = position.latitude;
      _lng = position.longitude;
      _locationLabel = 'Your current location';
      await _searchNearby();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _showManualInput = true;
        _error = 'Unable to get location. Please enter your address manually.';
      });
    }
  }

  Future<void> _searchNearby() async {
    if (_lat == null || _lng == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final doctors = await ApiService.fetchNearbyDoctors(
        lat: _lat!,
        lng: _lng!,
        radiusKm: 50,
      );
      setState(() {
        _doctors = doctors;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _searchAddress(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearchingSuggestions = true;
      _suggestions = [];
    });

    try {
      final results = await ApiService.fetchGeocodeSuggestions(query);
      setState(() {
        _suggestions = results;
        _isSearchingSuggestions = false;
      });
    } catch (e) {
      setState(() {
        _isSearchingSuggestions = false;
      });
    }
  }

  void _selectSuggestion(Map<String, dynamic> suggestion) {
    _lat = suggestion['lat'];
    _lng = suggestion['lng'];
    _locationLabel = suggestion['displayName'];
    _suggestions = [];
    _addressController.clear();
    _searchNearby();
  }

  String _formatDistance(double? distanceMeters) {
    if (distanceMeters == null) return '';
    if (distanceMeters < 1000) {
      return '${distanceMeters.toInt()} m away';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctors Near Me'),
      ),
      body: Column(
        children: [
          // Location info bar
          if (_locationLabel != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: colorScheme.primaryContainer.withOpacity(0.3),
              child: Row(
                children: [
                  Icon(Icons.location_on, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _locationLabel!,
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showManualInput = true;
                      });
                    },
                    child: const Text('Change', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Manual address input
          if (_showManualInput || _error != null && _doctors.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null && _doctors.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ),
                  TextField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      hintText: 'Enter area or address...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _isSearchingSuggestions
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                    onSubmitted: _searchAddress,
                    textInputAction: TextInputAction.search,
                  ),
                  // Suggestions
                  if (_suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: _suggestions.map((suggestion) {
                          return ListTile(
                            dense: true,
                            leading: Icon(Icons.place_outlined,
                                color: colorScheme.primary, size: 20),
                            title: Text(
                              suggestion['displayName'] ?? '',
                              style: const TextStyle(fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectSuggestion(suggestion),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _doctors.isEmpty && !_showManualInput
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.location_off_outlined,
                                  size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey[600])),
                              const SizedBox(height: 16),
                              FilledButton.tonal(
                                onPressed: _requestLocationAndSearch,
                                child: const Text('Try Again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _doctors.isEmpty && !_showManualInput && _lat != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off,
                                      size: 48, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text('No doctors found nearby',
                                      style: theme.textTheme.titleMedium),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Try increasing the search radius or searching a different area',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _doctors.isNotEmpty
                            ? ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                itemCount: _doctors.length,
                                itemBuilder: (context, index) {
                                  final doctor = _doctors[index];
                                  return _NearbyDoctorCard(
                                    doctor: doctor,
                                    distance:
                                        _formatDistance(doctor.distance),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => DoctorDetailScreen(
                                              doctorId: doctor.id),
                                        ),
                                      );
                                    },
                                  );
                                },
                              )
                            : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }
}

class _NearbyDoctorCard extends StatelessWidget {
  final Doctor doctor;
  final String distance;
  final VoidCallback onTap;

  const _NearbyDoctorCard({
    required this.doctor,
    required this.distance,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final initial = doctor.name.isNotEmpty ? doctor.name[0].toUpperCase() : '?';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  initial,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctor.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      doctor.specialities.isNotEmpty
                          ? doctor.specialities.join(', ')
                          : 'General',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    if (distance.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.near_me_outlined,
                              size: 14, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            distance,
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
