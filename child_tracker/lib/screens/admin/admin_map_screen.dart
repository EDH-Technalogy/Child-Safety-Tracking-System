import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/location_model.dart';
import '../../providers/alert_provider.dart';
import '../../providers/child_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/geofence_provider.dart';
import '../../services/admin_api_service.dart';
import '../../utils/constants.dart';
import '../../utils/localization_helpers.dart';
import '../../widgets/google_map_guard.dart';
import '../../widgets/admin_drawer.dart';
import '../../widgets/hover_icon_button.dart';

class AdminMapScreen extends StatefulWidget {
  final String? childId;

  const AdminMapScreen({super.key, this.childId});

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  final AdminApiService _adminApi = AdminApiService();
  GoogleMapController? _mapController;
  Position? _currentPosition;
  String? _activeChildId;
  bool _isLoading = true;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  bool _showLiveTracking = true;
  bool _showSafeZones = true;
  bool _showChildLocation = true;
  double _defaultZoom = 16.0;
  LocationProvider? _locationProvider;
  GeofenceProvider? _geofenceProvider;
  LatLng? _lastFocusedTarget;
  String? _alertMonitorOwnerId;
  String? _hoveredActionKey;

  @override
  void initState() {
    super.initState();
    _initializeMap();
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

  Future<void> _initializeMap() async {
    await _getCurrentLocation();
    _activeChildId = await _resolveInitialChildId();
    if (_activeChildId != null) {
      await _loadChildData();
    }
    if (!mounted) {
      return;
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
    final childId = _activeChildId;
    if (childId == null) return;

    final childProvider = Provider.of<ChildProvider>(context, listen: false);
    final alertProvider = Provider.of<AlertProvider>(context, listen: false);
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);

    final didLoadChild = await childProvider.getChildWithDevice(childId);
    if (!didLoadChild) {
      return;
    }

    await locationProvider.getLiveLocation(childId);
    final nextOwnerId = 'admin_map:$childId';
    if (_alertMonitorOwnerId != null && _alertMonitorOwnerId != nextOwnerId) {
      alertProvider.stopMonitoring(ownerId: _alertMonitorOwnerId!);
    }
    _alertMonitorOwnerId = nextOwnerId;
    await alertProvider.startMonitoring(
      childId,
      ownerId: nextOwnerId,
    );
    await geofenceProvider.loadSafeZones(childId);

    locationProvider.startLiveTracking(childId);
    _updateMarkers();
  }

  Future<String?> _resolveInitialChildId() async {
    if (widget.childId != null && widget.childId!.trim().isNotEmpty) {
      return widget.childId!.trim();
    }

    final childProvider = Provider.of<ChildProvider>(context, listen: false);
    final selectedChildId = childProvider.selectedChild?.id.trim() ?? '';
    if (selectedChildId.isNotEmpty) {
      return selectedChildId;
    }

    if (childProvider.children.isNotEmpty) {
      final firstChildId = childProvider.children.first.id.trim();
      if (firstChildId.isNotEmpty) {
        return firstChildId;
      }
    }

    try {
      final children = await _adminApi.getAllChildren();
      for (final entry in children) {
        if (entry is! Map) {
          continue;
        }

        final child = Map<String, dynamic>.from(entry);
        final childId =
            (child['id'] ?? child['child_id'] ?? '').toString().trim();
        if (childId.isNotEmpty) {
          return childId;
        }
      }
    } catch (_) {
      // Fall back to the empty-state UI when admin child lookup is unavailable.
    }

    return null;
  }

  void _updateMarkers() {
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);
    final location = locationProvider.liveLocation;
    final shouldShowOnlyTrackedMarker =
        location != null || _activeChildId != null;

    Set<Marker> markers = {};
    Set<Circle> circles = {};

    if (_showChildLocation && location != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('child'),
          position: LatLng(location.latitude, location.longitude),
          infoWindow: InfoWindow(
            title: context.l10n.childLocation,
            snippet: context.l10n.liveTracking,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    if (!shouldShowOnlyTrackedMarker && _currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current'),
          position:
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          infoWindow: InfoWindow(
            title: context.l10n.myLocation,
            snippet: context.l10n.currentPosition,
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

    if (_activeChildId == null && _currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }

    return const LatLng(0, 0);
  }

  void _maybeFocusLiveLocation(LocationModel? location) {
    if (_mapController == null || location == null) {
      return;
    }

    if (_locationProvider?.isAnimatingLiveLocation == true) {
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

  bool _shouldRenderMap(LocationModel? location) {
    if (_activeChildId != null) {
      return location != null;
    }

    return _currentPosition != null;
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

  void _showMapSettings() {
    final l10n = context.l10n;
    final mediaQuery = MediaQuery.of(context);
    final maxSheetHeight = mediaQuery.size.height * 0.85;
    final bottomPadding = mediaQuery.viewPadding.bottom + 24;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: maxSheetHeight,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.mapSettings,
                  style: TextStyle(
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
                    if (value && _activeChildId != null) {
                      final locationProvider =
                          Provider.of<LocationProvider>(context, listen: false);
                      locationProvider.startLiveTracking(_activeChildId!);
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
                  style: TextStyle(
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
                    child: Text(l10n.done),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final liveLocation = _locationProvider?.liveLocation;
    final canRenderMap = _shouldRenderMap(liveLocation);
    if (liveLocation != null) {
      _maybeFocusLiveLocation(liveLocation);
    }
    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: Text(l10n.mapView),
        backgroundColor: AppColors.primaryColor,
        actions: [
          HoverIconButton(
            icon: Icons.tune_rounded,
            isHovered: _hoveredActionKey == 'settings',
            isDimmed:
                _hoveredActionKey != null && _hoveredActionKey != 'settings',
            onHoverChanged: (value) {
              setState(() {
                if (value) {
                  _hoveredActionKey = 'settings';
                } else if (_hoveredActionKey == 'settings') {
                  _hoveredActionKey = null;
                }
              });
            },
            onPressed: _showMapSettings,
            tooltip: l10n.mapSettings,
          ),
          HoverIconButton(
            icon: Icons.gps_fixed_rounded,
            isHovered: _hoveredActionKey == 'my_location',
            isDimmed:
                _hoveredActionKey != null && _hoveredActionKey != 'my_location',
            onHoverChanged: (value) {
              setState(() {
                if (value) {
                  _hoveredActionKey = 'my_location';
                } else if (_hoveredActionKey == 'my_location') {
                  _hoveredActionKey = null;
                }
              });
            },
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
            tooltip: l10n.myLocation,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                if (canRenderMap)
                  GoogleMapAvailabilityGuard(
                    mapBuilder: (_) => GoogleMap(
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
                    fallbackBuilder: (_) => const GoogleMapUnavailableState(
                      title: 'Map unavailable',
                      message:
                          'Google Maps is not ready in this browser right now. Check the web Maps script and API key configuration.',
                    ),
                  )
                else
                  _buildUnavailableMapState(),
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
                              Text(l10n.child, style: TextStyle(fontSize: 12)),
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
                              Text(l10n.you,
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
                                Text(l10n.safeZone,
                                    style: TextStyle(fontSize: 12)),
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
                    child: const Icon(
                      Icons.layers_rounded,
                      color: AppColors.primaryColor,
                    ),
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
        child: const Icon(Icons.gps_fixed_rounded),
      ),
    );
  }

  @override
  void dispose() {
    _locationProvider?.removeListener(_handleMapDataChanged);
    _geofenceProvider?.removeListener(_handleMapDataChanged);
    if (_alertMonitorOwnerId != null) {
      Provider.of<AlertProvider>(context, listen: false)
          .stopMonitoring(ownerId: _alertMonitorOwnerId!);
    }
    Provider.of<LocationProvider>(context, listen: false).stopLiveTracking();
    _mapController?.dispose();
    super.dispose();
  }
}
