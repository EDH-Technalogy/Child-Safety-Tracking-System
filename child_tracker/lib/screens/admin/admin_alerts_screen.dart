import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../../services/admin_api_service.dart';
import '../../services/realtime_database_auth_service.dart';
import '../../utils/constants.dart';
import '../../utils/firebase_bootstrap.dart';
import '../../utils/localization_helpers.dart';
import '../../utils/timestamp_utils.dart';
import '../../widgets/admin_drawer.dart';

class AdminAlertsScreen extends StatefulWidget {
  const AdminAlertsScreen({super.key});

  @override
  State<AdminAlertsScreen> createState() => _AdminAlertsScreenState();
}

class _AdminAlertsScreenState extends State<AdminAlertsScreen> {
  final AdminApiService _adminApi = AdminApiService();
  List<dynamic> _alerts = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription<DatabaseEvent>? _alertsSubscription;

  @override
  void initState() {
    super.initState();
    _startRealtimeAlerts();
  }

  @override
  void dispose() {
    unawaited(_alertsSubscription?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  Future<FirebaseDatabase> _database() async {
    await FirebaseBootstrap.ensureInitialized();
    await RealtimeDatabaseAuthService.ensureSignedIn();
    return FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: AppConstants.firebaseDatabaseUrl,
    );
  }

  Map<String, dynamic> _asMap(Object? rawValue) {
    if (rawValue is Map<String, dynamic>) {
      return rawValue;
    }
    if (rawValue is Map) {
      return rawValue.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _parseAlerts(Object? rawValue) {
    final data = _asMap(rawValue);
    final alerts = data.entries.map((entry) {
      final item = _asMap(entry.value);
      final createdAt =
          TimestampUtils.normalizeEpochMilliseconds(item['created_at']) ??
              TimestampUtils.normalizeEpochMilliseconds(item['timestamp']) ??
              0;
      return <String, dynamic>{
        'id': (item['alert_id'] ?? item['id'] ?? entry.key).toString(),
        'type': (item['type'] ?? 'SOS').toString(),
        'message': (item['message'] ?? '').toString(),
        'child_id': (item['child_id'] ?? '').toString(),
        'child_name': (item['child_name'] ?? '').toString(),
        'location_text': (item['location_text'] ?? '').toString(),
        'zone_name': (item['zone_name'] ?? '').toString(),
        'created_at': createdAt,
      };
    }).toList()
      ..sort(
        (a, b) => ((b['created_at'] as int?) ?? 0)
            .compareTo((a['created_at'] as int?) ?? 0),
      );

    return alerts;
  }

  Future<void> _loadAlerts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final database = await _database();
      final snapshot = await database.ref('admin_alerts').get();
      final alerts = _parseAlerts(snapshot.value);
      setState(() {
        _alerts = alerts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = localizeErrorMessage(context.l10n, e);
        _isLoading = false;
      });
    }
  }

  Future<void> _startRealtimeAlerts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final database = await _database();
      final ref = database.ref('admin_alerts');
      await _alertsSubscription?.cancel();
      _alertsSubscription = ref.onValue.listen(
        (event) {
          final alerts = _parseAlerts(event.snapshot.value);
          if (!mounted) {
            return;
          }
          setState(() {
            _alerts = alerts;
            _isLoading = false;
            _error = null;
          });
        },
        onError: (error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _error = localizeErrorMessage(context.l10n, error);
            _isLoading = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _error = localizeErrorMessage(context.l10n, e);
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteAlert(String alertId) async {
    final l10n = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteAlert),
        content: Text(l10n.areYouSureDeleteAlert),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _adminApi.deleteAlert(alertId);
        if (!mounted) {
          return;
        }
        await _loadAlerts();
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.alertDeletedSuccessfully)),
        );
      } catch (e) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.error}: ${localizeErrorMessage(l10n, e)}'),
          ),
        );
      }
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    final date = TimestampUtils.toLocalDateTime(timestamp);
    if (date == null) {
      return context.l10n.unknown;
    }

    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: Text(l10n.alertsManagementTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAlerts,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('${l10n.error}: $_error'))
              : _alerts.isEmpty
                  ? Center(child: Text(l10n.noAlertsFound))
                  : RefreshIndicator(
                      onRefresh: _loadAlerts,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _alerts.length,
                        itemBuilder: (context, index) {
                          final alert = _alerts[index];
                          final type = (alert['type'] ?? '').toString();
                          final childName =
                              (alert['child_name'] ?? '').toString().trim();
                          final childId =
                              (alert['child_id'] ?? '').toString().trim();
                          final locationText =
                              (alert['location_text'] ?? '').toString().trim();
                          final zoneName =
                              (alert['zone_name'] ?? '').toString().trim();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    _getAlertColor(type).withValues(alpha: 0.1),
                                child: Icon(_getAlertIcon(type),
                                    color: _getAlertColor(type)),
                              ),
                              title: Text(
                                localizeAlertTypeLabel(l10n, type.toString()),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (alert['message'] ?? '')
                                            .toString()
                                            .trim()
                                            .isEmpty
                                        ? l10n.noMessage
                                        : localizeRawMessage(
                                            l10n,
                                            alert['message'].toString(),
                                          ),
                                  ),
                                  if (childName.isNotEmpty)
                                    Text(
                                      childName,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  if (childId.isNotEmpty)
                                    Text(
                                      '${l10n.childId}: $childId',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (locationText.isNotEmpty)
                                    Text(
                                      '${l10n.location}: $locationText',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (zoneName.isNotEmpty)
                                    Text(
                                      '${l10n.safeZone}: $zoneName',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  Text(
                                    _formatTimestamp(alert['created_at']),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteAlert(alert['id']),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  Color _getAlertColor(String type) {
    switch (type.toString().toUpperCase()) {
      case 'SOS':
        return Colors.red;
      case 'OUT_ZONE':
      case 'SAFE_ZONE_EXIT':
        return Colors.orange;
      case 'LOW_BATTERY':
        return Colors.yellow.shade700;
      case 'DEVICE_DISCONNECTED':
        return Colors.blueGrey;
      case 'DEVICE_RECONNECTED':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  IconData _getAlertIcon(String type) {
    switch (type.toString().toUpperCase()) {
      case 'SOS':
        return Icons.warning;
      case 'OUT_ZONE':
      case 'SAFE_ZONE_EXIT':
        return Icons.location_off;
      case 'LOW_BATTERY':
        return Icons.battery_alert;
      case 'DEVICE_DISCONNECTED':
        return Icons.portable_wifi_off;
      case 'DEVICE_RECONNECTED':
        return Icons.wifi;
      default:
        return Icons.notifications;
    }
  }
}
