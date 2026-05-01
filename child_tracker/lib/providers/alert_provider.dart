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
  final Set<String> _rootSosAlertIds = <String>{};
  final Map<String, int> _unreadCountsByChild = <String, int>{};

  List<AlertModel> _alerts = [];
  int _unreadCount = 0;
  int _totalUnreadCount = 0;
  bool _isLoading = false;
  String? _error;
  String? _monitoredChildId;
  StreamSubscription<DatabaseEvent>? _liveAlertSubscription;
  StreamSubscription<DatabaseEvent>? _backgroundLiveAlertSubscription;
  StreamSubscription<DatabaseEvent>? _liveAlertChangedSubscription;
  StreamSubscription<DatabaseEvent>? _liveAlertRemovedSubscription;
  StreamSubscription<DatabaseEvent>? _sosRootAlertSubscription;
  StreamSubscription<DatabaseEvent>? _sosRootAlertChangedSubscription;
  StreamSubscription<DatabaseEvent>? _sosRootAlertRemovedSubscription;
  String? _liveAlertPath;
  String? _backgroundLiveAlertPath;
  String? _sosRootListeningChildId;
  int _sosRootListenerStartedAt = 0;

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
    final childAlerts = _alertsFromRealtimePayload(
      rawValue: snapshot.value,
      childIdFallback: childId,
    );
    final rootSosAlerts = await _fetchRootSosAlertsForChild(
      database,
      childId,
    );

    return _mergeAndSortAlerts([
      ...rootSosAlerts,
      ...childAlerts,
    ]);
  }

  Future<List<AlertModel>> _fetchRootSosAlertsForChild(
    FirebaseDatabase database,
    String childId,
  ) async {
    final normalizedChildId = childId.trim();

    try {
      final snapshot = await database.ref('alerts_live').get();
      final data = _asMap(snapshot.value);
      final alerts = <AlertModel>[];

      for (final entry in data.entries) {
        final alertData = _asMap(entry.value);
        if (!_looksLikeSingleAlertPayload(alertData)) {
          continue;
        }

        final alert = _alertFromLivePayload(
          rawKey: entry.key,
          rawValue: entry.value,
          childIdFallback: normalizedChildId,
        );

        if (alert == null) {
          continue;
        }

        _rootSosAlertIds.add(alert.id);
        alerts.add(alert);
      }

      return alerts;
    } catch (error) {
      debugPrint('[AlertProvider.sos] root fetch skipped: $error');
      return const <AlertModel>[];
    }
  }

  List<AlertModel> _mergeAndSortAlerts(Iterable<AlertModel> alerts) {
    final alertsById = <String, AlertModel>{};
    for (final alert in alerts) {
      if (alert.id.trim().isEmpty) {
        continue;
      }

      alertsById[alert.id] = alert;
    }

    return alertsById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
      await _ensureRootSosAlertListener(childId);
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
        '[AlertProvider.live] listening to alerts_live for childId=$childId',
      );

      // Use onChildAdded for real-time new alerts
      _liveAlertSubscription = ref.onChildAdded.listen(
        (event) {
          debugPrint('🚨 NEW SOS ALERT DETECTED: ${event.snapshot.key}');
          final alert = _alertFromLivePayload(
            rawKey: event.snapshot.key,
            rawValue: event.snapshot.value,
            childIdFallback: childId,
          );

          if (alert == null || alert.childId != childId) {
            debugPrint(
                '[AlertProvider.live] alert ignored - childId mismatch or null');
            return;
          }

          if (_knownAlertIds.contains(alert.id)) {
            debugPrint('[AlertProvider.live] alert ignored - duplicate');
            return;
          }

          debugPrint(
            '[AlertProvider.live] received alert=${alert.id} type=${alert.type} child=${alert.childId}',
          );

          _knownAlertIds.add(alert.id);
          _alerts.insert(0, alert); // Add to beginning for newest first
          _applyAlerts(_alerts, childId: childId);
          notifyListeners();

          unawaited(_handleRealtimeAlert(alert, playSound: true));
        },
        onError: (error) {
          debugPrint(
            '[AlertProvider.live] listener error path=/$path error=$error',
          );
        },
      );

      // Also listen to onChildChanged for updates (mark-as-read, etc.)
      _liveAlertChangedSubscription = ref.onChildChanged.listen(
        (event) {
          debugPrint('🔄 ALERT UPDATED: ${event.snapshot.key}');
          final alert = _alertFromLivePayload(
            rawKey: event.snapshot.key,
            rawValue: event.snapshot.value,
            childIdFallback: childId,
          );

          if (alert == null || alert.childId != childId) {
            return;
          }

          final index = _alerts.indexWhere((a) => a.id == alert.id);
          if (index != -1) {
            _alerts[index] = alert;
            _applyAlerts(_alerts, childId: childId);
            notifyListeners();
          }
        },
        onError: (error) {
          debugPrint('[AlertProvider.live] update error: $error');
        },
      );

      // Also listen to onChildRemoved for deletions
      _liveAlertRemovedSubscription = ref.onChildRemoved.listen(
        (event) {
          debugPrint('🗑️ ALERT DELETED: ${event.snapshot.key}');
          _alerts.removeWhere((alert) => alert.id == event.snapshot.key);
          _knownAlertIds.remove(event.snapshot.key);
          _applyAlerts(_alerts, childId: childId);
          notifyListeners();
        },
        onError: (error) {
          debugPrint('[AlertProvider.live] delete error: $error');
        },
      );

      await _ensureRootSosAlertListener(childId);
    } catch (error) {
      debugPrint('[AlertProvider.live] failed path=/$path error=$error');
    }
  }

  Future<void> _ensureRootSosAlertListener(String childId) async {
    final normalizedChildId = childId.trim();
    if (normalizedChildId.isEmpty) {
      return;
    }

    if (_sosRootAlertSubscription != null &&
        _sosRootListeningChildId == normalizedChildId) {
      return;
    }

    await _stopRootSosAlertListener();

    try {
      final database = await _database();
      final ref = database.ref('alerts_live');
      _sosRootListeningChildId = normalizedChildId;
      _sosRootListenerStartedAt = DateTime.now().millisecondsSinceEpoch;

      debugPrint('[AlertProvider.sos] Listening to SOS alerts...');

      _sosRootAlertSubscription = ref.onChildAdded.listen(
        (event) => _handleRootSosEvent(
          event,
          normalizedChildId,
          isNewEvent: true,
        ),
        onError: (error) {
          debugPrint('[AlertProvider.sos] listener error: $error');
        },
      );

      _sosRootAlertChangedSubscription = ref.onChildChanged.listen(
        (event) => _handleRootSosEvent(
          event,
          normalizedChildId,
          isNewEvent: false,
        ),
        onError: (error) {
          debugPrint('[AlertProvider.sos] update error: $error');
        },
      );

      _sosRootAlertRemovedSubscription = ref.onChildRemoved.listen(
        (event) {
          final alertId = event.snapshot.key;
          if (alertId == null) {
            return;
          }

          _alerts.removeWhere((alert) => alert.id == alertId);
          _knownAlertIds.remove(alertId);
          _rootSosAlertIds.remove(alertId);
          _applyAlerts(_alerts, childId: normalizedChildId);
          notifyListeners();
        },
        onError: (error) {
          debugPrint('[AlertProvider.sos] delete error: $error');
        },
      );
    } catch (error) {
      debugPrint('[AlertProvider.sos] failed path=/alerts_live error=$error');
    }
  }

  void _handleRootSosEvent(
    DatabaseEvent event,
    String childId, {
    required bool isNewEvent,
  }) {
    final data = _asMap(event.snapshot.value);
    if (!_looksLikeSingleAlertPayload(data)) {
      return;
    }

    final alert = _alertFromLivePayload(
      rawKey: event.snapshot.key,
      rawValue: event.snapshot.value,
      childIdFallback: childId,
    );

    if (alert == null) {
      return;
    }

    final index = _alerts.indexWhere((item) => item.id == alert.id);
    final alreadyKnown = _knownAlertIds.contains(alert.id);

    if (index == -1) {
      _alerts.insert(0, alert);
    } else {
      _alerts[index] = alert;
    }

    _alerts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _knownAlertIds.add(alert.id);
    _rootSosAlertIds.add(alert.id);
    _applyAlerts(_alerts, childId: childId);
    notifyListeners();

    final shouldPlaySound = isNewEvent &&
        !alreadyKnown &&
        alert.createdAt >= _sosRootListenerStartedAt - 5000;
    if (shouldPlaySound) {
      debugPrint('[AlertProvider.sos] SOS received: ${alert.message}');
      unawaited(_handleRealtimeAlert(alert, playSound: true));
    }
  }

  bool _looksLikeSingleAlertPayload(Map<String, dynamic> data) {
    if (data.isEmpty) {
      return false;
    }

    return data.containsKey('message') ||
        data.containsKey('timestamp') ||
        data.containsKey('created_at') ||
        data.containsKey('isRead') ||
        data.containsKey('is_read');
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
    await _liveAlertChangedSubscription?.cancel();
    await _liveAlertRemovedSubscription?.cancel();
    await _stopRootSosAlertListener();
    _liveAlertSubscription = null;
    _liveAlertChangedSubscription = null;
    _liveAlertRemovedSubscription = null;
    _liveAlertPath = null;
  }

  Future<void> _stopRootSosAlertListener() async {
    await _sosRootAlertSubscription?.cancel();
    await _sosRootAlertChangedSubscription?.cancel();
    await _sosRootAlertRemovedSubscription?.cancel();
    _sosRootAlertSubscription = null;
    _sosRootAlertChangedSubscription = null;
    _sosRootAlertRemovedSubscription = null;
    _sosRootListeningChildId = null;
    _sosRootListenerStartedAt = 0;
    _rootSosAlertIds.clear();
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

  AlertModel _withReadStatus(AlertModel alert, bool isRead) {
    return AlertModel.fromJson({
      ...alert.toJson(),
      'is_read': isRead,
      'isRead': isRead,
      'status': isRead ? 'read' : 'unread',
    });
  }

  void _markLocalAlertAsRead(String alertId, String childId) {
    final normalizedChildId = childId.trim();
    _alerts = _alerts
        .map(
          (alert) => alert.id == alertId ? _withReadStatus(alert, true) : alert,
        )
        .toList();
    _applyAlerts(_alerts, childId: normalizedChildId);
    notifyListeners();
  }

  void _markLocalAlertsAsRead(String childId) {
    final normalizedChildId = childId.trim();
    _alerts = _alerts.map((alert) {
      if (normalizedChildId.isNotEmpty &&
          alert.childId.isNotEmpty &&
          alert.childId != normalizedChildId) {
        return alert;
      }

      return _withReadStatus(alert, true);
    }).toList();
    _applyAlerts(_alerts, childId: normalizedChildId);
    notifyListeners();
  }

  Future<bool> _markRootSosAlertAsRead(String alertId) async {
    if (!_rootSosAlertIds.contains(alertId)) {
      return false;
    }

    try {
      final database = await _database();
      await database.ref('alerts_live/$alertId').update({
        'isRead': true,
        'is_read': true,
        'status': 'read',
      });
      return true;
    } catch (error) {
      debugPrint('[AlertProvider.sos] direct read update skipped: $error');
      return false;
    }
  }

  Future<bool> _markAllRootSosAlertsAsRead() async {
    final updates = <String, Object?>{};
    for (final alert in _alerts) {
      if (alert.isRead || !_rootSosAlertIds.contains(alert.id)) {
        continue;
      }

      updates['alerts_live/${alert.id}/isRead'] = true;
      updates['alerts_live/${alert.id}/is_read'] = true;
      updates['alerts_live/${alert.id}/status'] = 'read';
    }

    if (updates.isEmpty) {
      return false;
    }

    try {
      final database = await _database();
      await database.ref().update(updates);
      return true;
    } catch (error) {
      debugPrint('[AlertProvider.sos] direct read-all update skipped: $error');
      return false;
    }
  }

  Future<bool> _deleteRootSosAlert(String alertId) async {
    if (!_rootSosAlertIds.contains(alertId)) {
      return false;
    }

    try {
      final database = await _database();
      await database.ref('alerts_live/$alertId').remove();
      _rootSosAlertIds.remove(alertId);
      return true;
    } catch (error) {
      debugPrint('[AlertProvider.sos] direct delete skipped: $error');
      return false;
    }
  }

  Future<bool> markAsRead(String alertId, String childId) async {
    try {
      if (_rootSosAlertIds.contains(alertId)) {
        final rootUpdated = await _markRootSosAlertAsRead(alertId);
        if (!rootUpdated) {
          throw Exception('Failed to mark alert as read');
        }

        _markLocalAlertAsRead(alertId, childId);
        return true;
      }

      Object? apiError;
      var backendUpdated = false;
      try {
        await _apiService.markAlertAsRead(alertId, childId: childId);
        backendUpdated = true;
      } catch (error) {
        apiError = error;
      }

      final rootUpdated = await _markRootSosAlertAsRead(alertId);
      if (!backendUpdated && !rootUpdated) {
        throw apiError ?? Exception('Failed to mark alert as read');
      }

      _markLocalAlertAsRead(alertId, childId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> markAllAsRead(String childId) async {
    try {
      final hasNonRootAlerts = _alerts.any(
        (alert) => !_rootSosAlertIds.contains(alert.id),
      );
      Object? apiError;
      var backendUpdated = false;
      if (hasNonRootAlerts) {
        try {
          await _apiService.markAllAlertsAsRead(childId);
          backendUpdated = true;
        } catch (error) {
          apiError = error;
        }
      }

      final rootUpdated = await _markAllRootSosAlertsAsRead();
      if (hasNonRootAlerts && !backendUpdated && !rootUpdated) {
        throw apiError ?? Exception('Failed to mark alerts as read');
      }

      _markLocalAlertsAsRead(childId);
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
        // Optimistic UI removal
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

      if (_rootSosAlertIds.contains(alertId)) {
        final rootDeleted = await _deleteRootSosAlert(alertId);
        if (!rootDeleted) {
          throw Exception('Failed to delete alert');
        }
      } else {
        await _apiService.deleteAlert(alertId, childId: childId);
      }
      _rootSosAlertIds.remove(alertId);

      // The RTDB listener fires when the backend removes the alert from
      // alerts_live/{childId}/{alertId}, which automatically updates local
      // state. Calling loadAlerts() here would cause a redundant rebuild
      // and a second network fetch.
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
