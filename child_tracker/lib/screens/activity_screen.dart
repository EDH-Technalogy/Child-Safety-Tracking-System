import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/child_activity_summary_model.dart';
import '../providers/activity_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/child_provider.dart';
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
  bool _accessDenied = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final childProvider = Provider.of<ChildProvider>(context, listen: false);

    if (!_canAccessSelectedChild(authProvider, childProvider)) {
      if (mounted) {
        setState(() {
          _accessDenied = true;
        });
      }
      return;
    }

    if (mounted && _accessDenied) {
      setState(() {
        _accessDenied = false;
      });
    }

    final activityProvider =
        Provider.of<ActivityProvider>(context, listen: false);
    await Future.wait([
      activityProvider.getActivityLogs(widget.childId),
      activityProvider.getLast24HourSummary(widget.childId),
    ]);
  }

  bool _canAccessSelectedChild(
    AuthProvider authProvider,
    ChildProvider childProvider,
  ) {
    if (authProvider.isAdmin) {
      return true;
    }

    final currentUserId = authProvider.user?.id.toString().trim() ?? '';
    if (currentUserId.isEmpty) {
      return false;
    }

    final selectedChild = childProvider.selectedChild;
    if (selectedChild == null || selectedChild.id != widget.childId) {
      return true;
    }

    if (selectedChild.userId.trim().isEmpty) {
      return true;
    }

    return selectedChild.userId.trim() == currentUserId;
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
            Tab(text: _summaryTabLabel(context)),
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
        if (_accessDenied) {
          return _buildAccessDeniedState();
        }

        if (activityProvider.isSummaryLoading &&
            activityProvider.last24HourSummary == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (activityProvider.summaryError != null &&
            activityProvider.last24HourSummary == null) {
          return _buildErrorState(
            message: _localizedProviderError(
              context,
              activityProvider.summaryError!,
            ),
            onRetry: _loadData,
          );
        }

        final summary = activityProvider.last24HourSummary;
        if (summary == null) {
          return _buildErrorState(
            message: _summaryLoadErrorLabel(context),
            onRetry: _loadData,
          );
        }

        return RefreshIndicator(
          onRefresh: _loadData,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummaryHeader(summary),
                  const SizedBox(height: 16),
                  _buildMetricsGrid(summary, constraints.maxWidth),
                  const SizedBox(height: 16),
                  summary.hasRecordedActivity
                      ? _buildNarrativeCard(summary)
                      : _buildEmptyStateCard(),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSummaryHeader(ChildActivitySummaryModel summary) {
    final l10n = AppLocalizations.of(context)!;
    final childName = summary.childName.trim().isNotEmpty
        ? summary.childName
        : widget.childName;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryColor.withValues(alpha: 0.12),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primaryColor.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _activitySummaryTitle(context),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            childName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeaderBadge(
                icon: Icons.schedule_rounded,
                label: _last24HoursLabel(context),
              ),
              _HeaderBadge(
                icon: Icons.update_rounded,
                label:
                    '${l10n.lastUpdated}: ${_formatDateTime(summary.generatedAt)}',
              ),
              _HeaderBadge(
                icon: _connectionStatusIcon(summary.currentConnectionState),
                label:
                    '${_currentStatusLabel(context)}: ${_connectionStatusLabel(summary.currentConnectionState)}',
                accentColor:
                    _connectionStatusColor(summary.currentConnectionState),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(
    ChildActivitySummaryModel summary,
    double maxWidth,
  ) {
    final crossAxisCount = maxWidth >= 1180
        ? 4
        : maxWidth >= 760
            ? 2
            : 1;
    final mainAxisExtent = crossAxisCount == 1
        ? 136.0
        : maxWidth >= 1180
            ? 144.0
            : 140.0;

    final metrics = [
      _SummaryMetric(
        icon: Icons.route_rounded,
        label: _distanceTraveledLabel(context),
        value:
            '${summary.distanceKm.toStringAsFixed(2)} ${context.l10n.kilometersShort}',
        accentColor: Colors.indigo,
      ),
      _SummaryMetric(
        icon: Icons.logout_rounded,
        label: _safeZoneExitsLabel(context),
        value: '${summary.safeZoneExitCount}',
        accentColor: Colors.orange,
      ),
      _SummaryMetric(
        icon: Icons.verified_user_rounded,
        label: _safeZoneReturnsLabel(context),
        value: '${summary.safeZoneReturnCount}',
        accentColor: Colors.green,
      ),
      _SummaryMetric(
        icon: Icons.portable_wifi_off_rounded,
        label: _deviceDisconnectsLabel(context),
        value: '${summary.deviceDisconnectCount}',
        accentColor: Colors.redAccent,
      ),
      _SummaryMetric(
        icon: Icons.wifi_tethering_rounded,
        label: _deviceReconnectsLabel(context),
        value: '${summary.deviceReconnectCount}',
        accentColor: Colors.teal,
      ),
      _SummaryMetric(
        icon: Icons.pin_drop_rounded,
        label: context.l10n.locationPoints,
        value: '${summary.locationPointsCount}',
        accentColor: Colors.deepPurple,
      ),
      _SummaryMetric(
        icon: Icons.access_time_filled_rounded,
        label: _lastLocationUpdateLabel(context),
        value: _formatDateTime(summary.lastLocationUpdateAt),
        accentColor: Colors.blueGrey,
      ),
      _SummaryMetric(
        icon: _connectionStatusIcon(summary.currentConnectionState),
        label: _currentStatusLabel(context),
        value: _connectionStatusLabel(summary.currentConnectionState),
        accentColor: _connectionStatusColor(summary.currentConnectionState),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        mainAxisExtent: mainAxisExtent,
      ),
      itemBuilder: (context, index) {
        final metric = metrics[index];
        return _SummaryMetricCard(metric: metric);
      },
    );
  }

  Widget _buildNarrativeCard(ChildActivitySummaryModel summary) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: AppColors.primaryColor.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _activitySummaryTitle(context),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _buildNarrative(summary),
              style: const TextStyle(
                fontSize: 15,
                height: 1.55,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: Colors.grey.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.insights_outlined,
              size: 40,
              color: Colors.grey[500],
            ),
            const SizedBox(height: 12),
            Text(
              _noActivityLast24HoursLabel(context),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityLogsTab() {
    return Consumer<ActivityProvider>(
      builder: (context, activityProvider, child) {
        if (_accessDenied) {
          return _buildAccessDeniedState();
        }

        if (activityProvider.isActivityLogsLoading &&
            activityProvider.activityLogs.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (activityProvider.logsError != null &&
            activityProvider.activityLogs.isEmpty) {
          return _buildErrorState(
            message: _localizedProviderError(
              context,
              activityProvider.logsError!,
            ),
            onRetry: _loadData,
          );
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

  Widget _buildAccessDeniedState() {
    return _buildErrorState(
      message: AppLocalizations.of(context)!.permissionDenied,
      onRetry: _loadData,
      icon: Icons.lock_outline_rounded,
    );
  }

  Widget _buildErrorState({
    required String message,
    required Future<void> Function() onRetry,
    IconData icon = Icons.error_outline_rounded,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.grey[500]),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.retry),
            ),
          ],
        ),
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
      case 'device_disconnected':
        return Icons.signal_cellular_off;
      case 'device_reconnected':
      case 'device_online':
        return Icons.wifi_tethering;
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
      case 'device_disconnected':
        return Colors.grey;
      case 'device_reconnected':
      case 'device_online':
        return Colors.teal;
      default:
        return AppColors.primaryColor;
    }
  }

  String _buildNarrative(ChildActivitySummaryModel summary) {
    final locale = Localizations.localeOf(context);
    final childName = summary.childName.trim().isNotEmpty
        ? summary.childName
        : widget.childName;
    final distanceText = summary.distanceKm.toStringAsFixed(2);
    final connectionLabel =
        _connectionStatusLabel(summary.currentConnectionState);
    final lastUpdateText = summary.lastLocationUpdateAt != null
        ? _formatTimeOnly(summary.lastLocationUpdateAt!)
        : null;

    if (_isPashto(locale)) {
      final exitLabel = summary.safeZoneExitCount == 1
          ? '۱ ځل'
          : '${summary.safeZoneExitCount} ځله';
      final returnLabel = summary.safeZoneReturnCount == 1
          ? '۱ ځل'
          : '${summary.safeZoneReturnCount} ځله';
      final disconnectLabel = summary.deviceDisconnectCount == 1
          ? '۱ ځل'
          : '${summary.deviceDisconnectCount} ځله';
      final reconnectLabel = summary.deviceReconnectCount == 1
          ? '۱ ځل'
          : '${summary.deviceReconnectCount} ځله';
      final lastUpdateSentence = lastUpdateText != null
          ? 'وروستی د موقعیت تازه معلومات په $lastUpdateText ترلاسه شوي دي.'
          : 'په دې موده کې د موقعیت وروستی تازه معلومات نه دي ترلاسه شوي.';

      return 'په وروستیو ۲۴ ساعتونو کې $childName نږدې $distanceText کیلومتره ګرځېدلی دی. '
          'ماشوم $exitLabel له خوندي سیمې څخه وتلی او $returnLabel بېرته خوندي سیمې ته داخل شوی دی. '
          'د ماشوم وسیله $disconnectLabel له سیستم څخه جلا شوې او $reconnectLabel بېرته وصل شوې ده. '
          '$lastUpdateSentence '
          'د وسیلې اوسنی حالت $connectionLabel دی.';
    }

    if (_isDari(locale)) {
      final exitLabel = summary.safeZoneExitCount == 1
          ? '۱ بار'
          : '${summary.safeZoneExitCount} بار';
      final returnLabel = summary.safeZoneReturnCount == 1
          ? '۱ بار'
          : '${summary.safeZoneReturnCount} بار';
      final disconnectLabel = summary.deviceDisconnectCount == 1
          ? '۱ بار'
          : '${summary.deviceDisconnectCount} بار';
      final reconnectLabel = summary.deviceReconnectCount == 1
          ? '۱ بار'
          : '${summary.deviceReconnectCount} بار';
      final lastUpdateSentence = lastUpdateText != null
          ? 'آخرین به‌روزرسانی موقعیت در ساعت $lastUpdateText دریافت شده است.'
          : 'در این بازه زمانی هیچ به‌روزرسانی تازه‌ای از موقعیت دریافت نشده است.';

      return 'در ۲۴ ساعت گذشته، $childName حدود $distanceText کیلومتر حرکت کرده است. '
          'کودک $exitLabel از ساحه امن خارج شده و $returnLabel دوباره وارد ساحه امن شده است. '
          'دستگاه کودک $disconnectLabel از سیستم قطع شده و $reconnectLabel دوباره وصل شده است. '
          '$lastUpdateSentence '
          'وضعیت فعلی دستگاه $connectionLabel است.';
    }

    final exitLabel = _englishTimesLabel(summary.safeZoneExitCount);
    final returnLabel = _englishTimesLabel(summary.safeZoneReturnCount);
    final disconnectLabel = _englishTimesLabel(summary.deviceDisconnectCount);
    final reconnectLabel = _englishTimesLabel(summary.deviceReconnectCount);
    final lastUpdateSentence = lastUpdateText != null
        ? 'The last location update was received at $lastUpdateText.'
        : 'No recent location update was received during this period.';

    return 'In the last 24 hours, $childName traveled approximately $distanceText km. '
        'The child exited the safe zone $exitLabel and returned $returnLabel. '
        'The device was disconnected $disconnectLabel and reconnected $reconnectLabel. '
        '$lastUpdateSentence '
        'The device is currently $connectionLabel.';
  }

  String _englishTimesLabel(int count) {
    return count == 1 ? '1 time' : '$count times';
  }

  bool _isPashto(Locale locale) => locale.languageCode.toLowerCase() == 'ps';

  bool _isDari(Locale locale) {
    final code = locale.languageCode.toLowerCase();
    return code == 'fa' || code == 'prs' || code == 'dar';
  }

  String _localizedProviderError(BuildContext context, String rawError) {
    if (rawError.contains('You do not have permission to access this child')) {
      return AppLocalizations.of(context)!.permissionDenied;
    }

    return localizeErrorMessage(AppLocalizations.of(context)!, rawError);
  }

  String _summaryLoadErrorLabel(BuildContext context) {
    if (_isPashto(Localizations.localeOf(context))) {
      return 'د فعالیت لنډیز پورته نه شو.';
    }

    if (_isDari(Localizations.localeOf(context))) {
      return 'خلاصه فعالیت بارگذاری نشد.';
    }

    return 'Unable to load the activity summary.';
  }

  String _summaryTabLabel(BuildContext context) {
    if (_isPashto(Localizations.localeOf(context))) {
      return 'لنډیز';
    }

    if (_isDari(Localizations.localeOf(context))) {
      return 'خلاصه';
    }

    return 'Summary';
  }

  String _activitySummaryTitle(BuildContext context) {
    if (_isPashto(Localizations.localeOf(context))) {
      return 'د فعالیت لنډیز';
    }

    if (_isDari(Localizations.localeOf(context))) {
      return 'خلاصه فعالیت';
    }

    return 'Activity Summary';
  }

  String _last24HoursLabel(BuildContext context) {
    if (_isPashto(Localizations.localeOf(context))) {
      return 'وروستۍ ۲۴ ساعته';
    }

    if (_isDari(Localizations.localeOf(context))) {
      return '۲۴ ساعت گذشته';
    }

    return 'Last 24 Hours';
  }

  String _distanceTraveledLabel(BuildContext context) {
    if (_isPashto(Localizations.localeOf(context))) {
      return 'وهل شوی واټن';
    }

    if (_isDari(Localizations.localeOf(context))) {
      return 'مسافت طی‌شده';
    }

    return 'Distance Traveled';
  }

  String _safeZoneExitsLabel(BuildContext context) {
    if (_isPashto(Localizations.localeOf(context))) {
      return 'له خوندي سیمې وتل';
    }

    if (_isDari(Localizations.localeOf(context))) {
      return 'خروج از ساحه امن';
    }

    return 'Safe Zone Exits';
  }

  String _safeZoneReturnsLabel(BuildContext context) {
    if (_isPashto(Localizations.localeOf(context))) {
      return 'خوندي سیمې ته بېرته راتګ';
    }

    if (_isDari(Localizations.localeOf(context))) {
      return 'بازگشت به ساحه امن';
    }

    return 'Safe Zone Returns';
  }

  String _deviceDisconnectsLabel(BuildContext context) {
    if (_isPashto(Localizations.localeOf(context))) {
      return 'د وسیلې جلا کېدل';
    }

    if (_isDari(Localizations.localeOf(context))) {
      return 'قطع دستگاه';
    }

    return 'Device Disconnects';
  }

  String _deviceReconnectsLabel(BuildContext context) {
    if (_isPashto(Localizations.localeOf(context))) {
      return 'د وسیلې بېرته نښلېدل';
    }

    if (_isDari(Localizations.localeOf(context))) {
      return 'وصل دوباره دستگاه';
    }

    return 'Device Reconnects';
  }

  String _lastLocationUpdateLabel(BuildContext context) {
    if (_isPashto(Localizations.localeOf(context))) {
      return 'د موقعیت وروستۍ تازه‌کول';
    }

    if (_isDari(Localizations.localeOf(context))) {
      return 'آخرین به‌روزرسانی موقعیت';
    }

    return 'Last Location Update';
  }

  String _currentStatusLabel(BuildContext context) {
    if (_isPashto(Localizations.localeOf(context))) {
      return 'اوسنی حالت';
    }

    if (_isDari(Localizations.localeOf(context))) {
      return 'وضعیت فعلی';
    }

    return 'Current Status';
  }

  String _noActivityLast24HoursLabel(BuildContext context) {
    if (_isPashto(Localizations.localeOf(context))) {
      return 'په وروستیو ۲۴ ساعتونو کې هېڅ فعالیت نه دی ثبت شوی.';
    }

    if (_isDari(Localizations.localeOf(context))) {
      return 'در ۲۴ ساعت گذشته هیچ فعالیتی ثبت نشده است.';
    }

    return 'No activity recorded in the last 24 hours.';
  }

  String _connectionStatusLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'online':
        return context.l10n.online;
      case 'offline':
        return context.l10n.offline;
      default:
        return context.l10n.unknown;
    }
  }

  Color _connectionStatusColor(String value) {
    switch (value.trim().toLowerCase()) {
      case 'online':
        return AppColors.successColor;
      case 'offline':
        return Colors.redAccent;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _connectionStatusIcon(String value) {
    switch (value.trim().toLowerCase()) {
      case 'online':
        return Icons.wifi_tethering_rounded;
      case 'offline':
        return Icons.portable_wifi_off_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    final date = TimestampUtils.toLocalDateTime(timestamp);
    if (date == null) {
      return '';
    }

    return _formatDateTime(date);
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) {
      return context.l10n.unknown;
    }

    final materialLocalizations = MaterialLocalizations.of(context);
    final date = materialLocalizations.formatCompactDate(dateTime);
    final time = materialLocalizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(dateTime),
    );

    return '$date $time';
  }

  String _formatTimeOnly(DateTime dateTime) {
    final materialLocalizations = MaterialLocalizations.of(context);
    return materialLocalizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(dateTime),
    );
  }
}

class _SummaryMetric {
  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;

  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
  });
}

class _SummaryMetricCard extends StatelessWidget {
  final _SummaryMetric metric;

  const _SummaryMetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: metric.accentColor.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: metric.accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                metric.icon,
                color: metric.accentColor,
                size: 21,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      metric.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? accentColor;

  const _HeaderBadge({
    required this.icon,
    required this.label,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
