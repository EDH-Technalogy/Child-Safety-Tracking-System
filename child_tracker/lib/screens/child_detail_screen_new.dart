import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/child_provider.dart';
import '../providers/location_provider.dart';
import '../providers/alert_provider.dart';
import '../providers/geofence_provider.dart';
import '../utils/constants.dart';
import '../utils/timestamp_utils.dart';

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
  LatLng? _lastChildLocation;
  bool _isMapExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _getParentLocation();
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
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);
    final location = locationProvider.liveLocation;

    Set<Marker> markers = {};
    Set<Circle> circles = {};

    // Add child marker with animation
    if (location != null) {
      // Animate to new location if there's a previous location
      if (_lastChildLocation != null && _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(location.latitude, location.longitude),
          ),
        );
      }
      _lastChildLocation = LatLng(location.latitude, location.longitude);

      markers.add(
        Marker(
          markerId: const MarkerId('child'),
          position: LatLng(location.latitude, location.longitude),
          infoWindow: const InfoWindow(
            title: 'Child Location',
            snippet: 'Live tracking',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    // Add parent marker
    if (_parentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('parent'),
          position:
              LatLng(_parentLocation!.latitude, _parentLocation!.longitude),
          infoWindow: const InfoWindow(
            title: 'Your Location',
            snippet: 'Parent/Guardian',
          ),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }

    // Add safe zone circles with enhanced styling
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

  Widget _buildUnavailableMapState() {
    return Container(
      color: Colors.grey[100],
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.location_off,
            size: 44,
            color: AppColors.textSecondary,
          ),
          SizedBox(height: 12),
          Text(
            'No live location available for this child',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'The map will appear when the linked device sends valid GPS data.',
            textAlign: TextAlign.center,
            style: TextStyle(
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

  void _toggleMapExpanded() {
    setState(() {
      _isMapExpanded = !_isMapExpanded;
    });
  }

  void _showFullScreenMap() {
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);
    final location = locationProvider.liveLocation;

    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No live location available for this child'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenMapView(
          childId: widget.childId,
          childName: Provider.of<ChildProvider>(context, listen: false)
                  .selectedChild
                  ?.name ??
              'Child',
          initialPosition: LatLng(location.latitude, location.longitude),
          markers: _markers,
          circles: _circles,
          isTracking: locationProvider.isTracking,
          safeZones: geofenceProvider.safeZones,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<ChildProvider>(
          builder: (context, childProvider, child) {
            return Text(childProvider.selectedChild?.name ?? 'Child Details');
          },
        ),
        actions: [
          Consumer<AlertProvider>(
            builder: (context, alertProvider, child) {
              final unreadCount =
                  alertProvider.unreadCountForChild(widget.childId);
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications),
                    onPressed: () {
                      Navigator.pushNamed(context, '/alerts',
                          arguments: widget.childId);
                    },
                  ),
                  if (unreadCount > 0)
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
                          '$unreadCount',
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
                case 'fullscreen_map':
                  _showFullScreenMap();
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
              const PopupMenuItem(
                value: 'activity',
                child: Row(
                  children: [
                    Icon(Icons.analytics, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Activity & Summary'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    Icon(Icons.history, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Location History'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'safe_zones',
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Safe Zones'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'fullscreen_map',
                child: Row(
                  children: [
                    Icon(Icons.fullscreen, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Full Screen Map'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'my_location',
                child: Row(
                  children: [
                    Icon(Icons.my_location, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('My Location'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Refresh'),
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

          if (childModel == null) {
            return const Center(child: Text('Child not found'));
          }

          return RefreshIndicator(
            onRefresh: _loadData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Google Map with expand/collapse
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: _isMapExpanded
                        ? MediaQuery.of(context).size.height - 100
                        : 300,
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
                        // Fullscreen toggle button
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              onTap: _toggleMapExpanded,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  _isMapExpanded
                                      ? Icons.fullscreen_exit
                                      : Icons.fullscreen,
                                  size: 20,
                                  color: AppColors.primaryColor,
                                ),
                              ),
                            ),
                          ),
                        ),
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
                              child: const Row(
                                children: [
                                  Icon(Icons.gps_fixed,
                                      size: 16, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'LIVE',
                                    style: TextStyle(
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
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Getting your location...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Safe zone legend
                        if (geofenceProvider.safeZones.isNotEmpty)
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
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: AppColors.successColor
                                              .withValues(alpha: 0.3),
                                          border: Border.all(
                                              color: AppColors.successColor),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Active Zone (${geofenceProvider.safeZones.where((z) => z.status == 'active').length})',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.grey
                                              .withValues(alpha: 0.2),
                                          border:
                                              Border.all(color: Colors.grey),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Inactive Zone (${geofenceProvider.safeZones.where((z) => z.status != 'active').length})',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 8,
                          right: 8,
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
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.child_care,
                                        size: 14,
                                        color: AppColors.primaryColor),
                                    SizedBox(width: 4),
                                    Text('Child',
                                        style: TextStyle(fontSize: 10)),
                                  ],
                                ),
                                SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.person,
                                        size: 14,
                                        color: AppColors.successColor),
                                    SizedBox(width: 4),
                                    Text('You', style: TextStyle(fontSize: 10)),
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
                          label: 'History',
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
                          label: 'Alerts',
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
                          label: 'Zones',
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
                          const Text(
                            'Child Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _InfoRow(label: 'Name', value: childModel.name),
                          _InfoRow(
                              label: 'Age', value: '${childModel.age} years'),
                          _InfoRow(label: 'Status', value: childModel.status),
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
                            const Text(
                              'Device Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _InfoRow(
                                label: 'Status',
                                value: childModel.device!.status),
                            _InfoRow(
                                label: 'Battery',
                                value: '${childModel.device!.batteryLevel}%'),
                            _InfoRow(
                                label: 'IMEI', value: childModel.device!.imei),
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
                            const Text(
                              'Last Known Location',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _InfoRow(
                                label: 'Latitude',
                                value: location.latitude.toStringAsFixed(6)),
                            _InfoRow(
                                label: 'Longitude',
                                value: location.longitude.toStringAsFixed(6)),
                            _InfoRow(
                                label: 'Speed',
                                value:
                                    '${location.speed.toStringAsFixed(2)} km/h'),
                            _InfoRow(
                                label: 'Battery',
                                value: '${location.battery}%'),
                            _InfoRow(
                              label: 'Last Update',
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
                            const Text(
                              'Safe Zones',
                              style: TextStyle(
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
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: zone.status == 'active'
                                                  ? AppColors.successColor
                                                  : Colors.grey,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
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
                                            '${zone.radius}m',
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
                                    'View all (${geofenceProvider.safeZones.length})'),
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
    final date = TimestampUtils.toLocalDateTime(timestamp);
    if (date == null) {
      return '--';
    }

    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// Full Screen Map View Widget
class FullScreenMapView extends StatefulWidget {
  final String childId;
  final String childName;
  final LatLng initialPosition;
  final Set<Marker> markers;
  final Set<Circle> circles;
  final bool isTracking;
  final List<dynamic> safeZones;

  const FullScreenMapView({
    super.key,
    required this.childId,
    required this.childName,
    required this.initialPosition,
    required this.markers,
    required this.circles,
    required this.isTracking,
    required this.safeZones,
  });

  @override
  State<FullScreenMapView> createState() => _FullScreenMapViewState();
}

class _FullScreenMapViewState extends State<FullScreenMapView> {
  late GoogleMapController _mapController;
  late Set<Marker> _markers;
  late Set<Circle> _circles;
  bool _showLegend = true;

  @override
  void initState() {
    super.initState();
    _markers = Set.from(widget.markers);
    _circles = Set.from(widget.circles);
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _toggleLegend() {
    setState(() {
      _showLegend = !_showLegend;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName} - Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: _toggleLegend,
            tooltip: 'Toggle legend',
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () async {
              try {
                LocationPermission permission =
                    await Geolocator.checkPermission();
                if (permission == LocationPermission.denied) {
                  permission = await Geolocator.requestPermission();
                }
                if (permission == LocationPermission.whileInUse ||
                    permission == LocationPermission.always) {
                  final position = await Geolocator.getCurrentPosition();
                  _mapController.animateCamera(
                    CameraUpdate.newLatLng(
                      LatLng(position.latitude, position.longitude),
                    ),
                  );
                }
              } catch (e) {
                // Handle error
              }
            },
            tooltip: 'My location',
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: widget.initialPosition,
              zoom: 16,
            ),
            markers: _markers,
            circles: _circles,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            mapToolbarEnabled: true,
          ),
          if (_showLegend && widget.safeZones.isNotEmpty)
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
                          const Icon(Icons.location_on,
                              color: AppColors.primaryColor, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${widget.childName}\'s Location',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color:
                                  AppColors.successColor.withValues(alpha: 0.3),
                              border: Border.all(color: AppColors.successColor),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Active Safe Zone (${widget.safeZones.where((z) => z.status == 'active').length})',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.2),
                              border: Border.all(color: Colors.grey),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Inactive Safe Zone (${widget.safeZones.where((z) => z.status != 'active').length})',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.isTracking)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.gps_fixed, size: 16, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'LIVE TRACKING',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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
