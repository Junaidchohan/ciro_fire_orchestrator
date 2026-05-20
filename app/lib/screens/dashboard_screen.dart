import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/event_bus.dart';

// Instructions:
// Please add the following dependencies to your pubspec.yaml:
// flutter_map: ^6.1.0 (or latest compatible)
// latlong2: ^0.9.0 (or latest compatible)

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final MapController _mapController = MapController();
  List<dynamic> _crises = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCrises();
    
    EventBus().on<CrisisDetectedEvent>().listen((event) {
      _fetchCrises();
    });
  }

  Future<void> _fetchCrises() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/crises'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _crises = data['crises'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Color _getMarkerColor(String type) {
    final lowerType = type.toLowerCase();
    if (lowerType.contains('fire')) return Colors.red;
    if (lowerType.contains('smoke')) return Colors.orange;
    return Colors.blue;
  }

  void _showCrisisDetails(BuildContext context, dynamic crisis) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final allocations = crisis['allocation_plan'] ?? {};
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Crisis: ${crisis['type'] ?? 'Unknown'}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text('Severity: ${crisis['severity'] ?? 'N/A'}', style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              const Text('Allocated Resources:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (allocations.isNotEmpty) ...[
                if (allocations['fire_trucks'] != null)
                  Text('- Fire Trucks: ${allocations['fire_trucks']}'),
                if (allocations['ambulances'] != null)
                  Text('- Ambulances: ${allocations['ambulances']}'),
                if (allocations['police'] != null)
                  Text('- Police Units: ${allocations['police']}'),
              ] else ...[
                const Text('No resources allocated yet.'),
              ],
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crisis Map Dashboard'),
        backgroundColor: Colors.black87,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(33.6844, 73.0479),
              initialZoom: 12.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app',
              ),
              MarkerLayer(
                markers: _crises.map((crisis) {
                  double lat = 33.6844;
                  double lon = 73.0479;
                  
                  if (crisis['lat'] != null && crisis['lon'] != null) {
                    lat = double.tryParse(crisis['lat'].toString()) ?? lat;
                    lon = double.tryParse(crisis['lon'].toString()) ?? lon;
                  } else if (crisis['location'] != null) {
                    // Attempt basic parse if location string "lat,lon" exists, else fallback
                    final parts = crisis['location'].toString().split(',');
                    if (parts.length == 2) {
                      lat = double.tryParse(parts[0]) ?? lat;
                      lon = double.tryParse(parts[1]) ?? lon;
                    }
                  }

                  return Marker(
                    point: LatLng(lat, lon),
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => _showCrisisDetails(context, crisis),
                      child: Icon(
                        Icons.location_on,
                        color: _getMarkerColor(crisis['type'] ?? ''),
                        size: 40,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          if (!_isLoading && _crises.isEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'No active crises',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fetchCrises,
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
