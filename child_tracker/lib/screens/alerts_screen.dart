import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/alert_provider.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';
import '../utils/timestamp_utils.dart';
import '../models/alert_model.dart';
import 'package:intl/intl.dart';

class AlertsScreen extends StatefulWidget {
  final String childId;

  const AlertsScreen({super.key, required this.childId});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String get _monitorOwnerId => 'alerts_screen:${widget.childId}';

  @override
  void initState() {
    super.initState();
    _initializeAlerts();
  }

  Future<void> _initializeAlerts() async {
    final alertProvider = Provider.of<AlertProvider>(context, listen: false);

    // Start real-time monitoring for this child
    await alertProvider.startMonitoring(
      widget.childId,
      ownerId: _monitorOwnerId,
    );
    if (!mounted) {
      return;
    }

    // Mark alerts as read AFTER the first frame renders so the user
    // actually sees the unread alerts before the badge is cleared.
    // Non-blocking — the API call runs in the background.
    return;
  }

  Future<void> _refreshAlerts() async {
    final alertProvider = Provider.of<AlertProvider>(context, listen: false);
    await alertProvider.loadAlerts(widget.childId);
  }

  @override
  void dispose() {
    Provider.of<AlertProvider>(context, listen: false)
        .stopMonitoring(ownerId: _monitorOwnerId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(l10n.alerts),
            const SizedBox(width: 8),
            Consumer<AlertProvider>(
              builder: (context, alertProvider, child) {
                final unreadCount =
                    alertProvider.unreadCountForChild(widget.childId);
                if (unreadCount == 0) return const SizedBox();
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          Consumer<AlertProvider>(
            builder: (context, alertProvider, child) {
              if (alertProvider.alerts.isEmpty) return const SizedBox();
              return TextButton(
                onPressed: () async {
                  await alertProvider.markAllAsRead(widget.childId);
                },
                child: Text(
                  l10n.markAllRead,
                  style: const TextStyle(color: Colors.white),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<AlertProvider>(
        builder: (context, alertProvider, child) {
          if (alertProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (alertProvider.alerts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noAlertsFound,
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.alerts,
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshAlerts,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: alertProvider.alerts.length,
              itemBuilder: (context, index) {
                final alert = alertProvider.alerts[index];
                return _AlertCard(
                  alert: alert,
                  onTap: () async {
                    if (!alert.isRead) {
                      await alertProvider.markAsRead(alert.id, widget.childId);
                    }
                  },
                  onDelete: () async {
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
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                            child: Text(l10n.delete),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      if (!context.mounted) return;
                      final messenger = ScaffoldMessenger.of(context);
                      final success = await alertProvider.deleteAlert(
                          alert.id, widget.childId);
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              success
                                  ? l10n.alertDeletedSuccessfully
                                  : localizeErrorMessage(
                                      l10n,
                                      alertProvider.error ??
                                          l10n.failedToDeleteAlert,
                                    ),
                            ),
                          ),
                        );
                      }
                    }
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final AlertModel alert;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AlertCard({
    required this.alert,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: alert.isRead
              ? Colors.transparent
              : _getAlertColor().withValues(alpha: 0.5),
          width: alert.isRead ? 1 : 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getAlertColor().withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getAlertIcon(),
                  color: _getAlertColor(),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _getAlertTitle(l10n),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: alert.isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getAlertColor().withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              localizeAlertTypeLabel(l10n, alert.type),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 10,
                                color: _getAlertColor(),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _buildAlertMessage(l10n),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (alert.childName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.child_care,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              alert.childName,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (alert.childId.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.badge_outlined,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${l10n.childId}: ${alert.childId}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[500]),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (alert.zoneName != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              alert.zoneName!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[500]),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if ((alert.locationText ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.place_outlined,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              alert.locationText!,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[500]),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _formatTimestamp(alert.createdAt),
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
              if (!alert.isRead)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                onPressed: onDelete,
                tooltip: l10n.deleteAlert,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getAlertIcon() {
    switch (alert.type) {
      case 'SOS':
        return Icons.warning;
      case 'OUT_ZONE':
      case 'ZONE_EXIT':
      case 'SAFE_ZONE_EXIT':
        return Icons.exit_to_app;
      case 'IN_ZONE':
      case 'ZONE_ENTER':
      case 'ZONE_ENTRY':
      case 'SAFE_ZONE_ENTER':
        return Icons.login;
      case 'SAFE_ZONE':
        return Icons.location_on;
      case 'LOW_BATTERY':
        return Icons.battery_alert;
      case 'DEVICE_OFF':
      case 'DEVICE_DISCONNECTED':
        return Icons.power_off;
      case 'DEVICE_ONLINE':
      case 'DEVICE_RECONNECTED':
        return Icons.power;
      default:
        return Icons.notifications;
    }
  }

  Color _getAlertColor() {
    switch (alert.type) {
      case 'SOS':
        return AppColors.sosColor;
      case 'OUT_ZONE':
      case 'ZONE_EXIT':
      case 'SAFE_ZONE_EXIT':
        return AppColors.outZoneColor;
      case 'IN_ZONE':
      case 'ZONE_ENTER':
      case 'ZONE_ENTRY':
      case 'SAFE_ZONE_ENTER':
        return AppColors.inZoneColor;
      case 'SAFE_ZONE':
        return AppColors.outZoneColor;
      case 'LOW_BATTERY':
        return AppColors.lowBatteryColor;
      case 'DEVICE_OFF':
      case 'DEVICE_DISCONNECTED':
        return AppColors.deviceOfflineColor;
      case 'DEVICE_ONLINE':
      case 'DEVICE_RECONNECTED':
        return AppColors.successColor;
      default:
        return AppColors.infoColor;
    }
  }

  String _getAlertTitle(AppLocalizations l10n) {
    return localizeAlertTypeLabel(l10n, alert.type);
  }

  String _buildAlertMessage(AppLocalizations l10n) {
    final localizedMessage = alert.message.trim().isEmpty
        ? ''
        : localizeRawMessage(l10n, alert.message);
    final normalizedType = alert.type.trim().toUpperCase();

    if (normalizedType == 'OUT_ZONE' ||
        normalizedType == 'ZONE_EXIT' ||
        normalizedType == 'SAFE_ZONE_EXIT') {
      final zone = (alert.zoneName ?? '').trim();
      final location = (alert.locationText ?? '').trim();
      if (zone.isNotEmpty && location.isNotEmpty) {
        return '${l10n.childOutOfSafeZone}: $zone • $location';
      }
      if (zone.isNotEmpty) {
        return '${l10n.childOutOfSafeZone}: $zone';
      }
      if (location.isNotEmpty) {
        return '${l10n.childOutOfSafeZone}: $location';
      }
      return l10n.childOutOfSafeZone;
    }

    if (normalizedType == 'IN_ZONE' ||
        normalizedType == 'ZONE_ENTER' ||
        normalizedType == 'ZONE_ENTRY' ||
        normalizedType == 'SAFE_ZONE_ENTER') {
      final zone = (alert.zoneName ?? '').trim();
      final location = (alert.locationText ?? '').trim();
      if (zone.isNotEmpty && location.isNotEmpty) {
        return '${l10n.childBackInSafeZone}: $zone • $location';
      }
      if (zone.isNotEmpty) {
        return '${l10n.childBackInSafeZone}: $zone';
      }
      if (location.isNotEmpty) {
        return '${l10n.childBackInSafeZone}: $location';
      }
      return l10n.childBackInSafeZone;
    }

    if (localizedMessage.isNotEmpty) {
      return localizedMessage;
    }

    return l10n.noMessage;
  }

  String _formatTimestamp(int timestamp) {
    final date = TimestampUtils.toLocalDateTime(timestamp);
    if (date == null) {
      return '--';
    }

    return DateFormat('MMM dd, yyyy - HH:mm').format(date);
  }
}
