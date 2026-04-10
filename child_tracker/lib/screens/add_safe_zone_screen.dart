import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/geofence_model.dart';
import '../providers/auth_provider.dart';
import '../providers/child_provider.dart';
import '../providers/geofence_provider.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';

class AddSafeZoneScreen extends StatefulWidget {
  final String childId;
  final GeofenceModel? initialZone;

  const AddSafeZoneScreen({
    super.key,
    required this.childId,
    this.initialZone,
  });

  bool get isEditMode => initialZone != null;

  @override
  State<AddSafeZoneScreen> createState() => _AddSafeZoneScreenState();
}

class _AddSafeZoneScreenState extends State<AddSafeZoneScreen> {
  static const int _minRadius = 50;
  static const int _maxRadius = 50000;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _childIdController;
  late final TextEditingController _childNameController;
  final ApiService _apiService = ApiService();

  GoogleMapController? _mapController;
  double? _latitude;
  double? _longitude;
  late int _radius;
  bool _isLoadingLocation = false;
  bool _isLoadingChildContext = false;
  Set<Marker> _markers = <Marker>{};
  Set<Circle> _circles = <Circle>{};

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.initialZone?.name ?? '');
    _childIdController = TextEditingController(
      text: widget.initialZone?.childId.isNotEmpty == true
          ? widget.initialZone!.childId
          : widget.childId,
    );
    _childNameController = TextEditingController(
      text: widget.initialZone?.childName ?? '',
    );
    _radius = (widget.initialZone?.radius ?? AppConstants.defaultSafeZoneRadius)
        .clamp(_minRadius, _maxRadius);
    _latitude = widget.initialZone?.latitude;
    _longitude = widget.initialZone?.longitude;

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChildContext());

    if (_latitude != null && _longitude != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateMap());
    } else {
      _getCurrentLocation();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _childIdController.dispose();
    _childNameController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadChildContext() async {
    if (_childNameController.text.trim().isNotEmpty) {
      return;
    }

    final childProvider = Provider.of<ChildProvider>(context, listen: false);
    final selectedChild = childProvider.selectedChild;
    if (selectedChild?.id == widget.childId &&
        selectedChild!.name.trim().isNotEmpty) {
      _childIdController.text = selectedChild.id;
      _childNameController.text = selectedChild.name.trim();
      return;
    }

    setState(() {
      _isLoadingChildContext = true;
    });

    try {
      final response = await _apiService.getChildById(widget.childId);
      if (!mounted) {
        return;
      }

      final resolvedChildId =
          (response['id'] ?? widget.childId).toString().trim();
      final resolvedChildName = (response['name'] ?? '').toString().trim();

      if (kDebugMode) {
        debugPrint(
          '[AddSafeZoneScreen] opened for childId=$resolvedChildId childName=$resolvedChildName',
        );
      }

      if (resolvedChildId.isNotEmpty) {
        _childIdController.text = resolvedChildId;
      }
      if (resolvedChildName.isNotEmpty) {
        _childNameController.text = resolvedChildName;
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[AddSafeZoneScreen] failed to load child context for childId=${widget.childId}: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingChildContext = false;
        });
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setFallbackLocation();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _isLoadingLocation = false;
      });

      _updateMap();
    } catch (_) {
      _setFallbackLocation();
    }
  }

  void _setFallbackLocation() {
    setState(() {
      _latitude ??= AppConstants.defaultLatitude;
      _longitude ??= AppConstants.defaultLongitude;
      _isLoadingLocation = false;
    });
    _updateMap();
  }

  void _updateMap() {
    if (_latitude == null || _longitude == null) {
      return;
    }

    final markerPosition = LatLng(_latitude!, _longitude!);

    setState(() {
      _markers = <Marker>{
        Marker(
          markerId: const MarkerId('selected_location'),
          position: markerPosition,
          draggable: true,
          onDragEnd: (newPosition) {
            setState(() {
              _latitude = newPosition.latitude;
              _longitude = newPosition.longitude;
            });
            _updateCircles();
          },
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: context.l10n.safeZoneCenter,
            snippet: context.l10n.dragToAdjustLocation,
          ),
        ),
      };
      _updateCircles();
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: markerPosition, zoom: 16),
      ),
    );
  }

  void _updateCircles() {
    if (_latitude == null || _longitude == null) {
      return;
    }

    _circles = <Circle>{
      Circle(
        circleId: const CircleId('zone_radius'),
        center: LatLng(_latitude!, _longitude!),
        radius: _radius.toDouble(),
        fillColor: AppColors.successColor.withValues(alpha: 0.2),
        strokeColor: AppColors.successColor,
        strokeWidth: 2,
      ),
    };
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _latitude = position.latitude;
      _longitude = position.longitude;
    });
    _updateMap();
  }

  String _validateZoneName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return context.l10n.pleaseEnterSafeZoneName;
    }

    return '';
  }

  Future<void> _saveSafeZone() async {
    final l10n = context.l10n;
    final validationMessage = _validateZoneName(_nameController.text);
    if (validationMessage.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationMessage),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseSelectLocation),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    if (_radius < _minRadius || _radius > _maxRadius) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.safeZoneRadiusRange),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);
    final resolvedChildId = _childIdController.text.trim().isNotEmpty
        ? _childIdController.text.trim()
        : widget.childId;
    final resolvedChildName = _childNameController.text.trim();

    if (kDebugMode) {
      debugPrint(
        '[AddSafeZoneScreen] save payload childId=$resolvedChildId childName=$resolvedChildName zoneName=${_nameController.text.trim()}',
      );
    }

    final isSuccess = widget.isEditMode
        ? await geofenceProvider.updateSafeZone(
            zoneId: widget.initialZone!.id,
            name: _nameController.text.trim(),
            latitude: _latitude!,
            longitude: _longitude!,
            radius: _radius,
            childId: resolvedChildId,
            childName: resolvedChildName,
          )
        : await geofenceProvider.createSafeZone(
            childId: resolvedChildId,
            userId: authProvider.user?.id ?? '',
            childName: resolvedChildName,
            name: _nameController.text.trim(),
            latitude: _latitude!,
            longitude: _longitude!,
            radius: _radius,
          );

    if (!mounted) {
      return;
    }

    if (isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditMode
                ? l10n.safeZoneUpdatedSuccessfully
                : l10n.safeZoneCreatedSuccessfully,
          ),
          backgroundColor: AppColors.successColor,
        ),
      );
      Navigator.pop(context);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          geofenceProvider.error != null
              ? localizeRawMessage(l10n, geofenceProvider.error!)
              : (widget.isEditMode
                  ? l10n.failedToUpdateSafeZone
                  : l10n.failedToCreateSafeZone),
        ),
        backgroundColor: AppColors.errorColor,
      ),
    );
  }

  String _formatRadiusLabel() {
    if (_radius >= 1000) {
      return '${(_radius / 1000).toStringAsFixed(_radius % 1000 == 0 ? 0 : 1)} ${context.l10n.kilometersShort}';
    }
    return '$_radius ${context.l10n.meters}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode ? l10n.editSafeZone : l10n.addSafeZone),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _getCurrentLocation,
            tooltip: l10n.useMyLocation,
          ),
        ],
      ),
      body: Consumer<GeofenceProvider>(
        builder: (context, geofenceProvider, child) {
          return Column(
            children: [
              Expanded(
                flex: 2,
                child: Stack(
                  children: [
                    GoogleMap(
                      onMapCreated: (controller) {
                        _mapController = controller;
                        _updateMap();
                      },
                      onTap: _onMapTap,
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          _latitude ?? AppConstants.defaultLatitude,
                          _longitude ?? AppConstants.defaultLongitude,
                        ),
                        zoom: 16,
                      ),
                      markers: _markers,
                      circles: _circles,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                    ),
                    if (_isLoadingLocation)
                      Container(
                        color: Colors.black26,
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: Card(
                        color: Colors.white.withValues(alpha: 0.9),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.touch_app,
                                color: AppColors.primaryColor,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.tapOnMapToSelectLocation,
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton(
                            heroTag: 'safe_zone_zoom_in',
                            mini: true,
                            onPressed: () {
                              _mapController?.animateCamera(
                                CameraUpdate.zoomIn(),
                              );
                            },
                            child: const Icon(Icons.add),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton(
                            heroTag: 'safe_zone_zoom_out',
                            mini: true,
                            onPressed: () {
                              _mapController?.animateCamera(
                                CameraUpdate.zoomOut(),
                              );
                            },
                            child: const Icon(Icons.remove),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: l10n.zoneName,
                            prefixIcon: Icon(Icons.label),
                            hintText: l10n.zoneNameHint,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _childIdController,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: l10n.childId,
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _childNameController,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: l10n.childName,
                            prefixIcon: const Icon(Icons.child_care),
                            suffixIcon: _isLoadingChildContext
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      l10n.radius,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryColor,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _formatRadiusLabel(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Slider(
                                  value: _radius.toDouble(),
                                  min: _minRadius.toDouble(),
                                  max: _maxRadius.toDouble(),
                                  divisions: 999,
                                  activeColor: AppColors.primaryColor,
                                  onChanged: (value) {
                                    setState(() {
                                      _radius = value.round();
                                      _updateCircles();
                                    });
                                  },
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '50${l10n.metersShort}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    Text(
                                      '50${l10n.kilometersShort}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _QuickRadiusChip(
                                      radius: 50,
                                      isSelected: _radius == 50,
                                      onTap: () => setState(() {
                                        _radius = 50;
                                        _updateCircles();
                                      }),
                                    ),
                                    _QuickRadiusChip(
                                      radius: 100,
                                      isSelected: _radius == 100,
                                      onTap: () => setState(() {
                                        _radius = 100;
                                        _updateCircles();
                                      }),
                                    ),
                                    _QuickRadiusChip(
                                      radius: 500,
                                      isSelected: _radius == 500,
                                      onTap: () => setState(() {
                                        _radius = 500;
                                        _updateCircles();
                                      }),
                                    ),
                                    _QuickRadiusChip(
                                      radius: 1000,
                                      isSelected: _radius == 1000,
                                      onTap: () => setState(() {
                                        _radius = 1000;
                                        _updateCircles();
                                      }),
                                    ),
                                    _QuickRadiusChip(
                                      radius: 5000,
                                      isSelected: _radius == 5000,
                                      onTap: () => setState(() {
                                        _radius = 5000;
                                        _updateCircles();
                                      }),
                                    ),
                                    _QuickRadiusChip(
                                      radius: 10000,
                                      isSelected: _radius == 10000,
                                      onTap: () => setState(() {
                                        _radius = 10000;
                                        _updateCircles();
                                      }),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.selectedLocation,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on,
                                      color: AppColors.primaryColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _latitude != null && _longitude != null
                                            ? '${l10n.latitude}: ${_latitude!.toStringAsFixed(6)}, ${l10n.longitude}: ${_longitude!.toStringAsFixed(6)}'
                                            : l10n.noLocationSelected,
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          color: AppColors.infoColor.withValues(alpha: 0.1),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(Icons.info, color: AppColors.infoColor),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    l10n.safeZoneAlertsInfo,
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed:
                              geofenceProvider.isLoading ? null : _saveSafeZone,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: geofenceProvider.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  widget.isEditMode
                                      ? l10n.updateSafeZone
                                      : l10n.createSafeZone,
                                  style: const TextStyle(fontSize: 16),
                                ),
                        ),
                      ],
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

class _QuickRadiusChip extends StatelessWidget {
  final int radius;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickRadiusChip({
    required this.radius,
    required this.isSelected,
    required this.onTap,
  });

  String _label(BuildContext context) {
    if (radius >= 1000) {
      return '${(radius / 1000).toStringAsFixed(radius % 1000 == 0 ? 0 : 1)} ${context.l10n.kilometersShort}';
    }
    return '$radius ${context.l10n.metersShort}';
  }

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(
        _label(context),
        style: TextStyle(
          color: isSelected ? Colors.white : AppColors.primaryColor,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      backgroundColor: isSelected ? AppColors.primaryColor : null,
      side: const BorderSide(color: AppColors.primaryColor),
      onPressed: onTap,
    );
  }
}
