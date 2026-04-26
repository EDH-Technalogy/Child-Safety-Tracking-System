import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/activity_provider.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';
import '../utils/timestamp_utils.dart';

class ActivityScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const ActivityScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    final activityProvider =
        Provider.of<ActivityProvider>(context, listen: false);
    await activityProvider.getActivityLogs(widget.childId);
    await activityProvider.getTodaySummary(widget.childId);
    await activityProvider.getWeeklySummary(widget.childId);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName} - ${l10n.activity}'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: l10n.summary),
            Tab(text: l10n.activityLogs),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSummaryTab(),
          _buildActivityLogsTab(),
        ],
      ),
    );
  }

  Widget _buildSummaryTab() {
    return Consumer<ActivityProvider>(
      builder: (context, activityProvider, child) {
        if (activityProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTodaySummaryCard(activityProvider),
                const SizedBox(height: 16),
                _buildWeeklySummaryCard(activityProvider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTodaySummaryCard(ActivityProvider activityProvider) {
    final summary = activityProvider.todaySummary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.todaysSummary,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (summary != null && summary.isNotEmpty) ...[
              _buildSummaryRow(
                Icons.route,
                context.l10n.totalDistance,
                '${summary['total_distance_km'] ?? '0'} ${context.l10n.kilometersShort}',
              ),
              _buildSummaryRow(
                Icons.location_on,
                context.l10n.locationPoints,
                '${summary['location_count'] ?? 0}',
              ),
              _buildSummaryRow(
                Icons.warning,
                context.l10n.sosAlerts,
                '${summary['sos_count'] ?? 0}',
              ),
              _buildSummaryRow(
                Icons.exit_to_app,
                context.l10n.zoneExits,
                '${summary['zone_exit_count'] ?? 0}',
              ),
              _buildSummaryRow(
                Icons.access_time,
                context.l10n.firstLocation,
                _formatTime(summary['first_location_time']),
              ),
              _buildSummaryRow(
                Icons.access_time_filled,
                context.l10n.lastLocation,
                _formatTime(summary['last_location_time']),
              ),
            ] else
              Text(
                context.l10n.noDataAvailableForToday,
                style: TextStyle(color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklySummaryCard(ActivityProvider activityProvider) {
    final weekly = activityProvider.weeklySummary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.weeklySummary,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (weekly != null && weekly.isNotEmpty) ...[
              _buildSummaryRow(
                Icons.calendar_today,
                context.l10n.daysTracked,
                '${weekly['days_tracked'] ?? 0}',
              ),
              _buildSummaryRow(
                Icons.route,
                context.l10n.totalDistance,
                '${weekly['total_distance_km'] ?? '0'} ${context.l10n.kilometersShort}',
              ),
              _buildSummaryRow(
                Icons.warning,
                context.l10n.totalSosAlerts,
                '${weekly['total_sos_count'] ?? 0}',
              ),
              _buildSummaryRow(
                Icons.exit_to_app,
                context.l10n.totalZoneExits,
                '${weekly['total_zone_exit_count'] ?? 0}',
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.dailyBreakdown,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _buildDailyBreakdown(weekly['days']),
            ] else
              Text(
                context.l10n.noWeeklyDataAvailable,
                style: TextStyle(color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyBreakdown(dynamic days) {
    if (days == null || (days as List).isEmpty) {
      return Text(context.l10n.noDailyData);
    }

    return Column(
      children: (days).map<Widget>((day) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                day['date'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                '${day['total_distance_km'] ?? 0} ${context.l10n.kilometersShort}',
              ),
              Row(
                children: [
                  Icon(
                    Icons.warning,
                    size: 14,
                    color:
                        (day['sos_count'] ?? 0) > 0 ? Colors.red : Colors.grey,
                  ),
                  Text(' ${day['sos_count'] ?? 0}'),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSummaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityLogsTab() {
    return Consumer<ActivityProvider>(
      builder: (context, activityProvider, child) {
        if (activityProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (activityProvider.activityLogs.isEmpty) {
          final l10n = AppLocalizations.of(context)!;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  l10n.noActivityLogsYet,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _loadData,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: activityProvider.activityLogs.length,
            itemBuilder: (context, index) {
              final log = activityProvider.activityLogs[index];
              return _buildActivityLogItem(log);
            },
          ),
        );
      },
    );
  }

  Widget _buildActivityLogItem(Map<String, dynamic> log) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getEventColor(log['event_type']),
          child: Icon(
            _getEventIcon(log['event_type']),
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          localizeAlertTypeLabel(
            AppLocalizations.of(context)!,
            log['event_type']?.toString(),
          ),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (log['description'] ?? '').toString().trim().isEmpty
                  ? AppLocalizations.of(context)!.noDescriptionAvailable
                  : localizeRawMessage(
                      AppLocalizations.of(context)!,
                      log['description'].toString(),
                    ),
            ),
            Text(
              _formatTimestamp(log['created_at']),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  IconData _getEventIcon(String? eventType) {
    switch (eventType?.toLowerCase()) {
      case 'sos':
        return Icons.warning;
      case 'location_update':
        return Icons.location_on;
      case 'zone_entry':
      case 'safe_zone_enter':
      case 'in_zone':
        return Icons.check_circle;
      case 'zone_exit':
      case 'safe_zone_exit':
      case 'out_zone':
        return Icons.exit_to_app;
      case 'low_battery':
        return Icons.battery_alert;
      case 'device_offline':
        return Icons.signal_cellular_off;
      default:
        return Icons.info;
    }
  }

  Color _getEventColor(String? eventType) {
    switch (eventType?.toLowerCase()) {
      case 'sos':
        return Colors.red;
      case 'location_update':
        return AppColors.primaryColor;
      case 'zone_entry':
      case 'safe_zone_enter':
      case 'in_zone':
        return AppColors.successColor;
      case 'zone_exit':
      case 'safe_zone_exit':
      case 'out_zone':
        return AppColors.warningColor;
      case 'low_battery':
        return Colors.orange;
      case 'device_offline':
        return Colors.grey;
      default:
        return AppColors.primaryColor;
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    final date = TimestampUtils.toLocalDateTime(timestamp);
    if (date == null) {
      return '';
    }

    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatTime(dynamic timestamp) {
    final date = TimestampUtils.toLocalDateTime(timestamp);
    if (date == null) {
      return '-';
    }

    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
