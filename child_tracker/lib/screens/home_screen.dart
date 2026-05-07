import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/alert_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/child_provider.dart';
import '../providers/location_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';
import '../utils/photo_provider.dart';
import '../models/child_model.dart';
import '../widgets/app_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _backgroundAlertMonitorOwnerId = 'home_screen';
  Timer? _statusRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadChildren();
    _statusRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadChildren(showLoading: false),
    );
  }

  @override
  void dispose() {
    _statusRefreshTimer?.cancel();
    unawaited(
      Provider.of<AlertProvider>(
        context,
        listen: false,
      ).stopBackgroundMonitoring(
        ownerId: _backgroundAlertMonitorOwnerId,
      ),
    );
    super.dispose();
  }

  Future<void> _loadChildren({bool showLoading = true}) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final alertProvider = Provider.of<AlertProvider>(context, listen: false);
    final childProvider = Provider.of<ChildProvider>(context, listen: false);
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);

    if (authProvider.user != null) {
      if (!showLoading && childProvider.isLoading) {
        return;
      }

      if (kDebugMode) {
        debugPrint(
          '[HomeScreen.children] load userId=${authProvider.user!.id} '
          'role=${authProvider.user!.role} showLoading=$showLoading',
        );
      }

      await childProvider.loadChildren(
        authProvider.user!.id,
        showLoading: showLoading,
      );

      await alertProvider.syncBackgroundMonitoring(
        ownerId: _backgroundAlertMonitorOwnerId,
        childIds: childProvider.children.map((child) => child.id),
      );

      await settingsProvider.loadSettings();
      if (settingsProvider.locationTrackingEnabled &&
          childProvider.children.isNotEmpty) {
        final trackedChildId = childProvider.selectedChild?.id.trim().isNotEmpty ==
                true
            ? childProvider.selectedChild!.id.trim()
            : childProvider.children.first.id.trim();
        await locationProvider.startLocalTracking(trackedChildId);
      }
    }
  }

  Future<void> _openAddChild() async {
    final didChange = await Navigator.pushNamed(context, '/add-child');
    if (!mounted || didChange != true) return;

    await _loadChildren();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(l10n.children),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
            tooltip: l10n.menu,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: Consumer2<AuthProvider, ChildProvider>(
        builder: (context, authProvider, childProvider, child) {
          if (childProvider.isLoading && childProvider.children.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (childProvider.children.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.child_care,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noData,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.addChild,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _openAddChild,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.addChild),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => _loadChildren(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: childProvider.children.length,
              itemBuilder: (context, index) {
                final child = childProvider.children[index];
                return _ChildCard(child: child);
              },
            ),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'home_add_child',
            onPressed: _openAddChild,
            backgroundColor: AppColors.primaryColor,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final ChildModel child;

  const _ChildCard({required this.child});

  Color _deviceStatusColor(DeviceModel device) {
    switch (device.status.trim().toLowerCase()) {
      case 'online':
        return AppColors.successColor;
      case 'delayed':
      case 'weak_connection':
        return AppColors.warningColor;
      case 'offline':
      case 'disconnected':
        return AppColors.deviceOfflineColor;
      case 'no_data':
      case 'no_recent_data':
      default:
        return Colors.grey;
    }
  }

  IconData _deviceStatusIcon(DeviceModel device) {
    switch (device.status.trim().toLowerCase()) {
      case 'online':
        return Icons.wifi;
      case 'delayed':
      case 'weak_connection':
        return Icons.wifi_tethering_error;
      case 'offline':
      case 'disconnected':
        return Icons.wifi_off;
      case 'no_data':
      case 'no_recent_data':
      default:
        return Icons.info_outline;
    }
  }

  String _lastSeenLabel(
    BuildContext context,
    AppLocalizations l10n,
    DeviceModel device,
  ) {
    final lastSeen = DateTime.fromMillisecondsSinceEpoch(
      device.latestTimestamp,
    ).toLocal();
    final materialLocalizations = MaterialLocalizations.of(context);
    final date = materialLocalizations.formatCompactDate(lastSeen);
    final time = materialLocalizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(lastSeen),
    );

    return '${l10n.lastSeen}: $date $time';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final photoProvider = buildPhotoProvider(child.photo);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Provider.of<ChildProvider>(context, listen: false).selectChild(child);
          Navigator.pushNamed(context, '/child-detail', arguments: child.id);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: photoProvider != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image(
                          image: photoProvider,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.child_care,
                              size: 30,
                              color: AppColors.primaryColor,
                            );
                          },
                        ),
                      )
                    : const Icon(
                        Icons.child_care,
                        size: 30,
                        color: AppColors.primaryColor,
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          child.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit,
                              color: AppColors.primaryColor),
                          onPressed: () async {
                            Provider.of<ChildProvider>(context, listen: false)
                                .selectChild(child);
                            final didChange = await Navigator.pushNamed(
                                context, '/edit-child',
                                arguments: child.id);
                            if (!context.mounted || didChange != true) return;

                            final authProvider = Provider.of<AuthProvider>(
                                context,
                                listen: false);
                            if (authProvider.user == null) return;

                            await Provider.of<ChildProvider>(context,
                                    listen: false)
                                .loadChildren(authProvider.user!.id);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${l10n.childAge}: ${child.age} ${l10n.yearsOld}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusBadge(
                          label: localizeStatusLabel(l10n, child.status),
                          color: child.status == 'active'
                              ? AppColors.successColor
                              : Colors.grey,
                        ),
                        if (child.device != null) ...[
                          _StatusBadge(
                            label:
                                localizeStatusLabel(l10n, child.device!.status),
                            color: _deviceStatusColor(child.device!),
                            icon: _deviceStatusIcon(child.device!),
                          ),
                          _BatteryLevel(device: child.device!),
                        ],
                      ],
                    ),
                    if (child.device != null &&
                        child.device!.hasLiveTimestamp) ...[
                      const SizedBox(height: 4),
                      Text(
                        _lastSeenLabel(context, l10n, child.device!),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _StatusBadge({
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BatteryLevel extends StatelessWidget {
  final DeviceModel device;

  const _BatteryLevel({required this.device});

  @override
  Widget build(BuildContext context) {
    final color = device.batteryLevel <= 20
        ? AppColors.warningColor
        : Colors.grey.shade700;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          device.batteryLevel <= 20 ? Icons.battery_alert : Icons.battery_full,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '${device.batteryLevel}%',
          style: TextStyle(
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }
}
