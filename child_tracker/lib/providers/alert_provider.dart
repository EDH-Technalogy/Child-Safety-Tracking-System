import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_model.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/realtime_database_auth_service.dart';
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
  final Map<String, int> _unreadCountsByChild = <String, int>{};

  List<AlertModel> _alerts = [];
  int _unreadCount = 0;
  int _totalUnreadCount = 0;
  bool _isLoading = false;
  String? _error;
  String? _monitoredChildId;
  StreamSubscription<DatabaseEvent>? _liveAlertSubscription;
  StreamSubscription<DatabaseEvent>? _backgroundLiveAlertSubscription;
  String? _liveAlertPath;
  String? _backgroundLiveAlertPath;

  List<AlertModel> get alerts => _alerts;
  int get unreadCount => _unreadCount;
  int get totalUnreadCount => _totalUnreadCount;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isMonitoring => _liveAlertSubscription != null;
  String? get monitoredChildId => _monitoredChildId;

  String _childAlertsPath(String childId) => 'alerts_live/$childId';

  Future<List<AlertModel>> _fetchAlerts(String childId) async {
    final database = await _database();
    final snapshot = await database.ref(_childAlertsPath(childId)).get();
    return _alertsFromRealtimePayload(
      rawValue: snapshot.value,
      childIdFallback: childId,
    );
  }

  int unreadCountForChild(String childId) {
    return _unreadCountsByChild[childId.trim()] ?? 0;
  }

  void _setUnreadCountForChild(String childId, int count) {
    final normalizedChildId = childId.trim();
    if (normalizedChildId.isEmpty) {
      return;
    }

    _unreadCountsByChild[normalizedChildId] = count;
    _totalUnreadCount = _unreadCountsByChild.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
  }

  void _applyAlerts(List<AlertModel> alerts, {String? childId}) {
    _alerts = alerts;
    final normalizedChildId = childId?.trim() ?? '';
    if (normalizedChildId.isNotEmpty) {
      _setUnreadCountForChild(
        normalizedChildId,
        alerts.where((alert) => !alert.isRead).length,
      );
      _unreadCount = unreadCountForChild(normalizedChildId);
    } else {
      _unreadCount = alerts.where((alert) => !alert.isRead).length;
      _totalUnreadCount = _unreadCount;
    }
  }

  void _applyAggregateAlerts(List<AlertModel> alerts) {
    final nextCounts = <String, int>{};
    for (final alert in alerts) {
      if (alert.isRead || alert.childId.isEmpty) {
        continue;
      }
      nextCounts[alert.childId] = (nextCounts[alert.childId] ?? 0) + 1;
    }

    _unreadCountsByChild
      ..clear()
      ..addAll(nextCounts);
    _totalUnreadCount = nextCounts.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final childId = _monitoredChildId;
    _unreadCount =
        childId == null ? _totalUnreadCount : unreadCountForChild(childId);
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
      _applyAlerts(alerts, childId: childId);
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
      final normalizedChildId = childId.trim();
      if (normalizedChildId.isNotEmpty &&
          normalizedChildId == _monitoredChildId) {
        _setUnreadCountForChild(
          normalizedChildId,
          _alerts.where((alert) => !alert.isRead).length,
        );
      } else {
        final alerts = await _fetchAlerts(normalizedChildId);
        _setUnreadCountForChild(
          normalizedChildId,
          alerts.where((alert) => !alert.isRead).length,
        );
      }
      _unreadCount = unreadCountForChild(normalizedChildId);
      notifyListeners();
      return true;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> _reloadForegroundMonitoring() async {
    final childId = _monitoredChildId;
    if (childId == null) {
      return;
    }

    await loadAlerts(childId, showLoader: false);
    if (_error == null) {
      await _ensureForegroundLiveAlertListener();
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
      clearAlerts();
      return;
    }

    unawaited(_reloadForegroundMonitoring());
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
    if (_monitoredChildId == null) {
      _unreadCountsByChild.clear();
      _totalUnreadCount = 0;
      _unreadCount = 0;
      notifyListeners();
    }

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
    await RealtimeDatabaseAuthService.ensureSignedIn();
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
    final childId = _monitoredChildId?.trim() ?? '';
    if (childId.isEmpty) {
      return;
    }

    final path = _childAlertsPath(childId);
    if (_liveAlertSubscription != null && _liveAlertPath == path) {
      return;
    }

    await _stopLiveAlertListener();

    try {
      final database = await _database();
      final ref = database.ref(path);
      _liveAlertPath = path;
      _knownAlertIds
        ..clear()
        ..addAll(
          _alerts
              .where((alert) => alert.childId == childId)
              .map((alert) => alert.id),
        );

      debugPrint(
        '[AlertProvider.live] listening childId=$childId rtdbPath=/$path',
      );

      _liveAlertSubscription = ref.onValue.listen(
        (event) {
          final previousIds = Set<String>.from(_knownAlertIds);
          final alerts = _alertsFromRealtimePayload(
            rawValue: event.snapshot.value,
            childIdFallback: childId,
          );
          final newAlerts =
              alerts.where((alert) => !previousIds.contains(alert.id)).toList();

          _knownAlertIds
            ..clear()
            ..addAll(alerts.map((alert) => alert.id));
          _applyAlerts(alerts, childId: childId);
          notifyListeners();

          for (final alert in newAlerts) {
            debugPrint(
              '[AlertProvider.live] received alert=${alert.id} type=${alert.type} child=${alert.childId}',
            );
            unawaited(_handleRealtimeAlert(alert, playSound: true));
          }
        },
        onError: (error) {
          debugPrint(
            '[AlertProvider.live] listener error path=/$path error=$error',
          );
        },
      );
    } catch (error) {
      debugPrint('[AlertProvider.live] failed path=/$path error=$error');
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

      _backgroundLiveAlertSubscription = ref.onValue.listen(
        (event) {
          final activeChildIds = _backgroundMonitorOwners.values
              .expand((childSet) => childSet)
              .toSet();
          final previousIds = Set<String>.from(_backgroundKnownAlertIds);
          final alerts = _alertsFromRealtimePayload(
            rawValue: event.snapshot.value,
            childIdFallback: '',
          ).where((alert) {
            if (activeChildIds.isEmpty || alert.childId.isEmpty) {
              return true;
            }
            return activeChildIds.contains(alert.childId);
          }).toList();
          final newAlerts =
              alerts.where((alert) => !previousIds.contains(alert.id)).toList();

          _backgroundKnownAlertIds
            ..clear()
            ..addAll(alerts.map((alert) => alert.id));
          _applyAggregateAlerts(alerts);
          notifyListeners();

          for (final alert in newAlerts) {
            debugPrint(
              '[AlertProvider.background] received alert=${alert.id} type=${alert.type} child=${alert.childId}',
            );
            unawaited(_handleRealtimeAlert(alert, playSound: !scope.isAdmin));
          }
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
    String? childIdFallback,
  }) {
    final data = _asMap(rawValue);
    if (data.isEmpty) {
      return null;
    }

    final createdAt = _parseInt(data['created_at']) > 0
        ? _parseInt(data['created_at'])
        : _parseInt(data['timestamp']);
    final rawType = (data['type'] ?? '').toString().trim();
    final type = rawType.isNotEmpty ? rawType : 'SOS';
    if (createdAt <= 0) {
      return null;
    }

    final alertId =
        (data['alert_id'] ?? data['id'] ?? rawKey ?? '$type:$createdAt')
            .toString();
    final isRead = data['is_read'] == true || data['isRead'] == true;
    final status =
        (data['status'] ?? (isRead ? 'read' : 'unread')).toString().trim();

    return AlertModel.fromJson({
      'id': alertId,
      'child_id': (data['child_id'] ?? childIdFallback ?? '').toString(),
      'child_name': (data['child_name'] ?? '').toString(),
      'type': type,
      'message': (data['message'] ?? '').toString(),
      'created_at': createdAt,
      'status': status,
      'is_read': isRead,
      'zone_name': data['zone_name'],
      'location_text': data['location_text'],
      'latitude': data['latitude'],
      'longitude': data['longitude'],
    });
  }

  List<AlertModel> _alertsFromRealtimePayload({
    required Object? rawValue,
    String? childIdFallback,
  }) {
    final data = _asMap(rawValue);
    final alerts = data.entries
        .map(
          (entry) => _alertFromLivePayload(
            rawKey: entry.key,
            rawValue: entry.value,
            childIdFallback: childIdFallback,
          ),
        )
        .whereType<AlertModel>()
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return alerts;
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
      case 'SOS':
      case 'OUT_ZONE':
      case 'SAFE_ZONE_EXIT':
      case 'ZONE_EXIT':
      case 'IN_ZONE':
      case 'SAFE_ZONE_ENTER':
      case 'ZONE_ENTER':
        return true;
      default:
        return false;
    }
  }

  Future<void> _handleRealtimeAlert(
    AlertModel alert, {
    required bool playSound,
  }) async {
    if (!playSound) {
      debugPrint(
        '[AlertProvider.monitor] sound skipped alert=${alert.id} reason=playback_disabled',
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

    final type = alert.type.trim().toUpperCase();
    final payload = 'alert:${alert.childId}:${alert.id}';

    if (type == 'SOS') {
      await _notificationService.sendSosAlert(
        alertId: alert.id,
        childName: alert.childName,
        body: alert.message,
        payload: payload,
      );
      return;
    }

    if (type == 'IN_ZONE' ||
        type == 'SAFE_ZONE_ENTER' ||
        type == 'ZONE_ENTER') {
      await _notificationService.sendSafeZoneEnterAlert(
        alertId: alert.id,
        childName: alert.childName,
        body: alert.message,
        payload: payload,
      );
      return;
    }

    await _notificationService.sendSafeZoneExitAlert(
      alertId: alert.id,
      childName: alert.childName,
      body: alert.message,
      payload: payload,
    );
  }

  Future<bool> markAsRead(String alertId, String childId) async {
    try {
      await _apiService.markAlertAsRead(alertId, childId: childId);
      await loadAlerts(childId);
      await getUnreadCount(childId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> markAllAsRead(String childId) async {
    try {
      await _apiService.markAllAlertsAsRead(childId);
      await loadAlerts(childId);
      await getUnreadCount(childId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteAlert(String alertId, String childId) async {
    final previousAlerts = List<AlertModel>.from(_alerts);
    try {
      final normalizedChildId = childId.trim();
      if (normalizedChildId.isNotEmpty) {
        _alerts = _alerts.where((alert) => alert.id != alertId).toList();
        _setUnreadCountForChild(
          normalizedChildId,
          _alerts
              .where((alert) =>
                  alert.childId == normalizedChildId && !alert.isRead)
              .length,
        );
        _unreadCount = unreadCountForChild(normalizedChildId);
        notifyListeners();
      }

      await _apiService.deleteAlert(alertId, childId: childId);
      await loadAlerts(childId, showLoader: false);
      return true;
    } catch (e) {
      _alerts = previousAlerts;
      _setUnreadCountForChild(
        childId,
        previousAlerts.where((alert) => !alert.isRead).length,
      );
      _unreadCount = unreadCountForChild(childId);
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearAlerts() {
    _alerts = [];
    final childId = _monitoredChildId;
    _unreadCount =
        childId == null ? _totalUnreadCount : unreadCountForChild(childId);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopLiveAlertListener();
    _backgroundLiveAlertSubscription?.cancel();
    super.dispose();
  }
}
