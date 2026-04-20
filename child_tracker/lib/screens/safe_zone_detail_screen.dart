import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/geofence_model.dart';
import '../models/location_model.dart';
import '../providers/geofence_provider.dart';
import '../providers/location_provider.dart';
import '../utils/constants.dart';

enum _MapViewMode {
  defaultView,
  satellite,
  terrain,
  threeDimensionalLike,
}

class SafeZoneDetailScreen extends StatefulWidget {
  final GeofenceModel zone;

  const SafeZoneDetailScreen({
    super.key,
    required this.zone,
  });

  @override
  State<SafeZoneDetailScreen> createState() => _SafeZoneDetailScreenState();
}

class _SafeZoneDetailScreenState extends State<SafeZoneDetailScreen> {
  static const double _maxAutoFrameDistanceMeters = 1000000;
  GoogleMapController? _mapController;
  bool _ownsLocationTracking = false;
  String? _lastZoneCheckKey;
  String? _lastCameraKey;
  _MapViewMode _mapViewMode = _MapViewMode.satellite;
  double _lastZoom = AppConstants.defaultZoom;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    if (widget.zone.childId.isEmpty) {
      return;
    }

    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);

    await locationProvider.getLiveLocation(widget.zone.childId);

    final shouldOwnTracking = !locationProvider.isTracking ||
        locationProvider.trackingChildId != widget.zone.childId;
    if (shouldOwnTracking) {
      locationProvider.startLiveTracking(widget.zone.childId);
      _ownsLocationTracking = true;
    }

    final liveLocation = locationProvider.liveLocation;
    if (liveLocation != null) {
      await geofenceProvider.checkLocationInZone(
        childId: widget.zone.childId,
        latitude: liveLocation.latitude,
        longitude: liveLocation.longitude,
      );
    }
  }

  @override
  void dispose() {
    if (_ownsLocationTracking) {
      Provider.of<LocationProvider>(context, listen: false).stopLiveTracking();
    }
    _mapController?.dispose();
    super.dispose();
  }

  void _scheduleZoneCheck(LocationModel? liveLocation) {
    if (liveLocation == null || widget.zone.childId.isEmpty) {
      return;
    }

    final nextKey = [
      widget.zone.childId,
      liveLocation.latitude.toStringAsFixed(6),
      liveLocation.longitude.toStringAsFixed(6),
      liveLocation.recordedAt,
    ].join('|');
    if (_lastZoneCheckKey == nextKey) {
      return;
    }

    _lastZoneCheckKey = nextKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      unawaited(
        Provider.of<GeofenceProvider>(context, listen: false)
            .checkLocationInZone(
          childId: widget.zone.childId,
          latitude: liveLocation.latitude,
          longitude: liveLocation.longitude,
        ),
      );
    });
  }

  void _frameMap(LocationModel? liveLocation) {
    if (_mapController == null) {
      return;
    }

    final nextKey = [
      widget.zone.id,
      liveLocation?.latitude.toStringAsFixed(6) ?? '',
      liveLocation?.longitude.toStringAsFixed(6) ?? '',
      widget.zone.radius,
    ].join('|');
    if (_lastCameraKey == nextKey) {
      return;
    }

    _lastCameraKey = nextKey;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _mapController == null) {
        return;
      }

      if (liveLocation != null) {
        final distance = Geolocator.distanceBetween(
          widget.zone.latitude,
          widget.zone.longitude,
          liveLocation.latitude,
          liveLocation.longitude,
        );
        if (distance > _maxAutoFrameDistanceMeters) {
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(liveLocation.latitude, liveLocation.longitude),
                zoom: math.max(_lastZoom, 16.5).toDouble(),
              ),
            ),
          );
          return;
        }
      }

      final bounds = _buildBounds(liveLocation);
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 56),
      );
      if (_mapViewMode == _MapViewMode.threeDimensionalLike) {
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          if (!mounted) {
            return;
          }
          _applyMapPerspective(liveLocation, animate: true);
        });
      }
    });
  }

  MapType get _activeMapType {
    switch (_mapViewMode) {
      case _MapViewMode.defaultView:
        return MapType.normal;
      case _MapViewMode.satellite:
        return MapType.satellite;
      case _MapViewMode.terrain:
        return MapType.terrain;
      case _MapViewMode.threeDimensionalLike:
        return MapType.hybrid;
    }
  }

  String _mapViewLabel(_MapViewMode mode) {
    switch (mode) {
      case _MapViewMode.defaultView:
        return 'Default';
      case _MapViewMode.satellite:
        return 'Satellite';
      case _MapViewMode.terrain:
        return 'Terrain';
      case _MapViewMode.threeDimensionalLike:
        return '3D-like';
    }
  }

  LatLng _resolveFocusTarget(LocationModel? liveLocation) {
    if (liveLocation != null) {
      return LatLng(liveLocation.latitude, liveLocation.longitude);
    }

    return LatLng(widget.zone.latitude, widget.zone.longitude);
  }

  Future<void> _setMapViewMode(
    _MapViewMode nextMode,
    LocationModel? liveLocation,
  ) async {
    if (_mapViewMode == nextMode) {
      return;
    }

    setState(() {
      _mapViewMode = nextMode;
    });

    if (_mapController == null) {
      return;
    }

    if (nextMode == _MapViewMode.threeDimensionalLike) {
      await _applyMapPerspective(liveLocation, animate: true);
      return;
    }

    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _resolveFocusTarget(liveLocation),
          zoom: _lastZoom,
          tilt: 0,
          bearing: 0,
        ),
      ),
    );
  }

  Future<void> _applyMapPerspective(
    LocationModel? liveLocation, {
    required bool animate,
  }) async {
    if (_mapController == null) {
      return;
    }

    final target = _resolveFocusTarget(liveLocation);
    final zoom = math.max(_lastZoom, 17.0).toDouble();
    final cameraUpdate = CameraUpdate.newCameraPosition(
      CameraPosition(
        target: target,
        zoom: zoom,
        tilt: 55,
        bearing: 35,
      ),
    );

    if (animate) {
      await _mapController!.animateCamera(cameraUpdate);
      return;
    }

    await _mapController!.moveCamera(cameraUpdate);
  }

  LatLngBounds _buildBounds(LocationModel? liveLocation) {
    final centerLat = widget.zone.latitude;
    final centerLng = widget.zone.longitude;
    final latPadding = math.max(widget.zone.radius / 111320, 0.0015);
    final cosLatitude = math.cos(centerLat * math.pi / 180).abs();
    final lngPadding = math.max(
      widget.zone.radius / (111320 * (cosLatitude < 0.1 ? 0.1 : cosLatitude)),
      0.0015,
    );

    double minLat = centerLat - latPadding;
    double maxLat = centerLat + latPadding;
    double minLng = centerLng - lngPadding;
    double maxLng = centerLng + lngPadding;

    if (liveLocation != null) {
      minLat = math.min(minLat, liveLocation.latitude);
      maxLat = math.max(maxLat, liveLocation.latitude);
      minLng = math.min(minLng, liveLocation.longitude);
      maxLng = math.max(maxLng, liveLocation.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Set<Marker> _buildMarkers({
    required AppLocalizations l10n,
    required LocationModel? liveLocation,
    required bool isInsideZone,
    required int distanceMeters,
    required String movementLabel,
    required String latestUpdateLabel,
  }) {
    final centerSnippetLines = <String>[
      '${l10n.radius}: ${_formatDistance(widget.zone.radius.toDouble(), l10n)}',
      '${l10n.distance}: ${_formatDistance(distanceMeters.toDouble(), l10n)}',
      '$movementLabel - ${_zoneRelationLabel(isInsideZone)}',
      '${l10n.lastSeen}: $latestUpdateLabel',
    ];

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('safe_zone_center'),
        position: LatLng(widget.zone.latitude, widget.zone.longitude),
        infoWindow: InfoWindow(
          title: widget.zone.name.isNotEmpty
              ? widget.zone.name
              : l10n.safeZoneCenter,
          snippet: centerSnippetLines.join('\n'),
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
      ),
    };

    if (liveLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('device_live_location'),
          position: LatLng(liveLocation.latitude, liveLocation.longitude),
          infoWindow: InfoWindow(
            title: l10n.childLocation,
            snippet: [
              '${l10n.distance}: ${_formatDistance(distanceMeters.toDouble(), l10n)}',
              '$movementLabel - ${_zoneRelationLabel(isInsideZone)}',
              '${l10n.lastSeen}: $latestUpdateLabel',
            ].join('\n'),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isInsideZone
                ? BitmapDescriptor.hueAzure
                : BitmapDescriptor.hueOrange,
          ),
        ),
      );
    }

    return markers;
  }

  String _formatDistance(double meters, AppLocalizations l10n) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(meters % 1000 == 0 ? 0 : 1)} ${l10n.kilometersShort}';
    }

    return '${meters.round()} ${l10n.metersShort}';
  }

  String _formatTimestamp(int timestamp) {
    if (timestamp <= 0) {
      return '--';
    }

    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}/${date.month}/${date.year} '
        '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _movementLabel(LocationModel? liveLocation) {
    if (liveLocation == null) {
      return 'No live data';
    }

    return liveLocation.speed > 0.5 ? 'Moving' : 'Stationary';
  }

  String _zoneRelationLabel(bool isInsideZone) {
    return isInsideZone ? 'Inside safe zone' : 'Outside safe zone';
  }

  String _statusLabel({
    required LocationModel? liveLocation,
    required bool isInsideZone,
  }) {
    if (liveLocation == null) {
      return 'No live data';
    }

    return _zoneRelationLabel(isInsideZone);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.zone.name.isNotEmpty ? widget.zone.name : l10n.safeZoneCenter,
        ),
      ),
      body: Consumer2<GeofenceProvider, LocationProvider>(
        builder: (context, geofenceProvider, locationProvider, child) {
          final liveLocation = locationProvider.liveLocation;
          _scheduleZoneCheck(liveLocation);
          _frameMap(liveLocation);

          ZoneDistance? zoneDistance;
          final checkedZones =
              geofenceProvider.zoneCheckResult?.zones ?? const [];
          for (final zone in checkedZones) {
            if (zone.id == widget.zone.id) {
              zoneDistance = zone;
              break;
            }
          }

          final computedDistance = liveLocation == null
              ? null
              : Geolocator.distanceBetween(
                  widget.zone.latitude,
                  widget.zone.longitude,
                  liveLocation.latitude,
                  liveLocation.longitude,
                ).round();
          final distanceMeters = liveLocation == null
              ? null
              : zoneDistance?.distance ?? computedDistance;
          final isInsideZone = zoneDistance?.inZone ??
              (liveLocation != null &&
                  computedDistance != null &&
                  computedDistance <= widget.zone.radius);
          final movementLabel = _movementLabel(liveLocation);
          final latestUpdateLabel = liveLocation != null
              ? _formatTimestamp(liveLocation.recordedAt)
              : '--';
          final statusLabel = _statusLabel(
            liveLocation: liveLocation,
            isInsideZone: isInsideZone,
          );
          final distanceLabel = distanceMeters == null
              ? '--'
              : _formatDistance(distanceMeters.toDouble(), l10n);

          return Stack(
            children: [
              GoogleMap(
                onMapCreated: (controller) {
                  _mapController = controller;
                  _frameMap(liveLocation);
                },
                onCameraMove: (position) {
                  _lastZoom = position.zoom;
                },
                initialCameraPosition: CameraPosition(
                  target: LatLng(widget.zone.latitude, widget.zone.longitude),
                  zoom: AppConstants.defaultZoom,
                ),
                mapType: _activeMapType,
                markers: _buildMarkers(
                  l10n: l10n,
                  liveLocation: liveLocation,
                  isInsideZone: isInsideZone,
                  distanceMeters: distanceMeters ?? 0,
                  movementLabel: movementLabel,
                  latestUpdateLabel: latestUpdateLabel,
                ),
                circles: {
                  Circle(
                    circleId: CircleId('safe_zone_${widget.zone.id}'),
                    center: LatLng(widget.zone.latitude, widget.zone.longitude),
                    radius: widget.zone.radius.toDouble(),
                    fillColor: AppColors.successColor.withValues(alpha: 0.18),
                    strokeColor: AppColors.successColor,
                    strokeWidth: 2,
                  ),
                },
                padding: EdgeInsets.only(
                  top: 96,
                  left: 16,
                  right: 16,
                  bottom: liveLocation == null ? 96 : 24,
                ),
                mapToolbarEnabled: false,
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                compassEnabled: true,
                buildingsEnabled: true,
                rotateGesturesEnabled: true,
                tiltGesturesEnabled: true,
              ),
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 8,
                  spacing: 8,
                  children: [
                    _MapBadge(
                      label: widget.zone.name.isNotEmpty
                          ? widget.zone.name
                          : l10n.safeZoneCenter,
                      value:
                          '${l10n.radius}: ${_formatDistance(widget.zone.radius.toDouble(), l10n)}',
                    ),
                    _MapBadge(
                      label: l10n.distance,
                      value: distanceLabel,
                    ),
                    _MapBadge(
                      label: l10n.status,
                      value: statusLabel,
                    ),
                    _MapBadge(
                      label: l10n.lastSeen,
                      value: latestUpdateLabel,
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                bottom: liveLocation == null ? 92 : 16,
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: PopupMenuButton<_MapViewMode>(
                    tooltip: 'Change map style',
                    initialValue: _mapViewMode,
                    onSelected: (mode) => _setMapViewMode(mode, liveLocation),
                    itemBuilder: (context) => _MapViewMode.values
                        .map(
                          (mode) => PopupMenuItem<_MapViewMode>(
                            value: mode,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (mode == _mapViewMode)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: Icon(Icons.check, size: 18),
                                  )
                                else
                                  const SizedBox(width: 26),
                                Text(_mapViewLabel(mode)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.layers_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _mapViewLabel(_mapViewMode),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (liveLocation == null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        locationProvider.error?.trim().isNotEmpty == true
                            ? locationProvider.error!.trim()
                            : 'No live location available',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MapBadge extends StatelessWidget {
  final String label;
  final String value;

  const _MapBadge({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
