import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../l10n/app_localizations.dart';
import '../providers/child_provider.dart';
import '../providers/location_provider.dart';
import '../providers/geofence_provider.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';
import '../widgets/app_drawer.dart';

class MapScreen extends StatefulWidget {
  final String? childId;

  const MapScreen({super.key, this.childId});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _isLoading = true;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  bool _showLiveTracking = true;
  bool _showSafeZones = true;
  bool _showChildLocation = true;
  double _defaultZoom = 16.0;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    await _getCurrentLocation();
    if (widget.childId != null) {
      await _loadChildData();
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _loadChildData() async {
    if (widget.childId == null) return;

    final childProvider = Provider.of<ChildProvider>(context, listen: false);
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);

    await childProvider.getChildWithDevice(widget.childId!);
    await locationProvider.getLiveLocation(widget.childId!);
    await geofenceProvider.loadSafeZones(widget.childId!);

    locationProvider.startLiveTracking(widget.childId!);
    _updateMarkers();
  }

  void _updateMarkers() {
    final l10n = context.l10n;
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);
    final location = locationProvider.liveLocation;

    Set<Marker> markers = {};
    Set<Circle> circles = {};

    if (_showChildLocation && location != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('child'),
          position: LatLng(location.latitude, location.longitude),
          infoWindow: InfoWindow(
            title: l10n.childLocation,
            snippet: l10n.liveTracking,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current'),
          position:
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          infoWindow: InfoWindow(
            title: l10n.myLocation,
            snippet: l10n.currentPosition,
          ),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }

    if (_showSafeZones) {
      for (final zone in geofenceProvider.safeZones) {
        final isActive = zone.status == 'active';
        final color = isActive ? AppColors.successColor : Colors.grey;

        circles.add(
          Circle(
            circleId: CircleId(zone.id),
            center: LatLng(zone.latitude, zone.longitude),
            radius: zone.radius.toDouble(),
            fillColor: color.withValues(alpha: isActive ? 0.15 : 0.08),
            strokeColor: color,
            strokeWidth: isActive ? 2 : 1,
          ),
        );
      }
    }

    setState(() {
      _markers = markers;
      _circles = circles;
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _updateMarkers();
  }

  LatLng _getInitialPosition() {
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final location = locationProvider.liveLocation;

    if (location != null) {
      return LatLng(location.latitude, location.longitude);
    }

    if (_currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }

    return const LatLng(
        AppConstants.defaultLatitude, AppConstants.defaultLongitude);
  }

  void _showMapSettings() {
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settings,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(l10n.liveTracking),
              subtitle: Text(l10n.showChildLocation),
              value: _showLiveTracking,
              activeColor: AppColors.primaryColor,
              onChanged: (value) {
                setState(() {
                  _showLiveTracking = value;
                });
                Navigator.pop(context);
                if (value && widget.childId != null) {
                  final locationProvider =
                      Provider.of<LocationProvider>(context, listen: false);
                  locationProvider.startLiveTracking(widget.childId!);
                }
              },
            ),
            SwitchListTile(
              title: Text(l10n.safeZones),
              subtitle: Text(l10n.showSafeZones),
              value: _showSafeZones,
              activeColor: AppColors.primaryColor,
              onChanged: (value) {
                setState(() {
                  _showSafeZones = value;
                });
                _updateMarkers();
                Navigator.pop(context);
              },
            ),
            SwitchListTile(
              title: Text(l10n.childLocation),
              subtitle: Text(l10n.showChildMarker),
              value: _showChildLocation,
              activeColor: AppColors.primaryColor,
              onChanged: (value) {
                setState(() {
                  _showChildLocation = value;
                });
                _updateMarkers();
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
            Text(
              l10n.defaultZoomLevel,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Slider(
              value: _defaultZoom,
              min: 10,
              max: 20,
              divisions: 10,
              label: _defaultZoom.toStringAsFixed(1),
              activeColor: AppColors.primaryColor,
              onChanged: (value) {
                setState(() {
                  _defaultZoom = value;
                });
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.save),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(l10n.map),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
            tooltip: l10n.menu,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showMapSettings,
            tooltip: l10n.settings,
          ),
          IconButton(
            icon: const Icon(Icons.child_care),
            onPressed: () {
              Navigator.pushNamed(context, '/add-child');
            },
            tooltip: l10n.addChild,
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () async {
              await _getCurrentLocation();
              if (_currentPosition != null && _mapController != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newLatLng(
                    LatLng(_currentPosition!.latitude,
                        _currentPosition!.longitude),
                  ),
                );
              }
            },
            tooltip: l10n.locationSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: _getInitialPosition(),
                    zoom: _defaultZoom,
                  ),
                  markers: _markers,
                  circles: _circles,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: true,
                ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: AppColors.primaryColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(l10n.child,
                                  style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 16),
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: AppColors.successColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(l10n.myLocation,
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                          if (_showSafeZones) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: AppColors.successColor.withValues(
                                      alpha: 0.3,
                                    ),
                                    border: Border.all(
                                        color: AppColors.successColor),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(l10n.safeZones,
                                    style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: FloatingActionButton(
                    mini: true,
                    heroTag: 'settings',
                    onPressed: _showMapSettings,
                    backgroundColor: Colors.white,
                    child:
                        const Icon(Icons.layers, color: AppColors.primaryColor),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await _getCurrentLocation();
          if (_currentPosition != null && _mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLng(
                LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
              ),
            );
          }
        },
        child: const Icon(Icons.my_location),
      ),
    );
  }
}
