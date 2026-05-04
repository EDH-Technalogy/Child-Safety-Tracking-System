import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/child_model.dart';
import '../models/location_model.dart';
import '../providers/alert_provider.dart';
import '../providers/child_provider.dart';
import '../providers/geofence_provider.dart';
import '../providers/location_provider.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';
import '../utils/timestamp_utils.dart';
import '../widgets/google_map_guard.dart';
import '../widgets/app_drawer.dart';
import '../widgets/hover_icon_button.dart';

class MapScreen extends StatefulWidget {
  final String? childId;

  const MapScreen({super.key, this.childId});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  LatLng? _lastFocusedTarget;
  String? _activeChildId;
  bool _isLoading = true;
  bool _showLiveTracking = true;
  bool _showSafeZones = true;
  bool _showChildLocation = true;
  double _defaultZoom = 16.0;
  MapType _mapType = MapType.normal;
  String? _alertMonitorOwnerId;
  String? _hoveredActionKey;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    await _getCurrentLocation();
    _activeChildId = _resolveInitialChildId();
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

      if (!mounted) {
        return;
      }

      setState(() {
        _currentPosition = position;
      });
    } catch (_) {
      // Keep the map usable even when current location is unavailable.
    }
  }

  Future<void> _loadChildData() async {
    final childId = _activeChildId;
    if (childId == null) {
      return;
    }

    final childProvider = Provider.of<ChildProvider>(context, listen: false);
    final alertProvider = Provider.of<AlertProvider>(context, listen: false);
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);

    await childProvider.getChildWithDevice(childId);
    await locationProvider.getLiveLocation(childId);
    await geofenceProvider.loadSafeZones(childId);

    final nextOwnerId = 'map_screen:$childId';
    if (_alertMonitorOwnerId != null && _alertMonitorOwnerId != nextOwnerId) {
      alertProvider.stopMonitoring(ownerId: _alertMonitorOwnerId!);
    }
    _alertMonitorOwnerId = nextOwnerId;
    await alertProvider.startMonitoring(
      childId,
      ownerId: nextOwnerId,
    );

    locationProvider.startLiveTracking(childId);
  }

  String? _resolveInitialChildId() {
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

    return null;
  }

  Set<Marker> _buildMarkers({
    required LocationModel? activeLocation,
    required GeofenceProvider geofenceProvider,
  }) {
    final l10n = context.l10n;
    final markers = <Marker>{};

    if (_showLiveTracking && _showChildLocation && activeLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('child'),
          position: LatLng(activeLocation.latitude, activeLocation.longitude),
          infoWindow: InfoWindow(
            title: _activeChild?.name.isNotEmpty == true
                ? _activeChild!.name
                : l10n.childLocation,
            snippet: l10n.liveTracking,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    if (_showSafeZones) {
      for (final zone in geofenceProvider.safeZones) {
        markers.add(
          Marker(
            markerId: MarkerId('safe_zone_center_${zone.id}'),
            position: LatLng(zone.latitude, zone.longitude),
            infoWindow: InfoWindow(
              title: zone.name.isNotEmpty ? zone.name : l10n.safeZoneCenter,
              snippet: '${l10n.radius}: ${zone.radius} m',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen),
          ),
        );
      }
    }

    return markers;
  }

  Set<Circle> _buildCircles({
    required GeofenceProvider geofenceProvider,
  }) {
    if (!_showSafeZones) {
      return const <Circle>{};
    }

    return geofenceProvider.safeZones.map((zone) {
      final isActive = zone.status == 'active';
      final color = isActive ? AppColors.successColor : Colors.grey;

      return Circle(
        circleId: CircleId(zone.id),
        center: LatLng(zone.latitude, zone.longitude),
        radius: zone.radius.toDouble(),
        fillColor: color.withValues(alpha: isActive ? 0.16 : 0.08),
        strokeColor: color,
        strokeWidth: isActive ? 2 : 1,
      );
    }).toSet();
  }

  LatLng _getInitialPosition(
    LocationModel? activeLocation,
    GeofenceProvider geofenceProvider,
  ) {
    if (activeLocation != null) {
      return LatLng(activeLocation.latitude, activeLocation.longitude);
    }

    if (geofenceProvider.safeZones.isNotEmpty) {
      final zone = geofenceProvider.safeZones.first;
      return LatLng(zone.latitude, zone.longitude);
    }

    if (_currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }

    return const LatLng(0, 0);
  }

  bool _shouldRenderMap({
    required LocationModel? activeLocation,
    required GeofenceProvider geofenceProvider,
  }) {
    if (_activeChildId == null) {
      return false;
    }

    return activeLocation != null || geofenceProvider.safeZones.isNotEmpty;
  }

  Widget _buildUnavailableMapState({
    required String title,
    required String message,
    bool showAddChildAction = false,
  }) {
    final l10n = context.l10n;
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
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
          if (showAddChildAction) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, '/add-child');
              },
              icon: const Icon(Icons.add),
              label: Text(l10n.addChild),
            ),
          ],
        ],
      ),
    );
  }

  void _maybeFocusTrackedLocation(
    LocationModel? activeLocation,
    GeofenceProvider geofenceProvider,
  ) {
    if (_mapController == null) {
      return;
    }

    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    if (locationProvider.isAnimatingLiveLocation) {
      return;
    }

    final nextTarget = activeLocation != null
        ? LatLng(activeLocation.latitude, activeLocation.longitude)
        : geofenceProvider.safeZones.isNotEmpty
            ? LatLng(
                geofenceProvider.safeZones.first.latitude,
                geofenceProvider.safeZones.first.longitude,
              )
            : null;
    if (nextTarget == null) {
      return;
    }

    if (_lastFocusedTarget?.latitude == nextTarget.latitude &&
        _lastFocusedTarget?.longitude == nextTarget.longitude) {
      return;
    }

    _lastFocusedTarget = nextTarget;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _mapController == null) {
        return;
      }

      _mapController!.animateCamera(
        CameraUpdate.newLatLng(nextTarget),
      );
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  String _mapTypeLabel(MapType mapType) {
    switch (mapType) {
      case MapType.satellite:
        return 'Satellite';
      case MapType.terrain:
        return 'Terrain';
      case MapType.normal:
      default:
        return 'Normal';
    }
  }

  Widget _buildMapTypeChip(MapType mapType) {
    return ChoiceChip(
      label: Text(_mapTypeLabel(mapType)),
      selected: _mapType == mapType,
      onSelected: (_) {
        setState(() {
          _mapType = mapType;
        });
      },
    );
  }

  void _showMapSettings() {
    final l10n = AppLocalizations.of(context)!;
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
                  l10n.settings,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Map mode',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildMapTypeChip(MapType.normal),
                    _buildMapTypeChip(MapType.satellite),
                    _buildMapTypeChip(MapType.terrain),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: Text(l10n.liveTracking),
                  subtitle: Text(l10n.showChildLocation),
                  value: _showLiveTracking,
                  activeThumbColor: AppColors.primaryColor,
                  onChanged: (value) {
                    setState(() {
                      _showLiveTracking = value;
                    });
                  },
                ),
                SwitchListTile(
                  title: Text(l10n.safeZones),
                  subtitle: Text(l10n.showSafeZones),
                  value: _showSafeZones,
                  activeThumbColor: AppColors.primaryColor,
                  onChanged: (value) {
                    setState(() {
                      _showSafeZones = value;
                    });
                  },
                ),
                SwitchListTile(
                  title: Text(l10n.childLocation),
                  subtitle: Text(l10n.showChildMarker),
                  value: _showChildLocation,
                  activeThumbColor: AppColors.primaryColor,
                  onChanged: (value) {
                    setState(() {
                      _showChildLocation = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.defaultZoomLevel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
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
                const SizedBox(height: 12),
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
        ),
      ),
    );
  }

  Widget _buildLegendCard() {
    final l10n = context.l10n;
    return Card(
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
                Text(l10n.child, style: const TextStyle(fontSize: 12)),
              ],
            ),
            if (_showSafeZones) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppColors.successColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.safeZoneCenter,
                    style: const TextStyle(fontSize: 12),
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
                      color: AppColors.successColor.withValues(alpha: 0.16),
                      border: Border.all(color: AppColors.successColor),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.safeZones, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChildSummaryCard({
    required ChildModel? child,
    required LocationModel? activeLocation,
    required GeofenceProvider geofenceProvider,
  }) {
    final l10n = context.l10n;
    final device = child?.device;
    final deviceStatus = localizeStatusLabel(
      l10n,
      device?.status ?? 'no_data',
    );
    final lastSeen = activeLocation != null && activeLocation.recordedAt > 0
        ? _formatTimestamp(activeLocation.recordedAt)
        : device != null && device.latestTimestamp > 0
            ? _formatTimestamp(device.latestTimestamp)
            : l10n.noData;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              child?.name.isNotEmpty == true ? child!.name : l10n.child,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            _buildLabelValueRow(
              l10n.status,
              deviceStatus,
            ),
            _buildLabelValueRow(
              l10n.lastSeen,
              lastSeen,
            ),
            _buildLabelValueRow(
              l10n.safeZones,
              '${geofenceProvider.safeZones.length}',
            ),
            if (activeLocation != null)
              _buildLabelValueRow(
                l10n.battery,
                '${activeLocation.battery}%',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabelValueRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = TimestampUtils.toLocalDateTime(timestamp);
    if (date == null) {
      return '--';
    }

    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year} ${date.hour}:$minute';
  }

  ChildModel? get _activeChild {
    final childProvider = Provider.of<ChildProvider>(context, listen: false);
    final activeChildId = _activeChildId;
    if (activeChildId == null || activeChildId.isEmpty) {
      return childProvider.selectedChild;
    }

    for (final child in childProvider.children) {
      if (child.id == activeChildId) {
        return child;
      }
    }

    return childProvider.selectedChild;
  }

  @override
  void dispose() {
    if (_alertMonitorOwnerId != null) {
      Provider.of<AlertProvider>(
        context,
        listen: false,
      ).stopMonitoring(
        ownerId: _alertMonitorOwnerId!,
      );
    }
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(l10n.map),
        leading: Builder(
          builder: (context) => HoverIconButton(
            icon: Icons.menu_rounded,
            isHovered: _hoveredActionKey == 'menu',
            isDimmed: _hoveredActionKey != null && _hoveredActionKey != 'menu',
            onHoverChanged: (value) {
              setState(() {
                if (value) {
                  _hoveredActionKey = 'menu';
                } else if (_hoveredActionKey == 'menu') {
                  _hoveredActionKey = null;
                }
              });
            },
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
            tooltip: l10n.menu,
          ),
        ),
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
            tooltip: l10n.settings,
          ),
          HoverIconButton(
            icon: Icons.person_add_alt_1_rounded,
            isHovered: _hoveredActionKey == 'add_child',
            isDimmed:
                _hoveredActionKey != null && _hoveredActionKey != 'add_child',
            onHoverChanged: (value) {
              setState(() {
                if (value) {
                  _hoveredActionKey = 'add_child';
                } else if (_hoveredActionKey == 'add_child') {
                  _hoveredActionKey = null;
                }
              });
            },
            onPressed: () {
              Navigator.pushNamed(context, '/add-child');
            },
            tooltip: l10n.addChild,
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
                    LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    ),
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
          : Consumer3<ChildProvider, LocationProvider, GeofenceProvider>(
              builder: (
                context,
                childProvider,
                locationProvider,
                geofenceProvider,
                child,
              ) {
                final activeLocation = locationProvider.liveLocation;
                final activeChild = _activeChildId == null
                    ? childProvider.selectedChild
                    : childProvider.children.cast<ChildModel?>().firstWhere(
                          (child) => child?.id == _activeChildId,
                          orElse: () => childProvider.selectedChild,
                        );
                final markers = _buildMarkers(
                  activeLocation: activeLocation,
                  geofenceProvider: geofenceProvider,
                );
                final circles = _buildCircles(
                  geofenceProvider: geofenceProvider,
                );

                if (_activeChildId != null) {
                  _maybeFocusTrackedLocation(activeLocation, geofenceProvider);
                }

                final canRenderMap = _shouldRenderMap(
                  activeLocation: activeLocation,
                  geofenceProvider: geofenceProvider,
                );

                final noChildSelected = _activeChildId == null;
                final unavailableTitle = noChildSelected
                    ? l10n.noData
                    : activeLocation == null &&
                            geofenceProvider.safeZones.isEmpty
                        ? 'No live location or safe zone available'
                        : 'Map unavailable';
                final unavailableMessage = noChildSelected
                    ? 'Add a child to start live tracking and safe zone monitoring.'
                    : activeLocation == null &&
                            geofenceProvider.safeZones.isEmpty
                        ? 'The map will appear once the child sends live data or a safe zone is saved.'
                        : 'The child map is temporarily unavailable.';

                return Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          if (canRenderMap)
                            GoogleMapAvailabilityGuard(
                              mapBuilder: (_) => GoogleMap(
                                onMapCreated: _onMapCreated,
                                initialCameraPosition: CameraPosition(
                                  target: _getInitialPosition(
                                    activeLocation,
                                    geofenceProvider,
                                  ),
                                  zoom: _defaultZoom,
                                ),
                                mapType: _mapType,
                                markers: markers,
                                circles: circles,
                                myLocationEnabled: true,
                                myLocationButtonEnabled: false,
                                zoomControlsEnabled: false,
                                mapToolbarEnabled: false,
                                compassEnabled: true,
                                buildingsEnabled: true,
                              ),
                              fallbackBuilder: (_) => _buildUnavailableMapState(
                                title: 'Map unavailable',
                                message:
                                    'Google Maps is not ready in this browser right now. Check the web Maps script and API key configuration.',
                              ),
                            )
                          else
                            _buildUnavailableMapState(
                              title: unavailableTitle,
                              message: unavailableMessage,
                              showAddChildAction: noChildSelected,
                            ),
                          Positioned(
                            bottom: 16,
                            left: 16,
                            right: 16,
                            child: activeChild == null
                                ? _buildLegendCard()
                                : _buildChildSummaryCard(
                                    child: activeChild,
                                    activeLocation: activeLocation,
                                    geofenceProvider: geofenceProvider,
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
                    ),
                  ],
                );
              },
            ),
    );
  }
}
