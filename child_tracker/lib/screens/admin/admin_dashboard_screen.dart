import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/child_provider.dart';
import '../../services/admin_api_service.dart';
import '../../services/api_service.dart';
import '../../utils/localization_helpers.dart';
import '../../utils/timestamp_utils.dart';
import '../../widgets/admin_drawer.dart';
import '../../widgets/admin_dashboard/dashboard_chart_card.dart';
import '../../widgets/admin_dashboard/dashboard_charts.dart';
import '../../widgets/admin_dashboard/dashboard_models.dart';
import '../../widgets/admin_dashboard/dashboard_section.dart';
import '../../widgets/admin_dashboard/dashboard_stat_card.dart';
import '../../widgets/admin_dashboard/quick_action_card.dart';
import '../../widgets/admin_dashboard/recent_activity_list.dart';
import '../../widgets/hover_icon_button.dart';
import 'admin_alerts_screen.dart';
import 'admin_children_screen.dart';
import 'admin_devices_screen.dart';
import 'admin_logs_screen.dart';
import 'admin_map_screen.dart';
import 'admin_users_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminApiService _adminApi = AdminApiService();
  final ApiService _apiService = ApiService();

  _DashboardSnapshot? _snapshot;
  String? _fallbackChildId;
  bool _isLoading = true;
  String? _error;
  DateTime? _lastUpdatedAt;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  int? _hoveredQuickActionIndex;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _now = DateTime.now();
      });
    });
    _loadDashboard();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final startedAt = DateTime.now();
    final timelineDays = _lastSevenDays(startedAt);

    final statsFuture = _guard(_adminApi.getSystemStats());
    final usersFuture = _guard(_adminApi.getAllUsers());
    final devicesFuture = _guard(_adminApi.getAllDevices());
    final childrenFuture = _guard(_adminApi.getAllChildren());
    final alertsFuture = _guard(_adminApi.getAllAlerts());
    final logsFuture = _guard(_adminApi.getSystemLogs(limit: 8));
    final safeZonesFuture = _guard(_apiService.searchSafeZones());
    final dailyLocationFutures = {
      for (final day in timelineDays)
        _dateKey(day): _guard(
          _adminApi.getDailyActiveDevices(date: _dateKey(day)),
        ),
    };

    final statsResult = await statsFuture;
    final usersResult = await usersFuture;
    final devicesResult = await devicesFuture;
    final childrenResult = await childrenFuture;
    final alertsResult = await alertsFuture;
    final logsResult = await logsFuture;
    final safeZonesResult = await safeZonesFuture;

    final dailyLocationResults =
        <String, _RequestResult<Map<String, dynamic>>>{};
    for (final entry in dailyLocationFutures.entries) {
      dailyLocationResults[entry.key] = await entry.value;
    }

    if (!mounted) {
      return;
    }

    final snapshot = _buildSnapshot(
      now: startedAt,
      timelineDays: timelineDays,
      statsResult: statsResult,
      usersResult: usersResult,
      devicesResult: devicesResult,
      childrenResult: childrenResult,
      alertsResult: alertsResult,
      logsResult: logsResult,
      safeZonesResult: safeZonesResult,
      dailyLocationResults: dailyLocationResults,
    );

    setState(() {
      _snapshot = snapshot;
      _fallbackChildId = _extractFallbackChildId(childrenResult.data);
      _lastUpdatedAt = startedAt;
      _now = DateTime.now();
      _isLoading = false;
      _error = snapshot.hasAnyData
          ? null
          : _firstErrorMessage([
              statsResult.error,
              usersResult.error,
              devicesResult.error,
              childrenResult.error,
              alertsResult.error,
              logsResult.error,
              safeZonesResult.error,
              ...dailyLocationResults.values.map((value) => value.error),
            ]);
    });
  }

  _DashboardSnapshot _buildSnapshot({
    required DateTime now,
    required List<DateTime> timelineDays,
    required _RequestResult<Map<String, dynamic>> statsResult,
    required _RequestResult<List<dynamic>> usersResult,
    required _RequestResult<List<dynamic>> devicesResult,
    required _RequestResult<List<dynamic>> childrenResult,
    required _RequestResult<List<dynamic>> alertsResult,
    required _RequestResult<List<dynamic>> logsResult,
    required _RequestResult<List<dynamic>> safeZonesResult,
    required Map<String, _RequestResult<Map<String, dynamic>>>
        dailyLocationResults,
  }) {
    final unavailableSections = <String>{};
    final hasUsersData = usersResult.data != null;
    final hasDevicesData = devicesResult.data != null;
    final hasChildrenData = childrenResult.data != null;
    final hasAlertsData = alertsResult.data != null;
    final hasLogsData = logsResult.data != null;
    final hasSafeZonesData = safeZonesResult.data != null;

    final stats = statsResult.data;
    final users = _normalizeList(usersResult.data);
    final devices = _normalizeList(devicesResult.data);
    final children = _normalizeList(childrenResult.data);
    final alerts = _normalizeList(alertsResult.data);
    final logs = _normalizeList(logsResult.data);
    final safeZones = _normalizeList(safeZonesResult.data);

    if (statsResult.data == null) unavailableSections.add('system_stats');
    if (usersResult.data == null) unavailableSections.add('users');
    if (devicesResult.data == null) unavailableSections.add('devices');
    if (childrenResult.data == null) unavailableSections.add('children');
    if (alertsResult.data == null) unavailableSections.add('alerts');
    if (logsResult.data == null) unavailableSections.add('logs');
    if (safeZonesResult.data == null) unavailableSections.add('safe_zones');

    final activeUsersCount = hasUsersData
        ? users.where((user) => _normalizeStatus(user) == 'active').length
        : _extractInt(stats?['active_users']);
    final totalUsersCount =
        hasUsersData ? users.length : _extractInt(stats?['total_users']);
    final adminUsersCount = hasUsersData
        ? users.where((user) => _normalizeRole(user) == 'admin').length
        : null;
    final parentUsersCount = hasUsersData
        ? users.where((user) => _normalizeRole(user) != 'admin').length
        : (totalUsersCount != null && adminUsersCount != null
            ? totalUsersCount - adminUsersCount
            : null);
    final totalChildrenCount = hasChildrenData
        ? children.length
        : _extractInt(stats?['total_children']);

    final roleCounts = <String, int>{};
    if (hasUsersData) {
      for (final user in users) {
        final role = _normalizeRole(user);
        roleCounts[role] = (roleCounts[role] ?? 0) + 1;
      }
    }

    final deviceStatusCounts = <String, int>{};
    if (hasDevicesData) {
      for (final device in devices) {
        final status = _normalizeDeviceStatus(device);
        deviceStatusCounts[status] = (deviceStatusCounts[status] ?? 0) + 1;
      }
    }

    final totalDevicesCount =
        hasDevicesData ? devices.length : _extractInt(stats?['total_devices']);
    final activeDevicesCount = hasDevicesData
        ? (deviceStatusCounts['online'] ?? 0)
        : _extractInt(stats?['active_devices']);
    final offlineDevicesCount = hasDevicesData
        ? devices.length - (deviceStatusCounts['online'] ?? 0)
        : (totalDevicesCount != null && activeDevicesCount != null
            ? totalDevicesCount - activeDevicesCount
            : null);

    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    int countAlertsForDay(DateTime day, {Set<String>? allowedTypes}) {
      return alerts.where((alert) {
        final createdAt = TimestampUtils.toLocalDateTime(alert['created_at']);
        if (!_isSameDay(createdAt, day)) {
          return false;
        }
        if (allowedTypes == null || allowedTypes.isEmpty) {
          return true;
        }
        return allowedTypes.contains(_normalizeAlertType(alert['type']));
      }).length;
    }

    final alertTypeCounts = <String, int>{};
    if (hasAlertsData) {
      for (final alert in alerts) {
        final type = _normalizeAlertType(alert['type']);
        alertTypeCounts[type] = (alertTypeCounts[type] ?? 0) + 1;
      }
    }

    final totalAlertsCount =
        hasAlertsData ? alerts.length : _extractInt(stats?['total_alerts']);
    final todayAlertsCount = hasAlertsData ? countAlertsForDay(today) : null;
    final yesterdayAlertsCount =
        hasAlertsData ? countAlertsForDay(yesterday) : null;
    final geofenceBreachesToday = hasAlertsData
        ? countAlertsForDay(today, allowedTypes: _zoneExitTypes)
        : null;
    final geofenceBreachesYesterday = hasAlertsData
        ? countAlertsForDay(yesterday, allowedTypes: _zoneExitTypes)
        : null;

    final safeZonesCount = hasSafeZonesData ? safeZones.length : null;
    final activeSafeZonesCount = hasSafeZonesData
        ? safeZones.where((zone) => _normalizeStatus(zone) == 'active').length
        : null;

    final locationSeries = <_DailyLocationPoint>[];
    var isLocationSeriesComplete = true;
    int? todayLocationUpdatesCount;
    int? yesterdayLocationUpdatesCount;
    int? yesterdayActiveDevicesCount;

    for (final day in timelineDays) {
      final key = _dateKey(day);
      final result = dailyLocationResults[key];
      final payload = result?.data;

      if (payload == null) {
        isLocationSeriesComplete = false;
        unavailableSections.add('location_updates');
        continue;
      }

      final updates = _extractInt(payload['total_location_updates']) ?? 0;
      final activeDevices = _extractInt(payload['active_devices_count']) ?? 0;

      locationSeries.add(
        _DailyLocationPoint(
          date: day,
          totalLocationUpdates: updates,
          activeDevicesCount: activeDevices,
        ),
      );

      if (_isSameDay(day, today)) {
        todayLocationUpdatesCount = updates;
      } else if (_isSameDay(day, yesterday)) {
        yesterdayLocationUpdatesCount = updates;
        yesterdayActiveDevicesCount = activeDevices;
      }
    }

    final recentActivity = hasLogsData
        ? logs.take(6).toList(growable: false)
        : const <Map<String, dynamic>>[];

    return _DashboardSnapshot(
      totalUsers: totalUsersCount,
      activeUsers: activeUsersCount,
      totalParents: parentUsersCount,
      totalAdmins: adminUsersCount,
      totalChildren: totalChildrenCount,
      totalDevices: totalDevicesCount,
      activeDevices: activeDevicesCount,
      offlineDevices: offlineDevicesCount,
      totalAlerts: totalAlertsCount,
      todayAlerts: todayAlertsCount,
      yesterdayAlerts: yesterdayAlertsCount,
      todayLocationUpdates: todayLocationUpdatesCount,
      yesterdayLocationUpdates: yesterdayLocationUpdatesCount,
      safeZonesCount: safeZonesCount,
      activeSafeZones: activeSafeZonesCount,
      geofenceBreachesToday: geofenceBreachesToday,
      geofenceBreachesYesterday: geofenceBreachesYesterday,
      yesterdayActiveDevices: yesterdayActiveDevicesCount,
      userRoleCounts: roleCounts,
      deviceStatusCounts: deviceStatusCounts,
      alertTypeCounts: alertTypeCounts,
      locationSeries: locationSeries,
      isLocationSeriesComplete: isLocationSeriesComplete &&
          locationSeries.length == timelineDays.length,
      recentActivity: recentActivity,
      unavailableSections: unavailableSections,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: _DashboardPalette.background,
      drawer: const AdminDrawer(),
      appBar: AppBar(
        backgroundColor: _DashboardPalette.background,
        foregroundColor: _DashboardPalette.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          l10n.adminPanelTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          HoverIconButton(
            icon: Icons.autorenew_rounded,
            tooltip: l10n.refreshData,
            onPressed: _isLoading ? null : _loadDashboard,
          ),
        ],
      ),
      body: _isLoading
          ? _DashboardLoadingState(message: l10n.adminOverviewSubtitle)
          : _error != null || _snapshot == null
              ? _DashboardErrorState(
                  title: l10n.error,
                  message: _error != null
                      ? localizeRawMessage(l10n, _error!)
                      : l10n.noDataAvailableYet,
                  onRetry: _loadDashboard,
                  buttonLabel: l10n.retry,
                )
              : RefreshIndicator(
                  onRefresh: _loadDashboard,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final layout = _DashboardLayout.fromWidth(
                        constraints.maxWidth,
                      );
                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1440),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeaderCard(context, _snapshot!),
                                if (_snapshot!
                                    .unavailableSections.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  _UnavailableDataBanner(
                                    message: l10n.dashboardPartialData,
                                    sections: _localizedSectionNames(
                                      context,
                                      _snapshot!.unavailableSections,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 24),
                                DashboardSection(
                                  title: l10n.systemStatus,
                                  subtitle: l10n.adminOverviewSubtitle,
                                  child: _buildStatsGrid(
                                      context, layout, _snapshot!),
                                ),
                                const SizedBox(height: 28),
                                _buildInsightsContent(
                                  context,
                                  layout,
                                  _snapshot!,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, _DashboardSnapshot snapshot) {
    final authProvider = context.watch<AuthProvider>();
    final adminName = (authProvider.user?.name ?? context.l10n.admin).trim();
    final dateTimeLabel = DateFormat(
      'EEEE, MMMM d - HH:mm',
      Localizations.localeOf(context).toLanguageTag(),
    ).format(_now);
    final lastUpdatedLabel = _lastUpdatedAt == null
        ? null
        : DateFormat(
            'HH:mm',
            Localizations.localeOf(context).toLanguageTag(),
          ).format(_lastUpdatedAt!);

    final summaryMetrics = <DashboardMetric>[
      DashboardMetric(
        title: context.l10n.activeDevices,
        value: _formatMetricValue(context, snapshot.activeDevices),
        subtitle: context.l10n.liveDeviceStatus,
        icon: Icons.wifi_tethering_rounded,
        accentColor: _DashboardPalette.primary,
        badgeLabel: context.l10n.online,
      ),
      DashboardMetric(
        title: context.l10n.todayAlerts,
        value: _formatMetricValue(context, snapshot.todayAlerts),
        subtitle: context.l10n.latestAlertVolume,
        icon: Icons.crisis_alert_rounded,
        accentColor: _DashboardPalette.rose,
        badgeLabel: context.l10n.todaysSummary,
      ),
      DashboardMetric(
        title: context.l10n.safeZonesCount,
        value: _formatMetricValue(context, snapshot.safeZonesCount),
        subtitle: context.l10n.allAccessibleSafeZones,
        icon: Icons.verified_user_rounded,
        accentColor: _DashboardPalette.teal,
        badgeLabel: context.l10n.safeZones,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _DashboardPalette.headerTop,
            _DashboardPalette.headerBottom,
          ],
        ),
        border: Border.all(color: _DashboardPalette.headerLine),
        boxShadow: [
          BoxShadow(
            color: _DashboardPalette.primary.withValues(alpha: 0.10),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -48,
            right: -24,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: _DashboardPalette.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -62,
            left: -28,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.42),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 16,
                  spacing: 16,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.welcomeBackAdmin(adminName),
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: _DashboardPalette.ink,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.8,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.manageUsersDevicesSystem,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: _DashboardPalette.headerMuted,
                                      height: 1.45,
                                    ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _buildHeaderStatusPills(
                              context,
                              snapshot,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _HeaderPill(
                                icon: Icons.calendar_today_rounded,
                                label: dateTimeLabel,
                              ),
                              if (lastUpdatedLabel != null)
                                _HeaderPill(
                                  icon: Icons.sync_rounded,
                                  label:
                                      '${context.l10n.lastUpdated}: $lastUpdatedLabel',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _loadDashboard,
                          style: FilledButton.styleFrom(
                            foregroundColor: _DashboardPalette.ink,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.72),
                            side: const BorderSide(
                              color: _DashboardPalette.headerLine,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                          icon: const Icon(Icons.autorenew_rounded),
                          label: Text(context.l10n.refreshData),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminLogsScreen(),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _DashboardPalette.ink,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.32),
                            side: BorderSide(
                              color: _DashboardPalette.headerLine,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                          icon: const Icon(Icons.timeline_rounded),
                          label: Text(context.l10n.systemLogs),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1080
                        ? 3
                        : constraints.maxWidth >= 620
                            ? 2
                            : 1;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: summaryMetrics.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 152,
                      ),
                      itemBuilder: (context, index) {
                        final metric = summaryMetrics[index];
                        return _HeaderMetricCard(metric: metric);
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(
    BuildContext context,
    _DashboardLayout layout,
    _DashboardSnapshot snapshot,
  ) {
    final l10n = context.l10n;
    final metrics = <DashboardMetric>[
      DashboardMetric(
        title: l10n.totalUsers,
        value: _formatMetricValue(context, snapshot.totalUsers),
        subtitle:
            '${l10n.activeUsers}: ${_formatMetricValue(context, snapshot.activeUsers)}',
        icon: Icons.groups_rounded,
        accentColor: _DashboardPalette.primary,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
          );
        },
      ),
      DashboardMetric(
        title: l10n.totalParentsNormalUsers,
        value: _formatMetricValue(context, snapshot.totalParents),
        subtitle:
            '${l10n.administrator}: ${_formatMetricValue(context, snapshot.totalAdmins)}',
        icon: Icons.family_restroom_rounded,
        accentColor: _DashboardPalette.indigo,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
          );
        },
      ),
      DashboardMetric(
        title: l10n.totalChildren,
        value: _formatMetricValue(context, snapshot.totalChildren),
        subtitle:
            '${l10n.safeZones}: ${_formatMetricValue(context, snapshot.safeZonesCount)}',
        icon: Icons.child_care_rounded,
        accentColor: _DashboardPalette.teal,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminChildrenScreen()),
          );
        },
      ),
      DashboardMetric(
        title: l10n.totalDevices,
        value: _formatMetricValue(context, snapshot.totalDevices),
        subtitle:
            '${l10n.online}: ${_formatMetricValue(context, snapshot.activeDevices)}',
        icon: Icons.devices_other_rounded,
        accentColor: _DashboardPalette.amber,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminDevicesScreen()),
          );
        },
      ),
      DashboardMetric(
        title: l10n.activeDevices,
        value: _formatMetricValue(context, snapshot.activeDevices),
        subtitle:
            '${l10n.offline}: ${_formatMetricValue(context, snapshot.offlineDevices)}',
        icon: Icons.sensors_rounded,
        accentColor: _DashboardPalette.primary,
        trend: _buildTrend(
          current: snapshot.activeDevices,
          previous: snapshot.yesterdayActiveDevices,
          label: l10n.vsYesterday,
          positiveIsGood: true,
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminDevicesScreen()),
          );
        },
      ),
      DashboardMetric(
        title: l10n.offlineDevices,
        value: _formatMetricValue(context, snapshot.offlineDevices),
        subtitle:
            '${l10n.totalDevices}: ${_formatMetricValue(context, snapshot.totalDevices)}',
        icon: Icons.signal_wifi_off_rounded,
        accentColor: _DashboardPalette.rose,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminDevicesScreen()),
          );
        },
      ),
      DashboardMetric(
        title: l10n.todayAlerts,
        value: _formatMetricValue(context, snapshot.todayAlerts),
        subtitle:
            '${l10n.totalAlerts}: ${_formatMetricValue(context, snapshot.totalAlerts)}',
        icon: Icons.notifications_active_rounded,
        accentColor: _DashboardPalette.rose,
        badgeLabel: l10n.todaysSummary,
        trend: _buildTrend(
          current: snapshot.todayAlerts,
          previous: snapshot.yesterdayAlerts,
          label: l10n.vsYesterday,
          positiveIsGood: false,
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminAlertsScreen()),
          );
        },
      ),
      DashboardMetric(
        title: l10n.todayLocationUpdates,
        value: _formatMetricValue(context, snapshot.todayLocationUpdates),
        subtitle:
            '${l10n.activeDevices}: ${_formatMetricValue(context, snapshot.activeDevices)}',
        icon: Icons.gps_fixed_rounded,
        accentColor: _DashboardPalette.indigo,
        badgeLabel: l10n.last7Days,
        trend: _buildTrend(
          current: snapshot.todayLocationUpdates,
          previous: snapshot.yesterdayLocationUpdates,
          label: l10n.vsYesterday,
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminMapScreen(
                childId: _preferredChildId(context),
              ),
            ),
          );
        },
      ),
      DashboardMetric(
        title: l10n.safeZonesCount,
        value: _formatMetricValue(context, snapshot.safeZonesCount),
        subtitle:
            '${l10n.active}: ${_formatMetricValue(context, snapshot.activeSafeZones)}',
        icon: Icons.verified_user_rounded,
        accentColor: _DashboardPalette.teal,
        onTap: () {
          Navigator.pushNamed(
            context,
            '/safe-zones',
            arguments: _preferredChildId(context),
          );
        },
      ),
      DashboardMetric(
        title: l10n.geofenceBreachesToday,
        value: _formatMetricValue(context, snapshot.geofenceBreachesToday),
        subtitle:
            '${l10n.todayAlerts}: ${_formatMetricValue(context, snapshot.todayAlerts)}',
        icon: Icons.radar_rounded,
        accentColor: _DashboardPalette.amber,
        badgeLabel: l10n.zoneExits,
        trend: _buildTrend(
          current: snapshot.geofenceBreachesToday,
          previous: snapshot.geofenceBreachesYesterday,
          label: l10n.vsYesterday,
          positiveIsGood: false,
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminAlertsScreen()),
          );
        },
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: layout.statCardMaxExtent,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: layout.statCardHeight,
      ),
      itemBuilder: (context, index) => DashboardStatCard(
        metric: metrics[index],
      ),
    );
  }

  Widget _buildChartsGrid(
    BuildContext context,
    _DashboardLayout layout,
    _DashboardSnapshot snapshot,
  ) {
    final l10n = context.l10n;

    final userRoleSeries = <DashboardSliceData>[
      if (snapshot.userRoleCounts['user'] != null)
        DashboardSliceData(
          label: l10n.parentUser,
          value: snapshot.userRoleCounts['user']!,
          color: _DashboardPalette.primary,
        ),
      if (snapshot.userRoleCounts['admin'] != null)
        DashboardSliceData(
          label: l10n.administrator,
          value: snapshot.userRoleCounts['admin']!,
          color: _DashboardPalette.indigo,
        ),
    ].where((item) => item.value > 0).toList(growable: false);

    final deviceStatusSeries = <DashboardSliceData>[
      if (snapshot.deviceStatusCounts['online'] != null)
        DashboardSliceData(
          label: l10n.online,
          value: snapshot.deviceStatusCounts['online']!,
          color: _DashboardPalette.emerald,
        ),
      if (snapshot.deviceStatusCounts['offline'] != null)
        DashboardSliceData(
          label: l10n.offline,
          value: snapshot.deviceStatusCounts['offline']!,
          color: _DashboardPalette.rose,
        ),
      if (snapshot.deviceStatusCounts['no_data'] != null)
        DashboardSliceData(
          label: l10n.noData,
          value: snapshot.deviceStatusCounts['no_data']!,
          color: _DashboardPalette.amber,
        ),
    ].where((item) => item.value > 0).toList(growable: false);

    final alertsByTypeSeries = _buildAlertTypeSeries(context, snapshot);

    final locationPoints = snapshot.isLocationSeriesComplete
        ? snapshot.locationSeries
            .map(
              (item) => DashboardPoint(
                label: DateFormat(
                  'EEE',
                  Localizations.localeOf(context).toLanguageTag(),
                ).format(item.date),
                value: item.totalLocationUpdates,
              ),
            )
            .toList(growable: false)
        : const <DashboardPoint>[];

    final cards = <Widget>[
      DashboardChartCard(
        title: l10n.usersByRole,
        subtitle: l10n.userRoleDistribution,
        emptyMessage: l10n.noDataAvailableYet,
        isEmpty: userRoleSeries.isEmpty,
        emptyIcon: Icons.bar_chart_rounded,
        child: UsersByRoleChart(series: userRoleSeries),
      ),
      DashboardChartCard(
        title: l10n.deviceStatusChart,
        subtitle: l10n.liveFleetHealth,
        emptyMessage: l10n.noDataAvailableYet,
        isEmpty: deviceStatusSeries.isEmpty,
        emptyIcon: Icons.donut_small_rounded,
        child: DeviceStatusChart(series: deviceStatusSeries),
      ),
      DashboardChartCard(
        title: l10n.alertsByType,
        subtitle: l10n.alertBreakdownAcrossThePlatform,
        emptyMessage: l10n.noDataAvailableYet,
        isEmpty: alertsByTypeSeries.isEmpty,
        emptyIcon: Icons.monitor_heart_outlined,
        child: AlertsByTypeChart(series: alertsByTypeSeries),
      ),
      DashboardChartCard(
        title: l10n.locationUpdates,
        subtitle: l10n.locationUpdatesLast7Days,
        emptyMessage: snapshot.unavailableSections.contains('location_updates')
            ? l10n.noAggregatedLocationData
            : l10n.noDataAvailableYet,
        isEmpty: locationPoints.isEmpty,
        emptyIcon: Icons.show_chart_rounded,
        child: LocationUpdatesChart(points: locationPoints),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: layout.chartCardMaxExtent,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: layout.chartCardHeight,
      ),
      itemBuilder: (context, index) => cards[index],
    );
  }

  Widget _buildInsightsContent(
    BuildContext context,
    _DashboardLayout layout,
    _DashboardSnapshot snapshot,
  ) {
    final chartsSection = DashboardSection(
      title: context.l10n.chartsAndInsights,
      subtitle: context.l10n.monitorUsersDevicesAlertsLocations,
      child: _buildChartsGrid(context, layout, snapshot),
    );

    if (!layout.showInsightsRail) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chartsSection,
          const SizedBox(height: 28),
          _buildBottomSections(context, layout, snapshot),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 7, child: chartsSection),
        const SizedBox(width: 24),
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRecentActivitySection(context, snapshot),
              const SizedBox(height: 28),
              _buildQuickActionsSection(context, layout),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSections(
    BuildContext context,
    _DashboardLayout layout,
    _DashboardSnapshot snapshot,
  ) {
    final recentActivitySection = Expanded(
      flex: 6,
      child: _buildRecentActivitySection(context, snapshot),
    );

    final quickActionsSection = Expanded(
      flex: 4,
      child: _buildQuickActionsSection(context, layout),
    );

    if (layout.showSideBySideBottomSections) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          recentActivitySection,
          const SizedBox(width: 20),
          quickActionsSection,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRecentActivitySection(context, snapshot),
        const SizedBox(height: 28),
        _buildQuickActionsSection(context, layout),
      ],
    );
  }

  Widget _buildRecentActivitySection(
    BuildContext context,
    _DashboardSnapshot snapshot,
  ) {
    return DashboardSection(
      title: context.l10n.recentActivity,
      subtitle: context.l10n.latestAuditEvents,
      action: TextButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminLogsScreen()),
          );
        },
        child: Text(context.l10n.systemLogs),
      ),
      child: RecentActivityList(
        activities: _buildRecentActivityItems(context, snapshot),
        emptyMessage: context.l10n.noActivityLogsYet,
      ),
    );
  }

  Widget _buildQuickActionsSection(
    BuildContext context,
    _DashboardLayout layout,
  ) {
    final quickActions = _buildQuickActions(context);

    return DashboardSection(
      title: context.l10n.quickActions,
      subtitle: context.l10n.openCoreAdminAreas,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: quickActions.length,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: layout.quickActionMaxExtent,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          mainAxisExtent: layout.quickActionHeight,
        ),
        itemBuilder: (context, index) => QuickActionCard(
          action: quickActions[index],
          isHovered: _hoveredQuickActionIndex == index,
          isDimmed: _hoveredQuickActionIndex != null &&
              _hoveredQuickActionIndex != index,
          onHoverChanged: (value) {
            setState(() {
              if (value) {
                _hoveredQuickActionIndex = index;
              } else if (_hoveredQuickActionIndex == index) {
                _hoveredQuickActionIndex = null;
              }
            });
          },
        ),
      ),
    );
  }

  List<DashboardQuickAction> _buildQuickActions(BuildContext context) {
    final l10n = context.l10n;
    final childId = _preferredChildId(context);

    return [
      DashboardQuickAction(
        title: l10n.userManagement,
        subtitle: l10n.usersActionSubtitle,
        icon: Icons.manage_accounts_rounded,
        accentColor: _DashboardPalette.primary,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
          );
        },
      ),
      DashboardQuickAction(
        title: l10n.childrenManagement,
        subtitle: l10n.childrenActionSubtitle,
        icon: Icons.face_retouching_natural_rounded,
        accentColor: _DashboardPalette.teal,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminChildrenScreen()),
          );
        },
      ),
      DashboardQuickAction(
        title: l10n.deviceManagement,
        subtitle: l10n.devicesActionSubtitle,
        icon: Icons.devices_other_rounded,
        accentColor: _DashboardPalette.amber,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminDevicesScreen()),
          );
        },
      ),
      DashboardQuickAction(
        title: l10n.mapView,
        subtitle: l10n.viewMapActionSubtitle,
        icon: Icons.travel_explore_rounded,
        accentColor: _DashboardPalette.indigo,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminMapScreen(childId: childId),
            ),
          );
        },
      ),
      DashboardQuickAction(
        title: l10n.alerts,
        subtitle: l10n.viewAlertsActionSubtitle,
        icon: Icons.crisis_alert_rounded,
        accentColor: _DashboardPalette.rose,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminAlertsScreen()),
          );
        },
      ),
      DashboardQuickAction(
        title: l10n.viewReportsHistory,
        subtitle: l10n.viewReportsActionSubtitle,
        icon: Icons.analytics_rounded,
        accentColor: _DashboardPalette.primary,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminLogsScreen()),
          );
        },
      ),
      DashboardQuickAction(
        title: l10n.safeZones,
        subtitle: l10n.safeZonesActionSubtitle,
        icon: Icons.verified_user_rounded,
        accentColor: _DashboardPalette.teal,
        onTap: () {
          Navigator.pushNamed(
            context,
            '/safe-zones',
            arguments: childId,
          );
        },
      ),
    ];
  }

  List<DashboardActivityItem> _buildRecentActivityItems(
    BuildContext context,
    _DashboardSnapshot snapshot,
  ) {
    return snapshot.recentActivity.map((entry) {
      final timestamp = TimestampUtils.toLocalDateTime(
        entry['timestamp'] ?? entry['created_at'],
      );
      final status =
          (entry['status'] ?? entry['result'] ?? context.l10n.unknown)
              .toString();
      final title =
          (entry['title'] ?? entry['eventType'] ?? context.l10n.unknown)
              .toString();
      final description =
          (entry['description'] ?? context.l10n.noDescriptionAvailable)
              .toString();

      return DashboardActivityItem(
        title: _humanizeEventLabel(title),
        description: description,
        timestampLabel: timestamp == null
            ? context.l10n.unavailable
            : DateFormat(
                'MMM d - HH:mm',
                Localizations.localeOf(context).toLanguageTag(),
              ).format(timestamp),
        statusLabel: _formatStatusLabel(context, status),
        statusColor: _statusColorFor(status),
        icon: _activityIconFor(entry),
        accentColor: _activityColorFor(entry),
        metadata: _activityMetadata(context, entry),
      );
    }).toList(growable: false);
  }

  List<DashboardSliceData> _buildAlertTypeSeries(
    BuildContext context,
    _DashboardSnapshot snapshot,
  ) {
    final entries = snapshot.alertTypeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final colorByType = <String, Color>{
      'SOS': _DashboardPalette.rose,
      'ZONE_EXIT': _DashboardPalette.amber,
      'ZONE_ENTER': _DashboardPalette.teal,
      'LOW_BATTERY': _DashboardPalette.amber,
      'DEVICE_OFFLINE': _DashboardPalette.indigo,
      'DEVICE_ONLINE': _DashboardPalette.primary,
      'UNKNOWN': const Color(0xFF94A3B8),
    };

    return entries
        .take(5)
        .map((entry) {
          return DashboardSliceData(
            label: _localizedAlertType(context, entry.key),
            value: entry.value,
            color: colorByType[entry.key] ?? const Color(0xFF64748B),
          );
        })
        .where((item) => item.value > 0)
        .toList(growable: false);
  }

  String _localizedAlertType(BuildContext context, String type) {
    final l10n = context.l10n;
    switch (type) {
      case 'SOS':
        return l10n.sos;
      case 'ZONE_EXIT':
        return l10n.zoneExits;
      case 'ZONE_ENTER':
        return l10n.inZone;
      case 'LOW_BATTERY':
        return l10n.lowBattery;
      case 'DEVICE_OFFLINE':
        return l10n.deviceOffline;
      case 'DEVICE_ONLINE':
        return l10n.deviceOnline;
      default:
        return l10n.unknown;
    }
  }

  DashboardTrend? _buildTrend({
    required int? current,
    required int? previous,
    required String label,
    bool positiveIsGood = true,
  }) {
    if (current == null || previous == null) {
      return null;
    }

    return DashboardTrend(
      delta: current - previous,
      label: label,
      positiveIsGood: positiveIsGood,
    );
  }

  String _formatMetricValue(BuildContext context, int? value) {
    if (value == null) {
      return '--';
    }
    return NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(value);
  }

  List<String> _localizedSectionNames(
    BuildContext context,
    Set<String> sections,
  ) {
    final l10n = context.l10n;
    final names = <String>[];
    if (sections.contains('system_stats')) names.add(l10n.systemStatus);
    if (sections.contains('users')) names.add(l10n.totalUsers);
    if (sections.contains('devices')) names.add(l10n.totalDevices);
    if (sections.contains('children')) names.add(l10n.totalChildren);
    if (sections.contains('alerts')) names.add(l10n.alerts);
    if (sections.contains('logs')) names.add(l10n.systemLogs);
    if (sections.contains('safe_zones')) names.add(l10n.safeZones);
    if (sections.contains('location_updates')) names.add(l10n.locationUpdates);
    return names;
  }

  String _firstErrorMessage(List<Object?> errors) {
    for (final error in errors) {
      if (error == null) {
        continue;
      }
      return error.toString().replaceFirst('Exception: ', '');
    }
    return '';
  }

  Future<_RequestResult<T>> _guard<T>(Future<T> future) async {
    try {
      return _RequestResult<T>(data: await future);
    } catch (error) {
      return _RequestResult<T>(error: error);
    }
  }

  List<Map<String, dynamic>> _normalizeList(List<dynamic>? source) {
    if (source == null) {
      return const <Map<String, dynamic>>[];
    }

    return source
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  int? _extractInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  String _normalizeRole(Map<String, dynamic> user) {
    return (user['role'] ?? 'user').toString().trim().toLowerCase() == 'admin'
        ? 'admin'
        : 'user';
  }

  String _normalizeStatus(Map<String, dynamic> item) {
    return (item['status'] ?? '').toString().trim().toLowerCase();
  }

  String _normalizeDeviceStatus(Map<String, dynamic> device) {
    if (device['is_disabled'] == true) {
      return 'offline';
    }

    final status = (device['status'] ??
            device['latest_live_status'] ??
            device['raw_live_status'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();

    if (status == 'online') {
      return 'online';
    }
    if (status == 'offline') {
      return 'offline';
    }
    return 'no_data';
  }

  String _normalizeAlertType(Object? rawType) {
    final type = rawType?.toString().trim().toUpperCase() ?? '';
    if (type == 'OUT_ZONE' || type == 'SAFE_ZONE_EXIT' || type == 'ZONE_EXIT') {
      return 'ZONE_EXIT';
    }
    if (type == 'IN_ZONE' ||
        type == 'SAFE_ZONE_ENTER' ||
        type == 'ZONE_ENTER') {
      return 'ZONE_ENTER';
    }
    if (type == 'LOW_BATTERY') {
      return 'LOW_BATTERY';
    }
    if (type == 'DEVICE_OFF' || type == 'DEVICE_OFFLINE') {
      return 'DEVICE_OFFLINE';
    }
    if (type == 'DEVICE_ON' || type == 'DEVICE_ONLINE') {
      return 'DEVICE_ONLINE';
    }
    if (type == 'SOS') {
      return 'SOS';
    }
    return type.isEmpty ? 'UNKNOWN' : type;
  }

  IconData _activityIconFor(Map<String, dynamic> entry) {
    final eventType = (entry['eventType'] ?? entry['event_type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (eventType.contains('user')) {
      return Icons.person_rounded;
    }
    if (eventType.contains('child')) {
      return Icons.child_care_rounded;
    }
    if (eventType.contains('device')) {
      return Icons.tablet_android_rounded;
    }
    if (eventType.contains('admin_login')) {
      return Icons.admin_panel_settings_rounded;
    }
    if (eventType.contains('logout')) {
      return Icons.logout_rounded;
    }
    if (eventType.contains('safe_zone') || eventType.contains('zone')) {
      return Icons.shield_rounded;
    }
    if (eventType.contains('alert')) {
      return Icons.notifications_rounded;
    }
    if (eventType.contains('location')) {
      return Icons.location_on_rounded;
    }
    return Icons.history_rounded;
  }

  Color _activityColorFor(Map<String, dynamic> entry) {
    final status = (entry['status'] ?? entry['result'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (status == 'failed') {
      return _DashboardPalette.rose;
    }

    final eventType = (entry['eventType'] ?? entry['event_type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (eventType.contains('device')) return _DashboardPalette.amber;
    if (eventType.contains('safe_zone') || eventType.contains('zone')) {
      return _DashboardPalette.teal;
    }
    if (eventType.contains('alert')) return _DashboardPalette.rose;
    if (eventType.contains('user')) return _DashboardPalette.primary;
    return _DashboardPalette.indigo;
  }

  String _activityMetadata(BuildContext context, Map<String, dynamic> entry) {
    final target = entry['target'];
    if (target is Map) {
      final name = target['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) {
        return name;
      }
      final email = target['email']?.toString().trim() ?? '';
      if (email.isNotEmpty) {
        return email;
      }
      final imei = target['imei']?.toString().trim() ?? '';
      if (imei.isNotEmpty) {
        return '${context.l10n.imei}: $imei';
      }
    }
    return '';
  }

  String _formatStatusLabel(BuildContext context, String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'success') {
      return context.l10n.success;
    }
    if (normalized == 'failed') {
      return context.l10n.error;
    }
    return normalized.isEmpty ? context.l10n.unknown : status;
  }

  Color _statusColorFor(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'success') {
      return _DashboardPalette.emerald;
    }
    if (normalized == 'failed') {
      return _DashboardPalette.rose;
    }
    return const Color(0xFF64748B);
  }

  String _humanizeEventLabel(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) {
      return cleaned;
    }
    final normalized = cleaned.replaceAll(RegExp(r'[_-]+'), ' ');
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String? _preferredChildId(BuildContext context) {
    final childProvider = context.read<ChildProvider>();
    final selectedChildId = childProvider.selectedChild?.id.trim() ?? '';
    if (selectedChildId.isNotEmpty) {
      return selectedChildId;
    }
    if (childProvider.children.isNotEmpty) {
      final childId = childProvider.children.first.id.trim();
      if (childId.isNotEmpty) {
        return childId;
      }
    }
    return _fallbackChildId;
  }

  String? _extractFallbackChildId(List<dynamic>? children) {
    if (children == null) {
      return null;
    }

    for (final entry in children) {
      if (entry is! Map) {
        continue;
      }

      final child = Map<String, dynamic>.from(entry);
      final childId =
          (child['id'] ?? child['child_id'] ?? '').toString().trim();
      if (childId.isNotEmpty) {
        return childId;
      }
    }

    return null;
  }

  List<DateTime> _lastSevenDays(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return List<DateTime>.generate(
      7,
      (index) => today.subtract(Duration(days: 6 - index)),
    );
  }

  String _dateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  bool _isSameDay(DateTime? first, DateTime second) {
    if (first == null) {
      return false;
    }
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  List<Widget> _buildHeaderStatusPills(
    BuildContext context,
    _DashboardSnapshot snapshot,
  ) {
    return [
      _HeaderPill(
        icon: Icons.wifi_tethering_rounded,
        label:
            '${_formatMetricValue(context, snapshot.activeDevices)} ${context.l10n.online}',
      ),
      _HeaderPill(
        icon: Icons.portable_wifi_off_rounded,
        label:
            '${_formatMetricValue(context, snapshot.offlineDevices)} ${context.l10n.offline}',
      ),
      _HeaderPill(
        icon: Icons.notifications_active_rounded,
        label:
            '${_formatMetricValue(context, snapshot.todayAlerts)} ${context.l10n.todayAlerts}',
      ),
    ];
  }
}

class _RequestResult<T> {
  const _RequestResult({
    this.data,
    this.error,
  });

  final T? data;
  final Object? error;
}

class _DashboardSnapshot {
  const _DashboardSnapshot({
    required this.totalUsers,
    required this.activeUsers,
    required this.totalParents,
    required this.totalAdmins,
    required this.totalChildren,
    required this.totalDevices,
    required this.activeDevices,
    required this.offlineDevices,
    required this.totalAlerts,
    required this.todayAlerts,
    required this.yesterdayAlerts,
    required this.todayLocationUpdates,
    required this.yesterdayLocationUpdates,
    required this.safeZonesCount,
    required this.activeSafeZones,
    required this.geofenceBreachesToday,
    required this.geofenceBreachesYesterday,
    required this.yesterdayActiveDevices,
    required this.userRoleCounts,
    required this.deviceStatusCounts,
    required this.alertTypeCounts,
    required this.locationSeries,
    required this.isLocationSeriesComplete,
    required this.recentActivity,
    required this.unavailableSections,
  });

  final int? totalUsers;
  final int? activeUsers;
  final int? totalParents;
  final int? totalAdmins;
  final int? totalChildren;
  final int? totalDevices;
  final int? activeDevices;
  final int? offlineDevices;
  final int? totalAlerts;
  final int? todayAlerts;
  final int? yesterdayAlerts;
  final int? todayLocationUpdates;
  final int? yesterdayLocationUpdates;
  final int? safeZonesCount;
  final int? activeSafeZones;
  final int? geofenceBreachesToday;
  final int? geofenceBreachesYesterday;
  final int? yesterdayActiveDevices;
  final Map<String, int> userRoleCounts;
  final Map<String, int> deviceStatusCounts;
  final Map<String, int> alertTypeCounts;
  final List<_DailyLocationPoint> locationSeries;
  final bool isLocationSeriesComplete;
  final List<Map<String, dynamic>> recentActivity;
  final Set<String> unavailableSections;

  bool get hasAnyData {
    return totalUsers != null ||
        totalDevices != null ||
        totalChildren != null ||
        todayAlerts != null ||
        safeZonesCount != null ||
        recentActivity.isNotEmpty ||
        locationSeries.isNotEmpty;
  }
}

class _DailyLocationPoint {
  const _DailyLocationPoint({
    required this.date,
    required this.totalLocationUpdates,
    required this.activeDevicesCount,
  });

  final DateTime date;
  final int totalLocationUpdates;
  final int activeDevicesCount;
}

class _DashboardLayout {
  const _DashboardLayout({
    required this.statCardMaxExtent,
    required this.statCardHeight,
    required this.chartCardMaxExtent,
    required this.chartCardHeight,
    required this.quickActionMaxExtent,
    required this.quickActionHeight,
    required this.showInsightsRail,
    required this.showSideBySideBottomSections,
  });

  final double statCardMaxExtent;
  final double statCardHeight;
  final double chartCardMaxExtent;
  final double chartCardHeight;
  final double quickActionMaxExtent;
  final double quickActionHeight;
  final bool showInsightsRail;
  final bool showSideBySideBottomSections;

  factory _DashboardLayout.fromWidth(double width) {
    if (width >= 1280) {
      return const _DashboardLayout(
        statCardMaxExtent: 300,
        statCardHeight: 236,
        chartCardMaxExtent: 560,
        chartCardHeight: 372,
        quickActionMaxExtent: 300,
        quickActionHeight: 140,
        showInsightsRail: true,
        showSideBySideBottomSections: false,
      );
    }
    if (width >= 860) {
      return const _DashboardLayout(
        statCardMaxExtent: 320,
        statCardHeight: 230,
        chartCardMaxExtent: 540,
        chartCardHeight: 340,
        quickActionMaxExtent: 280,
        quickActionHeight: 140,
        showInsightsRail: false,
        showSideBySideBottomSections: false,
      );
    }
    return const _DashboardLayout(
      statCardMaxExtent: 480,
      statCardHeight: 228,
      chartCardMaxExtent: 640,
      chartCardHeight: 320,
      quickActionMaxExtent: 360,
      quickActionHeight: 136,
      showInsightsRail: false,
      showSideBySideBottomSections: false,
    );
  }
}

class _DashboardPalette {
  static const Color background = Color(0xFFF4F7FB);
  static const Color ink = Color(0xFF14213D);
  static const Color primary = Color(0xFF2563EB);
  static const Color indigo = Color(0xFF4F46E5);
  static const Color teal = Color(0xFF0F766E);
  static const Color emerald = Color(0xFF059669);
  static const Color amber = Color(0xFFF59E0B);
  static const Color rose = Color(0xFFE11D48);
  static const Color headerTop = Color(0xFFF8FAFF);
  static const Color headerBottom = Color(0xFFE4ECFF);
  static const Color headerLine = Color(0xFFD8E3F7);
  static const Color headerMuted = Color(0xFF56657E);
}

class _DashboardLoadingState extends StatelessWidget {
  const _DashboardLoadingState({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _DashboardErrorState extends StatelessWidget {
  const _DashboardErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.buttonLabel,
  });

  final String title;
  final String message;
  final Future<void> Function() onRetry;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _DashboardPalette.rose.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: _DashboardPalette.rose,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: _DashboardPalette.ink,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF64748B),
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(buttonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnavailableDataBanner extends StatelessWidget {
  const _UnavailableDataBanner({
    required this.message,
    required this.sections,
  });

  final String message;
  final List<String> sections;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _DashboardPalette.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: _DashboardPalette.amber,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _DashboardPalette.ink,
                      ),
                ),
                if (sections.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    sections.join(' | '),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF9A3412),
                          height: 1.4,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _DashboardPalette.headerLine),
        boxShadow: [
          BoxShadow(
            color: _DashboardPalette.primary.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _DashboardPalette.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _DashboardPalette.ink,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _HeaderMetricCard extends StatelessWidget {
  const _HeaderMetricCard({
    required this.metric,
  });

  final DashboardMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _DashboardPalette.headerLine),
        boxShadow: [
          BoxShadow(
            color: _DashboardPalette.primary.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: metric.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  metric.icon,
                  color: metric.accentColor,
                  size: 20,
                ),
              ),
              if (metric.badgeLabel != null && metric.badgeLabel!.isNotEmpty)
                const SizedBox(width: 10),
              if (metric.badgeLabel != null && metric.badgeLabel!.isNotEmpty)
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: Text(
                      metric.badgeLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: _DashboardPalette.headerMuted,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: _DashboardPalette.ink,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                          height: 1.0,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metric.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: _DashboardPalette.ink,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metric.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _DashboardPalette.headerMuted,
                          height: 1.2,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const Set<String> _zoneExitTypes = {
  'ZONE_EXIT',
};
