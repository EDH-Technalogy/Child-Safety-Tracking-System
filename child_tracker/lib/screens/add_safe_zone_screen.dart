import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../models/geofence_model.dart';
import '../providers/auth_provider.dart';
import '../providers/child_provider.dart';
import '../providers/geofence_provider.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';
import '../utils/timestamp_utils.dart';
import 'safe_zone_detail_screen.dart';

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
  LatLng? _savedCenter;
  LatLng? _selectedCenter;
  LatLng? _previewCenter;
  late int _radius;
  late _SafeZoneCenterSource _centerSource;
  _SafeZoneMapViewMode _mapViewMode = _SafeZoneMapViewMode.defaultView;
  bool _isLoadingLocation = false;
  bool _isLoadingChildContext = false;
  bool _isLoadingSavedLocations = false;
  List<_SavedLocationOption> _savedLocationOptions = <_SavedLocationOption>[];
  String? _selectedSavedLocationId;
  String? _savedLocationError;
  String? _liveLocationError;
  int? _lastLiveLocationAt;
  bool _localizedMapArtifactsInitialized = false;
  double _lastMapZoom = 16;
  Set<Marker> _markers = <Marker>{};
  Set<Circle> _circles = <Circle>{};

  double? _parseCoordinate(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  LatLng? get _displayedCenter {
    if (_selectedCenter != null) {
      return _selectedCenter;
    }

    if (widget.isEditMode && _savedCenter != null) {
      return _savedCenter;
    }

    return _previewCenter ?? _savedCenter;
  }

  LatLng? get _persistedCenterForSave => _selectedCenter ?? _savedCenter;

  @override
  void initState() {
    super.initState();
    _centerSource = widget.isEditMode
        ? _SafeZoneCenterSource.customMap
        : _SafeZoneCenterSource.currentLiveLocation;
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
    if (_isValidCoordinate(widget.initialZone?.latitude, widget.initialZone?.longitude)) {
      _savedCenter = LatLng(
        widget.initialZone!.latitude,
        widget.initialZone!.longitude,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadChildContext();
      await _bootstrapCenterSelection();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_localizedMapArtifactsInitialized) {
      return;
    }

    if (_displayedCenter != null) {
      _rebuildMapArtifacts();
    }

    _localizedMapArtifactsInitialized = true;
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

  Future<void> _bootstrapCenterSelection() async {
    await _loadSavedLocations();

    if (widget.isEditMode && _savedCenter != null) {
      _animateToCenter(_savedCenter!);
      return;
    }

    final loadedLiveLocation = await _useCurrentLiveLocation(
      showFeedback: false,
      animate: false,
      applyAsSelection: false,
    );
    if (loadedLiveLocation) {
      return;
    }

    if (_savedLocationOptions.isNotEmpty) {
      _applySavedLocation(
        _savedLocationOptions.first,
        animate: false,
        applyAsSelection: false,
      );
      return;
    }

    _centerSource = _SafeZoneCenterSource.customMap;
    await _useDeviceLocationAsCustomFallback();
  }

  Future<void> _loadSavedLocations() async {
    setState(() {
      _isLoadingSavedLocations = true;
      _savedLocationError = null;
    });

    try {
      final response = await _apiService.getLocationHistory(widget.childId);
      final seenCoordinates = <String>{};
      final options = <_SavedLocationOption>[];

      for (final entry in response) {
        if (entry is! Map) {
          continue;
        }

        final payload = Map<String, dynamic>.from(entry);
        final latitude = _parseCoordinate(payload['latitude']);
        final longitude = _parseCoordinate(payload['longitude']);
        if (!_isValidCoordinate(latitude, longitude)) {
          continue;
        }

        final coordinateKey =
            '${latitude!.toStringAsFixed(6)}|${longitude!.toStringAsFixed(6)}';
        if (!seenCoordinates.add(coordinateKey)) {
          continue;
        }

        options.add(
          _SavedLocationOption(
            id: (payload['id'] ?? coordinateKey).toString(),
            latitude: latitude,
            longitude: longitude,
            recordedAt: _parseTimestamp(
              payload['recorded_at'] ?? payload['timestamp'],
            ),
            speed: _parseCoordinate(payload['speed']),
            label: (payload['location_text'] ?? payload['address'] ?? '')
                .toString()
                .trim(),
          ),
        );

        if (options.length >= 12) {
          break;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _savedLocationOptions = options;
        final selectedExists = options.any(
          (option) => option.id == _selectedSavedLocationId,
        );
        _selectedSavedLocationId = selectedExists || options.isEmpty
            ? _selectedSavedLocationId
            : options.first.id;
        _isLoadingSavedLocations = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _savedLocationOptions = <_SavedLocationOption>[];
        _savedLocationError = error.toString();
        _isLoadingSavedLocations = false;
      });
    }
  }

  Future<bool> _useCurrentLiveLocation({
    required bool showFeedback,
    bool animate = true,
    bool applyAsSelection = true,
  }) async {
    if (mounted) {
      setState(() {
        _isLoadingLocation = true;
      });
    }

    try {
      final response = await _apiService.getLiveLocation(widget.childId);
      final latitude = _parseCoordinate(response['latitude']);
      final longitude = _parseCoordinate(response['longitude']);
      if (!_isValidCoordinate(latitude, longitude)) {
        throw Exception('No valid live location available');
      }

      _lastLiveLocationAt = _parseTimestamp(
        response['recorded_at'] ?? response['timestamp'],
      );
      _liveLocationError = null;
      final applyCenter = applyAsSelection
          ? _applyManualCenterSelection
          : _setPreviewCenter;
      applyCenter(
        latitude: latitude!,
        longitude: longitude!,
        source: _SafeZoneCenterSource.currentLiveLocation,
        animate: animate,
      );
      return true;
    } catch (error) {
      _liveLocationError =
          error.toString().replaceFirst('Exception: ', '').trim();
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_liveLocationError ??
                'Live location is unavailable right now.'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _useDeviceLocationAsCustomFallback() async {
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
        if (mounted) {
          setState(() {
            _isLoadingLocation = false;
          });
        }
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

      _setPreviewCenter(
        latitude: position.latitude,
        longitude: position.longitude,
        source: _SafeZoneCenterSource.customMap,
        animate: false,
      );
    } catch (_) {
      // Keep the map usable even if device geolocation is unavailable.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  bool _isValidCoordinate(double? latitude, double? longitude) {
    return latitude != null &&
        longitude != null &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  int? _parseTimestamp(dynamic value) {
    if (value is int) {
      if (value < 1000000000) {
        return null;
      }
      return value < 100000000000 ? value * 1000 : value;
    }
    if (value is num) {
      final numericValue = value.round();
      if (numericValue < 1000000000) {
        return null;
      }
      return numericValue < 100000000000 ? numericValue * 1000 : numericValue;
    }
    return null;
  }

  void _setPreviewCenter({
    required double latitude,
    required double longitude,
    required _SafeZoneCenterSource source,
    String? savedLocationId,
    bool animate = true,
  }) {
    if (!_isValidCoordinate(latitude, longitude)) {
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[AddSafeZoneScreen] center source=${source.name} latitude=$latitude longitude=$longitude radius=$_radius',
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _centerSource = source;
      _previewCenter = LatLng(latitude, longitude);
      _selectedSavedLocationId =
          source == _SafeZoneCenterSource.previousSavedLocation
              ? (savedLocationId ?? _selectedSavedLocationId)
              : _selectedSavedLocationId;
      _rebuildMapArtifacts();
    });

    if (animate) {
      _animateToCenter(_previewCenter!);
    }
  }

  void _applyManualCenterSelection({
    required double latitude,
    required double longitude,
    required _SafeZoneCenterSource source,
    String? savedLocationId,
    bool animate = true,
  }) {
    if (!_isValidCoordinate(latitude, longitude)) {
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[AddSafeZoneScreen] selected center source=${source.name} latitude=$latitude longitude=$longitude radius=$_radius',
      );
    }

    if (!mounted) {
      return;
    }

    final center = LatLng(latitude, longitude);
    setState(() {
      _centerSource = source;
      _selectedCenter = center;
      _previewCenter = center;
      _selectedSavedLocationId =
          source == _SafeZoneCenterSource.previousSavedLocation
              ? savedLocationId
              : null;
      _rebuildMapArtifacts();
    });

    if (animate) {
      _animateToCenter(center);
    }
  }

  void _applySavedLocation(
    _SavedLocationOption option, {
    bool animate = true,
    bool applyAsSelection = true,
  }) {
    final applyCenter = applyAsSelection
        ? _applyManualCenterSelection
        : _setPreviewCenter;
    applyCenter(
      latitude: option.latitude,
      longitude: option.longitude,
      source: _SafeZoneCenterSource.previousSavedLocation,
      savedLocationId: option.id,
      animate: animate,
    );
  }

  Future<void> _selectCenterSource(_SafeZoneCenterSource source) async {
    if (source == _centerSource &&
        source != _SafeZoneCenterSource.currentLiveLocation) {
      return;
    }

    if (source == _SafeZoneCenterSource.previousSavedLocation) {
      if (mounted) {
        setState(() {
          _centerSource = source;
        });
      }

      if (_savedLocationOptions.isEmpty && !_isLoadingSavedLocations) {
        await _loadSavedLocations();
      }

      if (_savedLocationOptions.isNotEmpty) {
        final selectedOption = _savedLocationOptions.firstWhere(
          (option) => option.id == _selectedSavedLocationId,
          orElse: () => _savedLocationOptions.first,
        );
        _applySavedLocation(
          selectedOption,
          applyAsSelection: false,
        );
      }
      return;
    }

    if (source == _SafeZoneCenterSource.currentLiveLocation) {
      if (mounted) {
        setState(() {
          _centerSource = source;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _centerSource = source;
      });
    }
  }

  void _rebuildMapArtifacts() {
    final displayedCenter = _displayedCenter;
    if (displayedCenter == null) {
      _markers = <Marker>{};
      _circles = <Circle>{};
      return;
    }

    final markerPosition = displayedCenter;
    final hasManualSelection = _selectedCenter != null;
    final isSavedCenterVisible =
        _selectedCenter == null && widget.isEditMode && _savedCenter != null;

    _markers = <Marker>{
      Marker(
        markerId: const MarkerId('selected_location'),
        position: markerPosition,
        draggable: true,
        onDragEnd: (newPosition) {
          _applyManualCenterSelection(
            latitude: newPosition.latitude,
            longitude: newPosition.longitude,
            source: _SafeZoneCenterSource.customMap,
          );
        },
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(
          title: context.l10n.safeZoneCenter,
          snippet: hasManualSelection
              ? context.l10n.dragToAdjustLocation
              : isSavedCenterVisible
                  ? 'Saved center. Tap the map or use a location action, then save to change it.'
                  : 'Preview only. Tap the map or use a location action to set the center before saving.',
        ),
      ),
    };
    _circles = <Circle>{
      Circle(
        circleId: const CircleId('zone_radius'),
        center: displayedCenter,
        radius: _radius.toDouble(),
        fillColor: AppColors.successColor.withValues(alpha: 0.2),
        strokeColor: AppColors.successColor,
        strokeWidth: 2,
      ),
    };
  }

  void _animateToCenter(LatLng center) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: center,
          zoom: _lastMapZoom,
          tilt: _mapViewMode == _SafeZoneMapViewMode.threeDimensionalLike
              ? 55
              : 0,
          bearing: _mapViewMode == _SafeZoneMapViewMode.threeDimensionalLike
              ? 35
              : 0,
        ),
      ),
    );
  }

  void _onMapTap(LatLng position) {
    _applyManualCenterSelection(
      latitude: position.latitude,
      longitude: position.longitude,
      source: _SafeZoneCenterSource.customMap,
    );
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

    final centerToPersist = _persistedCenterForSave;
    if (centerToPersist == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditMode
                ? 'Choose a new center and save, or keep the existing saved center.'
                : l10n.pleaseSelectLocation,
          ),
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
        '[AddSafeZoneScreen] save payload source=${_centerSource.name} childId=$resolvedChildId childName=$resolvedChildName zoneName=${_nameController.text.trim()} latitude=${centerToPersist.latitude} longitude=${centerToPersist.longitude} radius=$_radius selectedCenter=${_selectedCenter != null} savedCenter=${_savedCenter != null}',
      );
    }

    final isSuccess = widget.isEditMode
        ? await geofenceProvider.updateSafeZone(
            zoneId: widget.initialZone!.id,
            name: _nameController.text.trim(),
            latitude: centerToPersist.latitude,
            longitude: centerToPersist.longitude,
            radius: _radius,
            childId: resolvedChildId,
            childName: resolvedChildName,
            centerSource: _centerSource.name,
          )
        : await geofenceProvider.createSafeZone(
            childId: resolvedChildId,
            userId: authProvider.user?.id ?? '',
            childName: resolvedChildName,
            name: _nameController.text.trim(),
            latitude: centerToPersist.latitude,
            longitude: centerToPersist.longitude,
            radius: _radius,
            centerSource: _centerSource.name,
          );

    if (!mounted) {
      return;
    }

    if (isSuccess) {
      if (kDebugMode) {
        debugPrint(
          '[AddSafeZoneScreen] save succeeded source=${_centerSource.name} latitude=${centerToPersist.latitude} longitude=${centerToPersist.longitude} radius=$_radius',
        );
      }
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
      if (widget.isEditMode) {
        Navigator.pop(context);
        return;
      }

      final resolvedZone = geofenceProvider.lastSavedZone ??
          GeofenceModel(
            id: '',
            childId: resolvedChildId,
            childName: resolvedChildName,
            userId: authProvider.user?.id ?? '',
            name: _nameController.text.trim(),
            latitude: centerToPersist.latitude,
            longitude: centerToPersist.longitude,
            radius: _radius,
            status: 'active',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SafeZoneDetailScreen(zone: resolvedZone),
        ),
      );
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[AddSafeZoneScreen] save failed source=${_centerSource.name} latitude=${centerToPersist.latitude} longitude=${centerToPersist.longitude} radius=$_radius error=${geofenceProvider.error}',
      );
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

  String _centerSourceLabel(_SafeZoneCenterSource source) {
    switch (source) {
      case _SafeZoneCenterSource.previousSavedLocation:
        return 'Previous saved location';
      case _SafeZoneCenterSource.currentLiveLocation:
        return 'Current live location';
      case _SafeZoneCenterSource.customMap:
        return 'Custom location from map';
    }
  }

  String _mapInstructionText() {
    switch (_centerSource) {
      case _SafeZoneCenterSource.previousSavedLocation:
        return 'Previewing a saved location. Tap the map, drag the marker, or confirm a location action before saving a new center.';
      case _SafeZoneCenterSource.currentLiveLocation:
        return 'Previewing the child\'s current live location. Use the action button or tap the map to set a new center before saving.';
      case _SafeZoneCenterSource.customMap:
        return context.l10n.tapOnMapToSelectLocation;
    }
  }

  String _centerPersistenceStatusText() {
    if (_selectedCenter != null) {
      return 'Pending change: save to update the safe zone center.';
    }

    if (_savedCenter != null) {
      return 'Saved center loaded from the database.';
    }

    if (_previewCenter != null) {
      return 'Preview only: choose this location explicitly, then save to keep it.';
    }

    return 'No center selected yet.';
  }

  String _displayedCenterText(BuildContext context) {
    final l10n = context.l10n;
    final displayedCenter = _displayedCenter;
    if (displayedCenter == null) {
      return l10n.noLocationSelected;
    }

    return '${l10n.latitude}: ${displayedCenter.latitude.toStringAsFixed(6)}, ${l10n.longitude}: ${displayedCenter.longitude.toStringAsFixed(6)}';
  }

  MapType get _activeMapType {
    switch (_mapViewMode) {
      case _SafeZoneMapViewMode.defaultView:
        return MapType.normal;
      case _SafeZoneMapViewMode.satellite:
        return MapType.satellite;
      case _SafeZoneMapViewMode.terrain:
        return MapType.terrain;
      case _SafeZoneMapViewMode.threeDimensionalLike:
        return MapType.hybrid;
    }
  }

  String _mapViewLabel(_SafeZoneMapViewMode mode) {
    switch (mode) {
      case _SafeZoneMapViewMode.defaultView:
        return 'Default';
      case _SafeZoneMapViewMode.satellite:
        return 'Satellite';
      case _SafeZoneMapViewMode.terrain:
        return 'Terrain';
      case _SafeZoneMapViewMode.threeDimensionalLike:
        return '3D-like';
    }
  }

  Future<void> _setMapViewMode(_SafeZoneMapViewMode nextMode) async {
    if (_mapViewMode == nextMode) {
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[AddSafeZoneScreen] map mode=${nextMode.name} tiltEnabled=${nextMode == _SafeZoneMapViewMode.threeDimensionalLike}',
      );
    }

    setState(() {
      _mapViewMode = nextMode;
    });

    final displayedCenter = _displayedCenter;
    if (_mapController == null || displayedCenter == null) {
      return;
    }

    final cameraPosition = CameraPosition(
      target: displayedCenter,
      zoom: _lastMapZoom,
      tilt: nextMode == _SafeZoneMapViewMode.threeDimensionalLike ? 55 : 0,
      bearing: nextMode == _SafeZoneMapViewMode.threeDimensionalLike ? 35 : 0,
    );

    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(cameraPosition),
    );
  }

  String _formatRecordedAt(int? value) {
    final date = TimestampUtils.toLocalDateTime(value);
    if (date == null) {
      return 'Unknown time';
    }

    return DateFormat('MMM d, HH:mm').format(date);
  }

  Widget _buildCenterSourceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Safe zone center',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _SafeZoneCenterSource.values.map((source) {
                return ChoiceChip(
                  label: Text(_centerSourceLabel(source)),
                  selected: _centerSource == source,
                  onSelected: (_) => _selectCenterSource(source),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (_centerSource == _SafeZoneCenterSource.previousSavedLocation)
              _buildSavedLocationPanel(),
            if (_centerSource == _SafeZoneCenterSource.currentLiveLocation)
              _buildCurrentLiveLocationPanel(),
            if (_centerSource == _SafeZoneCenterSource.customMap)
              _buildCustomLocationPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedLocationPanel() {
    if (_isLoadingSavedLocations) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_savedLocationOptions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _savedLocationError?.isNotEmpty == true
                ? _savedLocationError!
                : 'No previous saved locations are available for this child yet.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadSavedLocations,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh saved locations'),
          ),
        ],
      );
    }

    final selectedValue = _savedLocationOptions.any(
      (option) => option.id == _selectedSavedLocationId,
    )
        ? _selectedSavedLocationId
        : _savedLocationOptions.first.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: selectedValue,
          decoration: const InputDecoration(
            labelText: 'Saved locations',
            prefixIcon: Icon(Icons.history),
          ),
          items: _savedLocationOptions.map((option) {
            return DropdownMenuItem<String>(
              value: option.id,
              child: Text(option.displayLabel),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) {
              return;
            }

            setState(() {
              _selectedSavedLocationId = value;
            });

            final selectedOption = _savedLocationOptions.firstWhere(
              (option) => option.id == value,
            );
            _applySavedLocation(
              selectedOption,
              applyAsSelection: false,
            );
          },
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () {
            final selectedOption = _savedLocationOptions.firstWhere(
              (option) => option.id == selectedValue,
            );
            _applySavedLocation(selectedOption);
          },
          icon: const Icon(Icons.place),
          label: const Text('Use selected saved location'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Picking from this list only previews the location. The center changes after you press the button above and then save.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _loadSavedLocations,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh saved locations'),
        ),
      ],
    );
  }

  Widget _buildCurrentLiveLocationPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.tonalIcon(
          onPressed: _isLoadingLocation
              ? null
              : () => _useCurrentLiveLocation(showFeedback: true),
          icon: const Icon(Icons.gps_fixed),
          label: const Text('Use current live location'),
        ),
        const SizedBox(height: 8),
        Text(
          _liveLocationError?.isNotEmpty == true
              ? _liveLocationError!
              : (_lastLiveLocationAt != null
                  ? 'Latest live update: ${_formatRecordedAt(_lastLiveLocationAt)}. Use the button above if you want to set it as the center.'
                  : 'This shows the latest live location for preview. It only becomes the safe zone center after you choose it and save.'),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildCustomLocationPanel() {
    return const Text(
      'Tap anywhere on the map or drag the marker to place the safe zone center exactly where you want it. The saved center stays unchanged until you press Save or Update.',
      style: TextStyle(color: AppColors.textSecondary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode ? l10n.editSafeZone : l10n.addSafeZone),
        actions: [
          IconButton(
            icon: const Icon(Icons.gps_fixed),
            onPressed: _isLoadingLocation
                ? null
                : () => _useCurrentLiveLocation(showFeedback: true),
            tooltip: 'Use current live location',
          ),
        ],
      ),
      body: Consumer<GeofenceProvider>(
        builder: (context, geofenceProvider, child) {
          final displayedCenter = _displayedCenter;
          return Column(
            children: [
              Expanded(
                flex: 2,
                child: Stack(
                  children: [
                    if (displayedCenter != null)
                      GoogleMap(
                        onMapCreated: (controller) {
                          _mapController = controller;
                          _animateToCenter(displayedCenter);
                        },
                        onCameraMove: (position) {
                          _lastMapZoom = position.zoom;
                        },
                        onTap: _onMapTap,
                        initialCameraPosition: CameraPosition(
                          target: displayedCenter,
                          zoom: 16,
                        ),
                        mapType: _activeMapType,
                        markers: _markers,
                        circles: _circles,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        compassEnabled: true,
                        buildingsEnabled: true,
                        rotateGesturesEnabled: true,
                        tiltGesturesEnabled: true,
                      )
                    else
                      Container(
                        color: Colors.grey[100],
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_off,
                              size: 42,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              l10n.noData,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Choose a live, saved, or custom center to preview the safe zone on the map.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
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
                                  _mapInstructionText(),
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
                      left: 16,
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: PopupMenuButton<_SafeZoneMapViewMode>(
                          tooltip: 'Change map style',
                          initialValue: _mapViewMode,
                          onSelected: _setMapViewMode,
                          itemBuilder: (context) => _SafeZoneMapViewMode.values
                              .map(
                                (mode) => PopupMenuItem<_SafeZoneMapViewMode>(
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
                        _buildCenterSourceCard(),
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
                                      _rebuildMapArtifacts();
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
                                        _rebuildMapArtifacts();
                                      }),
                                    ),
                                    _QuickRadiusChip(
                                      radius: 100,
                                      isSelected: _radius == 100,
                                      onTap: () => setState(() {
                                        _radius = 100;
                                        _rebuildMapArtifacts();
                                      }),
                                    ),
                                    _QuickRadiusChip(
                                      radius: 500,
                                      isSelected: _radius == 500,
                                      onTap: () => setState(() {
                                        _radius = 500;
                                        _rebuildMapArtifacts();
                                      }),
                                    ),
                                    _QuickRadiusChip(
                                      radius: 1000,
                                      isSelected: _radius == 1000,
                                      onTap: () => setState(() {
                                        _radius = 1000;
                                        _rebuildMapArtifacts();
                                      }),
                                    ),
                                    _QuickRadiusChip(
                                      radius: 5000,
                                      isSelected: _radius == 5000,
                                      onTap: () => setState(() {
                                        _radius = 5000;
                                        _rebuildMapArtifacts();
                                      }),
                                    ),
                                    _QuickRadiusChip(
                                      radius: 10000,
                                      isSelected: _radius == 10000,
                                      onTap: () => setState(() {
                                        _radius = 10000;
                                        _rebuildMapArtifacts();
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
                                Text(
                                  'Center source: ${_centerSourceLabel(_centerSource)}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _centerPersistenceStatusText(),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Map view: ${_mapViewLabel(_mapViewMode)}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
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
                                        _displayedCenterText(context),
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

enum _SafeZoneMapViewMode {
  defaultView,
  satellite,
  terrain,
  threeDimensionalLike,
}

enum _SafeZoneCenterSource {
  previousSavedLocation,
  currentLiveLocation,
  customMap,
}

class _SavedLocationOption {
  final String id;
  final double latitude;
  final double longitude;
  final int? recordedAt;
  final double? speed;
  final String label;

  const _SavedLocationOption({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    required this.speed,
    required this.label,
  });

  String get displayLabel {
    final buffer = StringBuffer();
    final date = TimestampUtils.toLocalDateTime(recordedAt);
    if (date != null) {
      buffer.write(DateFormat('MMM d, HH:mm').format(date));
    } else {
      buffer.write('Saved point');
    }

    buffer.write(
        ' - ${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}');

    if (speed != null && speed! > 0) {
      buffer.write(' - ${speed!.toStringAsFixed(1)} m/s');
    }

    if (label.isNotEmpty) {
      buffer.write(' - $label');
    }

    return buffer.toString();
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
