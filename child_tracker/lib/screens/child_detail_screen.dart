import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../l10n/app_localizations.dart';
import '../models/location_model.dart';
import '../providers/child_provider.dart';
import '../providers/location_provider.dart';
import '../providers/alert_provider.dart';
import '../providers/geofence_provider.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';

class ChildDetailScreen extends StatefulWidget {
  final String childId;

  const ChildDetailScreen({super.key, required this.childId});

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  GoogleMapController? _mapController;
  Position? _parentLocation;
  bool _isLoadingParentLocation = false;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  LocationProvider? _locationProvider;
  GeofenceProvider? _geofenceProvider;
  LatLng? _lastFocusedTarget;

  @override
  void initState() {
    super.initState();
    _loadData();
    _getParentLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextLocationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    if (!identical(_locationProvider, nextLocationProvider)) {
      _locationProvider?.removeListener(_handleMapDataChanged);
      _locationProvider = nextLocationProvider;
      _locationProvider?.addListener(_handleMapDataChanged);
    }

    final nextGeofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);
    if (!identical(_geofenceProvider, nextGeofenceProvider)) {
      _geofenceProvider?.removeListener(_handleMapDataChanged);
      _geofenceProvider = nextGeofenceProvider;
      _geofenceProvider?.addListener(_handleMapDataChanged);
    }
  }

  void _handleMapDataChanged() {
    if (!mounted) {
      return;
    }

    _updateMarkers();
    _maybeFocusLiveLocation(_locationProvider?.liveLocation);
  }

  Future<void> _getParentLocation() async {
    setState(() {
      _isLoadingParentLocation = true;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _isLoadingParentLocation = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _parentLocation = position;
        _isLoadingParentLocation = false;
      });

      _updateMarkers();
    } catch (e) {
      setState(() {
        _isLoadingParentLocation = false;
      });
    }
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

    if (location != null) {
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

    for (final zone in geofenceProvider.safeZones) {
      circles.add(
        Circle(
          circleId: CircleId(zone.id),
          center: LatLng(zone.latitude, zone.longitude),
          radius: zone.radius.toDouble(),
          fillColor: AppColors.successColor.withValues(alpha: 0.2),
          strokeColor: AppColors.successColor,
          strokeWidth: 2,
        ),
      );
    }

    setState(() {
      _markers = markers;
      _circles = circles;
    });
  }

  Future<void> _loadData() async {
    final childProvider = Provider.of<ChildProvider>(context, listen: false);
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final alertProvider = Provider.of<AlertProvider>(context, listen: false);
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);

    await childProvider.getChildWithDevice(widget.childId);
    await locationProvider.getLiveLocation(widget.childId);
    await alertProvider.getUnreadCount(widget.childId);
    await geofenceProvider.loadSafeZones(widget.childId);

    locationProvider.startLiveTracking(widget.childId);
    _updateMarkers();
  }

  @override
  void dispose() {
    _locationProvider?.removeListener(_handleMapDataChanged);
    _geofenceProvider?.removeListener(_handleMapDataChanged);
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    locationProvider.stopLiveTracking();
    _mapController?.dispose();
    super.dispose();
  }

  LatLng _getInitialPosition() {
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final location = locationProvider.liveLocation;

    if (location != null) {
      return LatLng(location.latitude, location.longitude);
    }

    return const LatLng(0, 0);
  }

  void _maybeFocusLiveLocation(LocationModel? location) {
    if (_mapController == null || location == null) {
      return;
    }

    final nextTarget = LatLng(location.latitude, location.longitude);
    if (_lastFocusedTarget?.latitude == nextTarget.latitude &&
        _lastFocusedTarget?.longitude == nextTarget.longitude) {
      return;
    }

    _lastFocusedTarget = nextTarget;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _mapController == null) {
        return;
      }

      _mapController!.animateCamera(CameraUpdate.newLatLng(nextTarget));
    });
  }

  Widget _buildUnavailableMapState() {
    return Container(
      color: Colors.grey[100],
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_off,
            size: 44,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            'No live location available for this child',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The map will appear when the linked device sends valid GPS data.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _updateMarkers();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Consumer<ChildProvider>(
          builder: (context, childProvider, child) {
            return Text(childProvider.selectedChild?.name ?? l10n.children);
          },
        ),
        actions: [
          Consumer<AlertProvider>(
            builder: (context, alertProvider, child) {
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications),
                    onPressed: () {
                      Navigator.pushNamed(context, '/alerts',
                          arguments: widget.childId);
                    },
                  ),
                  if (alertProvider.unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${alertProvider.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'activity':
                  final childProvider =
                      Provider.of<ChildProvider>(context, listen: false);
                  if (childProvider.selectedChild != null) {
                    Navigator.pushNamed(
                      context,
                      '/activity',
                      arguments: {
                        'childId': widget.childId,
                        'childName': childProvider.selectedChild!.name,
                      },
                    );
                  }
                  break;
                case 'history':
                  final childProvider =
                      Provider.of<ChildProvider>(context, listen: false);
                  if (childProvider.selectedChild != null) {
                    Navigator.pushNamed(
                      context,
                      '/location-history',
                      arguments: {
                        'childId': widget.childId,
                        'childName': childProvider.selectedChild!.name,
                      },
                    );
                  }
                  break;
                case 'safe_zones':
                  Navigator.pushNamed(context, '/safe-zones',
                      arguments: widget.childId);
                  break;
                case 'refresh':
                  _loadData();
                  _getParentLocation();
                  break;
                case 'my_location':
                  _getParentLocation();
                  if (_parentLocation != null && _mapController != null) {
                    _mapController!.animateCamera(
                      CameraUpdate.newLatLng(
                        LatLng(_parentLocation!.latitude,
                            _parentLocation!.longitude),
                      ),
                    );
                  }
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'activity',
                child: Row(
                  children: [
                    const Icon(Icons.analytics, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(l10n.activity),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    const Icon(Icons.history, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(l10n.locationHistory),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'safe_zones',
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(l10n.safeZones),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'my_location',
                child: Row(
                  children: [
                    const Icon(Icons.my_location, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(l10n.locationSettings),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    const Icon(Icons.refresh, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(l10n.retry),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer4<ChildProvider, LocationProvider, AlertProvider,
          GeofenceProvider>(
        builder: (context, childProvider, locationProvider, alertProvider,
            geofenceProvider, child) {
          if (childProvider.isLoading || locationProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final childModel = childProvider.selectedChild;
          final location = locationProvider.liveLocation;
          final canRenderLiveMap = location != null;

          if (location != null) {
            _maybeFocusLiveLocation(location);
          }

          if (childModel == null) {
            return Center(child: Text(l10n.noData));
          }

          return RefreshIndicator(
            onRefresh: _loadData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Google Map
                  Container(
                    height: 300,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey[200],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        if (canRenderLiveMap)
                          GoogleMap(
                            onMapCreated: _onMapCreated,
                            initialCameraPosition: CameraPosition(
                              target: _getInitialPosition(),
                              zoom: AppConstants.defaultZoom,
                            ),
                            markers: _markers,
                            circles: _circles,
                            myLocationEnabled: false,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            mapToolbarEnabled: false,
                          )
                        else
                          _buildUnavailableMapState(),
                        if (locationProvider.isTracking)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.gps_fixed,
                                      size: 16, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text(
                                    l10n.online,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_isLoadingParentLocation)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    l10n.loading,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.child_care,
                                        size: 14,
                                        color: AppColors.primaryColor),
                                    const SizedBox(width: 4),
                                    Text(l10n.child,
                                        style: const TextStyle(fontSize: 10)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.person,
                                        size: 14,
                                        color: AppColors.successColor),
                                    const SizedBox(width: 4),
                                    Text(l10n.myLocation,
                                        style: const TextStyle(fontSize: 10)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Quick Actions
                  Row(
                    children: [
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.history,
                          label: l10n.locationHistory,
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              '/location-history',
                              arguments: {
                                'childId': widget.childId,
                                'childName': childModel.name,
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.notifications,
                          label: l10n.alerts,
                          onTap: () {
                            Navigator.pushNamed(context, '/alerts',
                                arguments: widget.childId);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.location_on,
                          label: l10n.safeZones,
                          onTap: () {
                            Navigator.pushNamed(context, '/safe-zones',
                                arguments: widget.childId);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Child Info Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.children,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _InfoRow(label: l10n.name, value: childModel.name),
                          _InfoRow(
                              label: l10n.childAge,
                              value: '${childModel.age} ${l10n.yearsOld}'),
                          _InfoRow(
                            label: l10n.status,
                            value: localizeStatusLabel(l10n, childModel.status),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Device Info Card
                  if (childModel.device != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.deviceId,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _InfoRow(
                                label: l10n.status,
                                value: localizeStatusLabel(
                                  l10n,
                                  childModel.device!.status,
                                )),
                            _InfoRow(
                                label: l10n.battery,
                                value: '${childModel.device!.batteryLevel}%'),
                            _InfoRow(
                                label: l10n.deviceId,
                                value: childModel.device!.imei),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Location Info Card
                  if (location != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.locationHistory,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _InfoRow(
                                label: l10n.latitude,
                                value: location.latitude.toStringAsFixed(6)),
                            _InfoRow(
                                label: l10n.longitude,
                                value: location.longitude.toStringAsFixed(6)),
                            _InfoRow(
                                label: l10n.battery,
                                value: '${location.battery}%'),
                            _InfoRow(
                              label: l10n.lastSeen,
                              value: _formatTimestamp(location.recordedAt),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Safe Zones Summary
                  if (geofenceProvider.safeZones.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.safeZones,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ...geofenceProvider.safeZones
                                .take(3)
                                .map((zone) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.location_on,
                                              color: AppColors.successColor,
                                              size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              zone.name,
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                          ),
                                          Text(
                                            '${zone.radius} ${l10n.metersShort}',
                                            style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    )),
                            if (geofenceProvider.safeZones.length > 3)
                              TextButton(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/safe-zones',
                                      arguments: widget.childId);
                                },
                                child: Text(
                                    '${l10n.safeZones} (${geofenceProvider.safeZones.length})'),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primaryColor, size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[600]),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
