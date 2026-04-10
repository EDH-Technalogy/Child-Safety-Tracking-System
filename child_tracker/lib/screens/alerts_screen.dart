import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/alert_provider.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';
import '../models/alert_model.dart';
import 'package:intl/intl.dart';

class AlertsScreen extends StatefulWidget {
  final String childId;

  const AlertsScreen({super.key, required this.childId});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) {
        return;
      }
      final alertProvider = Provider.of<AlertProvider>(context, listen: false);
      if (!alertProvider.isLoading) {
        _loadAlerts();
      }
    });
  }

  Future<void> _loadAlerts() async {
    final alertProvider = Provider.of<AlertProvider>(context, listen: false);
    await alertProvider.loadAlerts(widget.childId);
    await alertProvider.getUnreadCount(widget.childId);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.alerts),
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
            onRefresh: _loadAlerts,
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

  const _AlertCard({required this.alert, required this.onTap});

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
                      children: [
                        Text(
                          _getAlertTitle(l10n),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: alert.isRead
                                ? FontWeight.normal
                                : FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getAlertColor().withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            localizeAlertTypeLabel(l10n, alert.type),
                            style: TextStyle(
                              fontSize: 10,
                              color: _getAlertColor(),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.message.trim().isEmpty
                          ? l10n.noMessage
                          : localizeRawMessage(l10n, alert.message),
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
                          Text(
                            alert.zoneName!,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500]),
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
        return Icons.exit_to_app;
      case 'SAFE_ZONE_EXIT':
        return Icons.exit_to_app;
      case 'IN_ZONE':
        return Icons.login;
      case 'LOW_BATTERY':
        return Icons.battery_alert;
      case 'DEVICE_OFF':
        return Icons.power_off;
      case 'DEVICE_ONLINE':
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
        return AppColors.outZoneColor;
      case 'SAFE_ZONE_EXIT':
        return AppColors.outZoneColor;
      case 'IN_ZONE':
        return AppColors.inZoneColor;
      case 'LOW_BATTERY':
        return AppColors.lowBatteryColor;
      case 'DEVICE_OFF':
        return AppColors.deviceOfflineColor;
      case 'DEVICE_ONLINE':
        return AppColors.successColor;
      default:
        return AppColors.infoColor;
    }
  }

  String _getAlertTitle(AppLocalizations l10n) {
    return localizeAlertTypeLabel(l10n, alert.type);
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('MMM dd, yyyy - HH:mm').format(date);
  }
}
