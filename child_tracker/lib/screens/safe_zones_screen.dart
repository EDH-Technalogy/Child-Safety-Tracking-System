import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/geofence_provider.dart';
import '../providers/location_provider.dart';
import '../utils/constants.dart';
import '../utils/timestamp_utils.dart';
import '../models/geofence_model.dart';
import '../models/location_model.dart';
import 'add_safe_zone_screen.dart';
import 'safe_zone_detail_screen.dart';
import '../widgets/google_map_guard.dart';

class SafeZonesScreen extends StatefulWidget {
  final String? childId;

  const SafeZonesScreen({super.key, this.childId});

  @override
  State<SafeZonesScreen> createState() => _SafeZonesScreenState();
}

class _SafeZonesScreenState extends State<SafeZonesScreen> {
  final TextEditingController _searchController = TextEditingController();
  GoogleMapController? _mapController;
  String? _lastZoneCheckKey;
  bool _ownsLocationTracking = false;

  @override
  void initState() {
    super.initState();
    _loadSafeZones();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    if (_ownsLocationTracking) {
      Provider.of<LocationProvider>(context, listen: false).stopLiveTracking();
    }
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSafeZones() async {
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);

    if (widget.childId != null && widget.childId!.isNotEmpty) {
      await geofenceProvider.loadSafeZones(widget.childId!);
      await locationProvider.getLiveLocation(widget.childId!);

      final shouldOwnTracking = !locationProvider.isTracking ||
          locationProvider.trackingChildId != widget.childId;
      if (shouldOwnTracking) {
        locationProvider.startLiveTracking(widget.childId!);
        _ownsLocationTracking = true;
      }

      final liveLocation = locationProvider.liveLocation;
      if (liveLocation != null) {
        await geofenceProvider.checkLocationInZone(
          childId: widget.childId!,
          latitude: liveLocation.latitude,
          longitude: liveLocation.longitude,
        );
      }
      return;
    }

    await geofenceProvider.loadAccessibleSafeZones();
  }

  List<GeofenceModel> _filterZones(List<GeofenceModel> zones) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return zones;
    }

    return zones.where((zone) {
      return zone.name.toLowerCase().contains(query) ||
          zone.childName.toLowerCase().contains(query) ||
          zone.childId.toLowerCase().contains(query);
    }).toList();
  }

  void _scheduleZoneCheck(LocationModel? liveLocation) {
    if (widget.childId == null || liveLocation == null) {
      return;
    }

    final nextKey = [
      widget.childId,
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
          childId: widget.childId!,
          latitude: liveLocation.latitude,
          longitude: liveLocation.longitude,
        ),
      );
    });
  }

  void _maybeFocusLiveLocation(LocationModel? liveLocation) {
    if (_mapController == null || liveLocation == null) {
      return;
    }

    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    if (locationProvider.isAnimatingLiveLocation) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _mapController == null) {
        return;
      }

      _mapController!.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(liveLocation.latitude, liveLocation.longitude),
        ),
      );
    });
  }

  Widget _buildLiveTrackingMap({
    required BuildContext context,
    required GeofenceProvider geofenceProvider,
    required LocationProvider locationProvider,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final liveLocation = locationProvider.liveLocation;

    if (widget.childId == null || widget.childId!.isEmpty) {
      return const SizedBox.shrink();
    }

    if (liveLocation == null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.location_off, color: AppColors.warningColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  locationProvider.isLoading ? l10n.loading : l10n.noData,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }

    _scheduleZoneCheck(liveLocation);
    _maybeFocusLiveLocation(liveLocation);

    final zoneCheck = geofenceProvider.zoneCheckResult;
    final nearestZone = zoneCheck != null && zoneCheck.zones.isNotEmpty
        ? (zoneCheck.zones.toList()
              ..sort((left, right) => left.distance.compareTo(right.distance)))
            .first
        : null;
    final statusColor = zoneCheck == null
        ? AppColors.infoColor
        : zoneCheck.inZone
            ? AppColors.successColor
            : AppColors.warningColor;
    final statusText = zoneCheck == null
        ? l10n.loading
        : zoneCheck.inZone
            ? 'Inside ${zoneCheck.currentZone?.name ?? l10n.safeZones}'
            : nearestZone != null
                ? 'Outside by ${nearestZone.distance} ${l10n.metersShort}'
                : 'Outside safe zones';
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('device_live_location'),
        position: LatLng(liveLocation.latitude, liveLocation.longitude),
        infoWindow: InfoWindow(
          title: l10n.childLocation,
          snippet: l10n.liveTracking,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
    };
    final circles = geofenceProvider.safeZones.map((zone) {
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

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.liveTracking,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 240,
            child: GoogleMapAvailabilityGuard(
              mapBuilder: (_) => GoogleMap(
                onMapCreated: (controller) {
                  _mapController = controller;
                },
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    liveLocation.latitude,
                    liveLocation.longitude,
                  ),
                  zoom: AppConstants.defaultZoom,
                ),
                markers: markers,
                circles: circles,
                mapToolbarEnabled: false,
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
              ),
              fallbackBuilder: (_) => const GoogleMapUnavailableState(
                title: 'Map unavailable',
                message:
                    'Google Maps is not ready in this browser right now. Check the web Maps script and API key configuration.',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _LiveInfoChip(
                  label: l10n.location,
                  value:
                      '${liveLocation.latitude.toStringAsFixed(5)}, ${liveLocation.longitude.toStringAsFixed(5)}',
                ),
                _LiveInfoChip(
                  label: l10n.lastSeen,
                  value: _formatTimestamp(liveLocation.recordedAt),
                ),
                _LiveInfoChip(
                  label: l10n.battery,
                  value: '${liveLocation.battery}%',
                ),
                if (nearestZone != null)
                  _LiveInfoChip(
                    label: l10n.radius,
                    value:
                        '${nearestZone.distance} ${l10n.metersShort} from ${nearestZone.name}',
                  ),
              ],
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

    return '${date.day}/${date.month}/${date.year} '
        '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.safeZones),
      ),
      body: Consumer2<GeofenceProvider, LocationProvider>(
        builder: (context, geofenceProvider, locationProvider, child) {
          final visibleZones = _filterZones(geofenceProvider.safeZones);

          if (geofenceProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (geofenceProvider.safeZones.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noData,
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.childId != null
                        ? l10n.addSafeZone
                        : l10n.noSafeZonesAvailableForScope,
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.childId != null) ...[
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/add-safe-zone',
                          arguments: widget.childId,
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: Text(l10n.addSafeZone),
                    ),
                  ],
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadSafeZones,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildLiveTrackingMap(
                  context: context,
                  geofenceProvider: geofenceProvider,
                  locationProvider: locationProvider,
                ),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.searchSafeZonesPlaceholder,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (visibleZones.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 80),
                    child: Column(
                      children: [
                        Icon(Icons.search_off,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          '${l10n.noSafeZonesMatch} "${_searchController.text}"',
                          style:
                              TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                else
                  ...visibleZones.map(
                    (zone) => _SafeZoneCard(
                      zone: zone,
                      showChildMetadata:
                          widget.childId == null || widget.childId!.isEmpty,
                      onTap: () => _openSafeZoneDetails(zone),
                      onEdit: () => _showEditDialog(zone),
                      onDelete: () => _showDeleteDialog(zone),
                      onToggle: () => _toggleZone(zone),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: widget.childId == null
          ? null
          : FloatingActionButton(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/add-safe-zone',
                  arguments: widget.childId,
                );
              },
              backgroundColor: AppColors.primaryColor,
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }

  Future<void> _showEditDialog(GeofenceModel zone) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddSafeZoneScreen(
          childId: zone.childId,
          initialZone: zone,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadSafeZones();
  }

  Future<void> _openSafeZoneDetails(GeofenceModel zone) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SafeZoneDetailScreen(zone: zone),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadSafeZones();
  }

  Future<void> _showDeleteDialog(GeofenceModel zone) async {
    final l10n = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.delete),
        content: Text('${l10n.areYouSureDeleteZone}\n"${zone.name}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final navigator = Navigator.of(dialogContext);
              final geofenceProvider = Provider.of<GeofenceProvider>(
                dialogContext,
                listen: false,
              );
              await geofenceProvider.deleteSafeZone(
                zone.id,
                childId: widget.childId,
              );
              if (mounted) {
                navigator.pop();
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleZone(GeofenceModel zone) async {
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);
    await geofenceProvider.updateSafeZone(
      zoneId: zone.id,
      status: zone.status == 'active' ? 'inactive' : 'active',
      childId: widget.childId,
    );
    _loadSafeZones();
  }
}

class _SafeZoneCard extends StatelessWidget {
  final GeofenceModel zone;
  final bool showChildMetadata;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _SafeZoneCard({
    required this.zone,
    required this.showChildMetadata,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isActive = zone.status == 'active';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? AppColors.successColor : Colors.grey,
          width: isActive ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.successColor.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.location_on,
                      color: isActive ? AppColors.successColor : Colors.grey,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          zone.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (showChildMetadata) ...[
                          const SizedBox(height: 4),
                          Text(
                            zone.childName.isNotEmpty
                                ? '${l10n.child}: ${zone.childName}'
                                : '${l10n.childId}: ${zone.childId}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (zone.childName.isNotEmpty &&
                              zone.childId.isNotEmpty)
                            Text(
                              '${l10n.childId}: ${zone.childId}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.successColor
                                        .withValues(alpha: 0.1)
                                    : Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isActive ? l10n.online : l10n.offline,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isActive
                                      ? AppColors.successColor
                                      : Colors.grey,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.radar,
                                size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              '${l10n.radius}: ${zone.radius} ${l10n.metersShort}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onTap,
                    icon: const Icon(
                      Icons.map_outlined,
                      color: AppColors.primaryColor,
                    ),
                    tooltip: l10n.liveTracking,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.locationSettings,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${zone.latitude.toStringAsFixed(4)}, ${zone.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: onToggle,
                    icon: Icon(
                      isActive ? Icons.pause : Icons.play_arrow,
                      size: 18,
                    ),
                    label: Text(isActive ? l10n.deactivate : l10n.activate),
                  ),
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 18),
                    label: Text(l10n.edit),
                  ),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    label: Text(l10n.delete,
                        style: const TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveInfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _LiveInfoChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
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
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
