import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart'
    hide PermissionStatus;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Routing Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MapPage(),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  LocationData? _currentLocation;
  bool _loading = true;
  double _currentZoom = 15.0;
  LatLng? _userMarker;
  List<LatLng> _route = [];
  StreamSubscription<LocationData>? _locationSubscription;
  DateTime? _lastRouteUpdate;
  bool _useImagery = true;

  @override
  void initState() {
    super.initState();
    checkLocationPermission();
    _getLocation();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> checkLocationPermission() async {
    try {
      // Check location service
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Location services are not enabled
        await Geolocator.openLocationSettings();
        return;
      }

      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // Permissions are denied
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // Permissions are permanently denied
        await openAppSettings();
        return;
      }

      // Permission granted, proceed with your location operations
    } catch (e) {
      print('❌ ERROR: $e');
    }
  }

  Future<void> _getLocation() async {
    final location = Location();

    try {
      for (int i = 0; i < 3; i++) {
        final serviceEnabled = await location.serviceEnabled();
        if (!serviceEnabled) {
          final requested = await location.requestService();
          if (!requested) {
            debugPrint("❌ Location service not enabled");
            await Future.delayed(Duration(seconds: 1));
            continue;
          }
        }
        break;
      }

      PermissionStatus permission = await location.hasPermission();
      if (permission != PermissionStatus.granted) {
        permission = await location.requestPermission();
        if (permission != PermissionStatus.granted) {
          debugPrint("❌ Permission not granted");
          return;
        }
      }

      final loc = await location.getLocation();
      setState(() {
        _currentLocation = loc;
        _loading = false;
      });

      _locationSubscription = location.onLocationChanged.listen((newLoc) {
        setState(() => _currentLocation = newLoc);
      });
    } catch (e) {
      debugPrint("❌ ERROR: $e");
    }
  }

  void _zoomIn() {
    setState(() {
      _currentZoom += 1;
      _mapController.move(_mapController.camera.center, _currentZoom);
    });
  }

  void _zoomOut() {
    setState(() {
      _currentZoom -= 1;
      _mapController.move(_mapController.camera.center, _currentZoom);
    });
  }

  Future<void> _setUserMarkerAndRoute(LatLng latLng) async {
    _userMarker = latLng;
    setState(() => _route = []);
    if (_currentLocation == null) return;

    final userLat = _currentLocation!.latitude ?? 0;
    final userLng = _currentLocation!.longitude ?? 0;

    final url =
        'https://router.project-osrm.org/route/v1/driving/$userLng,$userLat;${latLng.longitude},${latLng.latitude}?geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final coords = data["routes"][0]["geometry"]["coordinates"] as List;
        final points = coords
            .map((c) => LatLng(c[1] as double, c[0] as double))
            .toList();
        setState(() {
          _route = points;
        });
      }
    } catch (e) {
      // Handle error if needed
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Routing Demo')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _currentLocation == null
          ? const Center(child: Text('Could not get location'))
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(
                  _currentLocation!.latitude ?? 0,
                  _currentLocation!.longitude ?? 0,
                ),
                initialZoom: _currentZoom,
                onTap: (tapPosition, point) => _setUserMarkerAndRoute(point),
                onPositionChanged: (position, hasGesture) {
                  setState(() {
                    _currentZoom = position.zoom ?? _currentZoom;
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: _useImagery
                      ? "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
                      : "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                  subdomains: _useImagery ? [] : ['a', 'b', 'c'],
                  userAgentPackageName: 'com.app.wesocet',
                  // attributionBuilder: (_) => Text(
                  //   _useImagery
                  //       ? "© Esri, Maxar, Earthstar Geographics"
                  //       : "© OpenStreetMap contributors",
                  //   style: const TextStyle(fontSize: 10),
                  // ),
                ),
                PolylineLayer(
                  polylines: _route.isEmpty
                      ? []
                      : [
                          Polyline(
                            points: _route,
                            color: Colors.blue,
                            strokeWidth: 5.0,
                          ),
                        ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 80.0,
                      height: 80.0,
                      point: LatLng(
                        _currentLocation!.latitude ?? 0,
                        _currentLocation!.longitude ?? 0,
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.blue,
                        size: 40,
                      ),
                    ),
                    if (_userMarker != null)
                      Marker(
                        width: 60,
                        height: 60,
                        point: _userMarker!,
                        child: const Icon(
                          Icons.place,
                          color: Colors.red,
                          size: 36,
                        ),
                      ),
                  ],
                ),
              ],
            ),
      floatingActionButton: _currentLocation == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: "zoomIn",
                  mini: true,
                  onPressed: _zoomIn,
                  child: const Icon(Icons.zoom_in),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: "zoomOut",
                  mini: true,
                  onPressed: _zoomOut,
                  child: const Icon(Icons.zoom_out),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: "myLocation",
                  child: const Icon(Icons.my_location),
                  onPressed: () {
                    _mapController.move(
                      LatLng(
                        _currentLocation!.latitude ?? 0,
                        _currentLocation!.longitude ?? 0,
                      ),
                      _currentZoom,
                    );
                  },
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: "toggleMap",
                  child: Icon(_useImagery ? Icons.map : Icons.satellite),
                  onPressed: () {
                    setState(() {
                      _useImagery = !_useImagery;
                    });
                  },
                ),
              ],
            ),
    );
  }
}
