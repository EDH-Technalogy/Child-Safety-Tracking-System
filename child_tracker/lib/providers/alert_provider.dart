import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_model.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';
import '../utils/firebase_bootstrap.dart';

class _LiveAlertScope {
  final String path;
  final String role;
  final String userId;

  const _LiveAlertScope({
    required this.path,
    required this.role,
    required this.userId,
  });

  bool get isAdmin => role == 'admin';
}

class AlertProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final NotificationService _notificationService = NotificationService();

  final Map<String, String> _monitorOwners = <String, String>{};
  final Map<String, Set<String>> _backgroundMonitorOwners =
      <String, Set<String>>{};
  final Set<String> _knownAlertIds = <String>{};
  final Set<String> _backgroundKnownAlertIds = <String>{};
  final Set<String> _handledAlertIds = <String>{};

  List<AlertModel> _alerts = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  String? _error;
  String? _monitoredChildId;
  StreamSubscription<DatabaseEvent>? _liveAlertSubscription;
  StreamSubscription<DatabaseEvent>? _backgroundLiveAlertSubscription;
  String? _liveAlertPath;
  String? _backgroundLiveAlertPath;

  List<AlertModel> get alerts => _alerts;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isMonitoring => _liveAlertSubscription != null;
  String? get monitoredChildId => _monitoredChildId;

  Future<List<AlertModel>> _fetchAlerts(String childId) async {
    final response = await _apiService.getAlerts(childId);
    final alerts = response
        .map((json) => AlertModel.fromJson(json))
        .toList(growable: false);
    alerts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return alerts;
  }

  void _applyAlerts(List<AlertModel> alerts) {
    _alerts = alerts;
    _unreadCount = alerts.where((alert) => !alert.isRead).length;
  }

  Future<bool> loadAlerts(
    String childId, {
    bool showLoader = true,
  }) async {
    if (showLoader) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    } else {
      _error = null;
    }

    try {
      final alerts = await _fetchAlerts(childId);
      _applyAlerts(alerts);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (error) {
      _isLoading = false;
      _error = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> getUnreadCount(String childId) async {
    try {
      final response = await _apiService.getUnreadAlertsCount(childId);
      _unreadCount = response['count'] ?? 0;
      notifyListeners();
      return true;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> startMonitoring(
    String childId, {
    required String ownerId,
  }) async {
    final normalizedChildId = childId.trim();
    if (normalizedChildId.isEmpty) {
      return;
    }

    _monitorOwners[ownerId] = normalizedChildId;
    _monitoredChildId =
        _monitorOwners.values.isEmpty ? null : _monitorOwners.values.last;

    await _notificationService.init();
    debugPrint(
      '[AlertProvider.monitor] start owner=$ownerId childId=$_monitoredChildId owners=${_monitorOwners.length}',
    );

    if (_monitoredChildId != null) {
      await loadAlerts(_monitoredChildId!, showLoader: _alerts.isEmpty);
      if (_error == null) {
        await _ensureForegroundLiveAlertListener();
      }
    }
  }

  void stopMonitoring({required String ownerId}) {
    _monitorOwners.remove(ownerId);
    final nextChildId =
        _monitorOwners.values.isEmpty ? null : _monitorOwners.values.last;

    debugPrint(
      '[AlertProvider.monitor] stop owner=$ownerId remaining=${_monitorOwners.length} nextChild=$nextChildId',
    );

    _monitoredChildId = nextChildId;
    if (_monitoredChildId == null) {
      unawaited(_stopLiveAlertListener());
      _knownAlertIds.clear();
    }
  }

  Future<void> syncBackgroundMonitoring({
    required String ownerId,
    required Iterable<String> childIds,
  }) async {
    final normalizedChildIds = childIds
        .map((childId) => childId.trim())
        .where((childId) => childId.isNotEmpty)
        .toSet();

    if (normalizedChildIds.isEmpty) {
      await stopBackgroundMonitoring(ownerId: ownerId);
      return;
    }

    _backgroundMonitorOwners[ownerId] = normalizedChildIds;
    await _notificationService.init();
    await _ensureBackgroundLiveAlertListener();

    final activeChildIds =
        _backgroundMonitorOwners.values.expand((childSet) => childSet).toSet();
    debugPrint(
      '[AlertProvider.background] sync owner=$ownerId childIds=${activeChildIds.join(",")} listeners=${_backgroundLiveAlertSubscription == null ? 0 : 1}',
    );
  }

  Future<void> stopBackgroundMonitoring({required String ownerId}) async {
    _backgroundMonitorOwners.remove(ownerId);
    if (_backgroundMonitorOwners.isNotEmpty) {
      return;
    }

    await _backgroundLiveAlertSubscription?.cancel();
    _backgroundLiveAlertSubscription = null;
    _backgroundLiveAlertPath = null;
    _backgroundKnownAlertIds.clear();

    debugPrint('[AlertProvider.background] stop owner=$ownerId remaining=0');
  }

  Future<_LiveAlertScope?> _resolveLiveAlertScope() async {
    final prefs = await SharedPreferences.getInstance();
    final role =
        (prefs.getString(AppConstants.userRoleKey) ?? '').trim().toLowerCase();
    final userId = (prefs.getString(AppConstants.userIdKey) ?? '').trim();

    if (role == 'admin') {
      return const _LiveAlertScope(
        path: 'admin_alerts',
        role: 'admin',
        userId: 'admin',
      );
    }

    if (userId.isEmpty) {
      return null;
    }

    return _LiveAlertScope(
      path: 'alerts/$userId',
      role: 'user',
      userId: userId,
    );
  }

  Future<FirebaseDatabase> _database() async {
    await FirebaseBootstrap.ensureInitialized();
    return FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: AppConstants.firebaseDatabaseUrl,
    );
  }

  Future<void> _primeKnownAlertIds(
    DatabaseReference ref,
    Set<String> knownIds, {
    required String label,
  }) async {
    final snapshot = await ref.get();
    final data = _asMap(snapshot.value);
    for (final entry in data.entries) {
      final candidate = _alertFromLivePayload(
        rawKey: entry.key,
        rawValue: entry.value,
      );
      if (candidate != null) {
        knownIds.add(candidate.id);
      }
    }

    debugPrint(
      '[AlertProvider.$label] primed path=/${ref.path} known=${knownIds.length}',
    );
  }

  Future<void> _ensureForegroundLiveAlertListener() async {
    final scope = await _resolveLiveAlertScope();
    if (scope == null) {
      return;
    }

    if (_liveAlertSubscription != null && _liveAlertPath == scope.path) {
      return;
    }

    await _stopLiveAlertListener();

    try {
      final database = await _database();
      final ref = database.ref(scope.path);
      _liveAlertPath = scope.path;
      _knownAlertIds.clear();
      await _primeKnownAlertIds(ref, _knownAlertIds, label: 'live');

      debugPrint(
        '[AlertProvider.live] listening role=${scope.role} userId=${scope.userId} rtdbPath=/${scope.path}',
      );

      _liveAlertSubscription = ref.onChildAdded.listen(
        (event) {
          final alert = _alertFromLivePayload(
            rawKey: event.snapshot.key,
            rawValue: event.snapshot.value,
          );
          if (alert == null) {
            return;
          }

          if (!_knownAlertIds.add(alert.id)) {
            debugPrint(
              '[AlertProvider.live] skipped duplicate alert=${alert.id}',
            );
            return;
          }

          debugPrint(
            '[AlertProvider.live] received alert=${alert.id} type=${alert.type} child=${alert.childId}',
          );
          unawaited(_handleRealtimeAlert(alert, scope: scope, refreshList: true));
        },
        onError: (error) {
          debugPrint(
            '[AlertProvider.live] listener error path=/${scope.path} error=$error',
          );
        },
      );
    } catch (error) {
      debugPrint('[AlertProvider.live] failed path=/${scope.path} error=$error');
    }
  }

  Future<void> _ensureBackgroundLiveAlertListener() async {
    final scope = await _resolveLiveAlertScope();
    if (scope == null) {
      return;
    }

    if (_backgroundLiveAlertSubscription != null &&
        _backgroundLiveAlertPath == scope.path) {
      return;
    }

    await _backgroundLiveAlertSubscription?.cancel();
    _backgroundLiveAlertSubscription = null;
    _backgroundLiveAlertPath = null;
    _backgroundKnownAlertIds.clear();

    try {
      final database = await _database();
      final ref = database.ref(scope.path);
      _backgroundLiveAlertPath = scope.path;
      await _primeKnownAlertIds(
        ref,
        _backgroundKnownAlertIds,
        label: 'background',
      );

      debugPrint(
        '[AlertProvider.background] listening role=${scope.role} userId=${scope.userId} rtdbPath=/${scope.path}',
      );

      _backgroundLiveAlertSubscription = ref.onChildAdded.listen(
        (event) {
          final alert = _alertFromLivePayload(
            rawKey: event.snapshot.key,
            rawValue: event.snapshot.value,
          );
          if (alert == null) {
            return;
          }

          if (!_backgroundKnownAlertIds.add(alert.id)) {
            debugPrint(
              '[AlertProvider.background] skipped duplicate alert=${alert.id}',
            );
            return;
          }

          debugPrint(
            '[AlertProvider.background] received alert=${alert.id} type=${alert.type} child=${alert.childId}',
          );
          unawaited(
            _handleRealtimeAlert(
              alert,
              scope: scope,
              refreshList: false,
            ),
          );
        },
        onError: (error) {
          debugPrint(
            '[AlertProvider.background] listener error path=/${scope.path} error=$error',
          );
        },
      );
    } catch (error) {
      debugPrint(
        '[AlertProvider.background] failed path=/${scope.path} error=$error',
      );
    }
  }

  Future<void> _stopLiveAlertListener() async {
    await _liveAlertSubscription?.cancel();
    _liveAlertSubscription = null;
    _liveAlertPath = null;
  }

  AlertModel? _alertFromLivePayload({
    required String? rawKey,
    required Object? rawValue,
  }) {
    final data = _asMap(rawValue);
    if (data.isEmpty) {
      return null;
    }

    final createdAt = _parseInt(data['created_at']);
    final type = (data['type'] ?? '').toString().trim();
    if (type.isEmpty || createdAt <= 0) {
      return null;
    }

    final alertId =
        (data['alert_id'] ?? data['id'] ?? rawKey ?? '$type:$createdAt')
            .toString();

    return AlertModel.fromJson({
      'id': alertId,
      'child_id': (data['child_id'] ?? '').toString(),
      'child_name': (data['child_name'] ?? '').toString(),
      'type': type,
      'message': (data['message'] ?? '').toString(),
      'created_at': createdAt,
      'status': (data['status'] ?? 'unread').toString(),
      'zone_name': data['zone_name'],
      'location_text': data['location_text'],
      'latitude': data['latitude'],
      'longitude': data['longitude'],
    });
  }

  Map<String, dynamic> _asMap(Object? rawValue) {
    if (rawValue is Map<String, dynamic>) {
      return rawValue;
    }

    if (rawValue is Map) {
      return rawValue.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    return const <String, dynamic>{};
  }

  int _parseInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.round();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _isAudibleAlert(AlertModel alert) {
    switch (alert.type.trim().toUpperCase()) {
      case 'OUT_ZONE':
      case 'SAFE_ZONE_EXIT':
      case 'ZONE_EXIT':
        return true;
      default:
        return false;
    }
  }

  Future<void> _handleRealtimeAlert(
    AlertModel alert, {
    required _LiveAlertScope scope,
    required bool refreshList,
  }) async {
    if (refreshList &&
        _monitoredChildId != null &&
        _monitoredChildId == alert.childId) {
      await loadAlerts(alert.childId, showLoader: false);
    }

    if (scope.isAdmin) {
      debugPrint(
        '[AlertProvider.monitor] sound skipped alert=${alert.id} reason=admin_scope',
      );
      return;
    }

    if (!_handledAlertIds.add(alert.id)) {
      debugPrint(
        '[AlertProvider.monitor] sound skipped alert=${alert.id} reason=already_handled',
      );
      return;
    }

    if (!_isAudibleAlert(alert)) {
      debugPrint(
        '[AlertProvider.monitor] sound skipped alert=${alert.id} reason=type_not_audible',
      );
      return;
    }

    final fallbackBody = alert.message.trim().isNotEmpty
        ? alert.message.trim()
        : 'A child moved outside the configured safe zone.';

    await _notificationService.sendSafeZoneExitAlert(
      alertId: alert.id,
      childName: alert.childName.isNotEmpty ? alert.childName : null,
      body: fallbackBody,
      payload: alert.childId,
    );

    debugPrint(
      '[AlertProvider.monitor] sound played alert=${alert.id} type=${alert.type}',
    );
  }

  Future<bool> markAsRead(String alertId, String childId) async {
    try {
      await _apiService.markAlertAsRead(alertId);
      await loadAlerts(childId, showLoader: false);
      await getUnreadCount(childId);
      return true;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> markAllAsRead(String childId) async {
    try {
      await _apiService.markAllAlertsAsRead(childId);
      await loadAlerts(childId, showLoader: false);
      await getUnreadCount(childId);
      return true;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return false;
    }
  }

  void clearAlerts() {
    _alerts = [];
    _unreadCount = 0;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_stopLiveAlertListener());
    unawaited(_backgroundLiveAlertSubscription?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}
