import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/location_model.dart';
import '../providers/child_provider.dart';
import '../providers/device_live_tracking_provider.dart';
import '../providers/geofence_provider.dart';
import '../providers/location_provider.dart';
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
  final TextEditingController _deviceIdController = TextEditingController();
  Position? _currentPosition;
  LatLng? _lastFocusedTarget;
  String? _activeChildId;
  bool _isLoading = true;
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
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);

    await childProvider.getChildWithDevice(childId);
    await locationProvider.getLiveLocation(childId);
    await geofenceProvider.loadSafeZones(childId);

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

  Future<void> _submitDeviceLookup() async {
    final trackingProvider = Provider.of<DeviceLiveTrackingProvider>(
      context,
      listen: false,
    );

    FocusScope.of(context).unfocus();
    final success = await trackingProvider.trackDeviceById(
      _deviceIdController.text,
    );

    if (!mounted || success) {
      return;
    }

    if (trackingProvider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.l10n.error}: ${trackingProvider.error!}'),
        ),
      );
    }
  }

  Future<void> _resetDeviceLookup() async {
    _deviceIdController.clear();
    FocusScope.of(context).unfocus();

    await Provider.of<DeviceLiveTrackingProvider>(
      context,
      listen: false,
    ).clearTracking();

    if (mounted) {
      setState(() {});
    }
  }

  LocationModel? _resolveActiveLocation({
    required LocationProvider locationProvider,
    required DeviceLiveTrackingProvider trackingProvider,
  }) {
    if (trackingProvider.hasSelection) {
      return trackingProvider.liveLocation;
    }

    return locationProvider.liveLocation;
  }

  Set<Marker> _buildMarkers({
    required LocationModel? activeLocation,
    required DeviceLiveTrackingProvider trackingProvider,
  }) {
    final l10n = context.l10n;
    final markers = <Marker>{};
    final shouldShowOnlyTrackedMarker = activeLocation != null ||
        trackingProvider.hasSelection ||
        _activeChildId != null;

    if (_showLiveTracking && _showChildLocation && activeLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('child'),
          position: LatLng(activeLocation.latitude, activeLocation.longitude),
          infoWindow: InfoWindow(
            title: trackingProvider.child?.name.isNotEmpty == true
                ? trackingProvider.child!.name
                : l10n.childLocation,
            snippet: l10n.liveTracking,
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
            title: l10n.myLocation,
            snippet: l10n.currentPosition,
          ),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }

    return markers;
  }

  Set<Circle> _buildCircles({
    required GeofenceProvider geofenceProvider,
    required DeviceLiveTrackingProvider trackingProvider,
  }) {
    if (!_showSafeZones || trackingProvider.hasSelection) {
      return const <Circle>{};
    }

    return geofenceProvider.safeZones.map((zone) {
      final isActive = zone.status == 'active';
      final color = isActive ? AppColors.successColor : Colors.grey;

      return Circle(
        circleId: CircleId(zone.id),
        center: LatLng(zone.latitude, zone.longitude),
        radius: zone.radius.toDouble(),
        fillColor: color.withValues(alpha: isActive ? 0.15 : 0.08),
        strokeColor: color,
        strokeWidth: isActive ? 2 : 1,
      );
    }).toSet();
  }

  LatLng _getInitialPosition(LocationModel? activeLocation) {
    if (activeLocation != null) {
      return LatLng(activeLocation.latitude, activeLocation.longitude);
    }

    if (widget.childId == null && _currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }

    return const LatLng(0, 0);
  }

  bool _shouldRenderMap({
    required LocationModel? activeLocation,
    required DeviceLiveTrackingProvider trackingProvider,
  }) {
    if (_activeChildId != null || trackingProvider.hasSelection) {
      return activeLocation != null;
    }

    return _currentPosition != null;
  }

  Widget _buildUnavailableMapState({
    required String title,
    required String message,
  }) {
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
        ],
      ),
    );
  }

  void _maybeFocusTrackedLocation(LocationModel? activeLocation) {
    if (_mapController == null || activeLocation == null) {
      return;
    }

    final nextTarget = LatLng(
      activeLocation.latitude,
      activeLocation.longitude,
    );

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

  Widget _buildDeviceSearchPanel(DeviceLiveTrackingProvider trackingProvider) {
    final l10n = context.l10n;
    final waitingForLiveData = trackingProvider.hasSelection &&
        trackingProvider.liveTracking == null &&
        trackingProvider.isListening &&
        trackingProvider.error == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.liveTracking,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _deviceIdController,
                enabled: !trackingProvider.isLoading,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: l10n.deviceId,
                  prefixIcon: const Icon(Icons.phone_android),
                  suffixIcon: _deviceIdController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _resetDeviceLookup,
                        ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submitDeviceLookup(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: trackingProvider.isLoading
                          ? null
                          : _submitDeviceLookup,
                      icon: trackingProvider.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.search),
                      label: Text(l10n.search),
                    ),
                  ),
                  if (trackingProvider.hasSelection ||
                      trackingProvider.hasSearched ||
                      _deviceIdController.text.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: trackingProvider.isLoading
                          ? null
                          : _resetDeviceLookup,
                      child: Text(l10n.cancel),
                    ),
                  ],
                ],
              ),
              if (trackingProvider.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  trackingProvider.error!,
                  style: const TextStyle(
                    color: AppColors.errorColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else if (waitingForLiveData) ...[
                const SizedBox(height: 12),
                Text(
                  'Connected to the child record. Waiting for live location updates.',
                  style: TextStyle(
                    color: Colors.orange[800],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
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
                Text(l10n.myLocation, style: const TextStyle(fontSize: 12)),
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
                      color: AppColors.successColor.withValues(alpha: 0.3),
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

  Widget _buildTrackingSummaryCard(
      DeviceLiveTrackingProvider trackingProvider) {
    final l10n = context.l10n;
    final liveTracking = trackingProvider.liveTracking;
    final statusValue = liveTracking?.effectiveDeviceStatus ??
        trackingProvider.device?.status ??
        l10n.unknown;
    final batteryValue = liveTracking?.location != null
        ? '${liveTracking!.location!.battery}%'
        : '${trackingProvider.device?.batteryLevel ?? 0}%';
    final latestTimestamp = liveTracking?.latestTimestamp;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trackingProvider.child?.name ?? l10n.child,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            _buildLabelValueRow(
              l10n.deviceId,
              trackingProvider.device?.id ?? l10n.unknown,
            ),
            _buildLabelValueRow(
              l10n.name,
              trackingProvider.child?.name ?? l10n.unknown,
            ),
            _buildLabelValueRow(
              l10n.status,
              localizeStatusLabel(l10n, statusValue),
            ),
            _buildLabelValueRow(
              l10n.battery,
              batteryValue,
            ),
            _buildLabelValueRow(
              l10n.lastSeen,
              latestTimestamp != null
                  ? _formatTimestamp(latestTimestamp)
                  : l10n.noData,
            ),
            if ((liveTracking?.connection?.reason ?? '').isNotEmpty)
              _buildLabelValueRow(
                'Signal',
                liveTracking!.connection!.reason,
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
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year} ${date.hour}:$minute';
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
          : Consumer3<LocationProvider, GeofenceProvider,
              DeviceLiveTrackingProvider>(
              builder: (
                context,
                locationProvider,
                geofenceProvider,
                trackingProvider,
                child,
              ) {
                final activeLocation = _resolveActiveLocation(
                  locationProvider: locationProvider,
                  trackingProvider: trackingProvider,
                );
                final markers = _buildMarkers(
                  activeLocation: activeLocation,
                  trackingProvider: trackingProvider,
                );
                final circles = _buildCircles(
                  geofenceProvider: geofenceProvider,
                  trackingProvider: trackingProvider,
                );

                if ((_activeChildId != null || trackingProvider.hasSelection) &&
                    activeLocation != null) {
                  _maybeFocusTrackedLocation(activeLocation);
                }
                final canRenderMap = _shouldRenderMap(
                  activeLocation: activeLocation,
                  trackingProvider: trackingProvider,
                );
                final unavailableTitle = trackingProvider.hasSelection
                    ? 'No live location available for this device'
                    : _activeChildId != null
                        ? 'No live location available for this child'
                        : 'Location unavailable';
                final unavailableMessage = trackingProvider.hasSelection
                    ? 'The map will appear when this device sends valid GPS data.'
                    : _activeChildId != null
                        ? 'The child map will appear when the linked device sends valid GPS data.'
                        : 'Allow location access to center the map on your current position.';

                return Column(
                  children: [
                    if (_activeChildId == null)
                      _buildDeviceSearchPanel(trackingProvider),
                    Expanded(
                      child: Stack(
                        children: [
                          if (canRenderMap)
                            GoogleMap(
                              onMapCreated: _onMapCreated,
                              initialCameraPosition: CameraPosition(
                                target: _getInitialPosition(activeLocation),
                                zoom: _defaultZoom,
                              ),
                              markers: markers,
                              circles: circles,
                              myLocationEnabled: true,
                              myLocationButtonEnabled: false,
                              zoomControlsEnabled: false,
                              mapToolbarEnabled: false,
                              compassEnabled: true,
                            )
                          else
                            _buildUnavailableMapState(
                              title: unavailableTitle,
                              message: unavailableMessage,
                            ),
                          Positioned(
                            bottom: 16,
                            left: 16,
                            right: 16,
                            child: trackingProvider.hasSelection
                                ? _buildTrackingSummaryCard(trackingProvider)
                                : _buildLegendCard(),
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
                                Icons.layers,
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

  @override
  void dispose() {
    _deviceIdController.dispose();
    Provider.of<LocationProvider>(context, listen: false).stopLiveTracking();
    unawaited(
      Provider.of<DeviceLiveTrackingProvider>(
        context,
        listen: false,
      ).clearTracking(),
    );
    _mapController?.dispose();
    super.dispose();
  }
}
