import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/device_status_model.dart';
import '../models/location_model.dart';
import '../providers/location_provider.dart';
import '../services/device_status_service.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';
import '../utils/timestamp_utils.dart';
import '../widgets/google_map_guard.dart';

class LocationHistoryScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const LocationHistoryScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen> {
  static const int _afghanistanTimezoneOffsetMinutes = 270;
  late DateTime _selectedDate;
  final DeviceStatusService _deviceStatusService = DeviceStatusService();

  @override
  void initState() {
    super.initState();
    _selectedDate = _normalizeCalendarDate(_afghanistanToday);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final dateStr = _selectedAfghanistanDateKey;
    await locationProvider.getRouteData(
      widget.childId,
      dateStr,
      timezoneOffsetMinutes: _afghanistanTimezoneOffsetMinutes,
    );
  }

  Future<void> _selectDate() async {
    final afghanistanToday = _normalizeCalendarDate(_afghanistanToday);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: afghanistanToday.subtract(const Duration(days: 30)),
      lastDate: afghanistanToday,
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = _normalizeCalendarDate(picked);
      });
      await _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName} ${l10n.childHistory}'),
      ),
      body: Consumer<LocationProvider>(
        builder: (context, locationProvider, child) {
          final routeData = locationProvider.routeData;
          final hasAnyHistory = routeData?.hasAnyHistory ?? false;
          final allLogs = routeData?.logs ?? const <HistoryEventModel>[];
          final activityLogs = _nonConnectionLogs(allLogs);

          return StreamBuilder<List<DeviceStatusLogModel>>(
            stream: _deviceStatusService.watchDeviceStatusLogsForRange(
              widget.childId,
              startTimestamp: _selectedAfghanistanDayStart,
              endTimestamp: _selectedAfghanistanDayEnd,
            ),
            builder: (context, snapshot) {
              final realtimeLogs =
                  snapshot.data ?? const <DeviceStatusLogModel>[];
              final deviceConnectionLogs = _deviceConnectionLogs(
                allLogs,
                realtimeLogs,
              );
              final offlineEventLogs =
                  deviceConnectionLogs.where((log) => !log.isOnline).toList();
              final onlineEventLogs =
                  deviceConnectionLogs.where((log) => log.isOnline).toList();
              final hasStatusEvents = deviceConnectionLogs.isNotEmpty;

              final content = <Widget>[];

              if (locationProvider.isLoading &&
                  routeData == null &&
                  !hasStatusEvents) {
                content.add(
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              } else {
                if (routeData != null && hasAnyHistory) {
                  content.addAll([
                    const SizedBox(height: 16),
                    _buildRouteSummaryCard(routeData, l10n),
                  ]);
                } else if (locationProvider.error != null && !hasStatusEvents) {
                  content.addAll([
                    const SizedBox(height: 16),
                    _HistoryMessageState(
                      icon: Icons.error_outline,
                      message: locationProvider.error!,
                      buttonLabel: l10n.retry,
                      onPressed: _loadHistory,
                    ),
                  ]);
                } else if (!hasStatusEvents &&
                    snapshot.connectionState != ConnectionState.waiting) {
                  content.addAll([
                    const SizedBox(height: 16),
                    _HistoryMessageState(
                      icon: Icons.location_off,
                      message:
                          'No online or offline events recorded for this date.',
                      buttonLabel: l10n.retry,
                      onPressed: _loadHistory,
                    ),
                  ]);
                }

                content.addAll([
                  const SizedBox(height: 16),
                  _buildSectionTitle(
                    context,
                    'Status Events',
                    '${deviceConnectionLogs.length}',
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.hasError)
                    _HistoryInlineMessage(
                      message: 'Unable to load live connection history.',
                    )
                  else
                    Column(
                      children: [
                        _DeviceStatusEventSection(
                          title: 'Offline Events',
                          emptyMessage:
                              'No offline events recorded for this date.',
                          accentColor: AppColors.errorColor,
                          icon: Icons.wifi_off_rounded,
                          logs: offlineEventLogs,
                          onTapLog: (log) => _showDeviceStatusDetails(
                            context,
                            deviceName: log.deviceName.isNotEmpty
                                ? log.deviceName
                                : widget.childName,
                            status: log.status,
                            placeName: log.placeName,
                            latitude: log.latitude,
                            longitude: log.longitude,
                            timestamp: log.timestamp,
                            source: log.source,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DeviceStatusEventSection(
                          title: 'Online Events',
                          emptyMessage:
                              'No online events recorded for this date.',
                          accentColor: AppColors.successColor,
                          icon: Icons.wifi_rounded,
                          logs: onlineEventLogs,
                          onTapLog: (log) => _showDeviceStatusDetails(
                            context,
                            deviceName: log.deviceName.isNotEmpty
                                ? log.deviceName
                                : widget.childName,
                            status: log.status,
                            placeName: log.placeName,
                            latitude: log.latitude,
                            longitude: log.longitude,
                            timestamp: log.timestamp,
                            source: log.source,
                          ),
                        ),
                      ],
                    ),
                  if (activityLogs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildSectionTitle(
                      context,
                      l10n.activityLogs,
                      '${activityLogs.length}',
                    ),
                    const SizedBox(height: 12),
                    ListView.builder(
                      itemCount: activityLogs.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemBuilder: (context, index) => _HistoryEventTile(
                        event: activityLogs[index],
                        childName: widget.childName,
                      ),
                    ),
                  ],
                ]);
              }

              return Column(
                children: [
                  _buildDateSelector(context, l10n),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadHistory,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: content,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<HistoryEventModel> _nonConnectionLogs(List<HistoryEventModel> logs) {
    return logs.where((log) => !_isConnectionEvent(log.type)).toList();
  }

  List<DeviceStatusLogModel> _deviceConnectionLogs(
    List<HistoryEventModel> routeLogs,
    List<DeviceStatusLogModel> realtimeLogs,
  ) {
    final filteredRealtimeLogs = realtimeLogs.where((log) {
      final status = log.status.trim().toLowerCase();
      return (status == 'online' || status == 'offline') &&
          _isSelectedAfghanistanDate(log.timestamp);
    }).toList();
    final fallbackLogs = routeLogs
        .where(
          (log) =>
              _isConnectionEvent(log.type) &&
              _normalizeHistoryStatus(log.type).isNotEmpty &&
              _isSelectedAfghanistanDate(log.timestamp),
        )
        .map(_mapHistoryEventToDeviceStatusLog)
        .toList();
    final mergedLogs = <DeviceStatusLogModel>[
      ...filteredRealtimeLogs,
      ...fallbackLogs,
    ];
    final seen = <String>{};
    final dedupedLogs = <DeviceStatusLogModel>[];

    for (final log in mergedLogs) {
      final key =
          '${log.status}|${log.timestamp}|${log.latitude}|${log.longitude}';
      if (seen.add(key)) {
        dedupedLogs.add(log);
      }
    }

    dedupedLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return dedupedLogs;
  }

  bool _isSelectedAfghanistanDate(int timestamp) {
    return TimestampUtils.formatAfghanistan(
          timestamp,
          pattern: 'yyyy-MM-dd',
        ) ==
        _selectedAfghanistanDateKey;
  }

  DateTime get _afghanistanToday =>
      TimestampUtils.toAfghanistanDateTime(
        DateTime.now().millisecondsSinceEpoch,
      ) ??
      DateTime.now();

  DateTime _normalizeCalendarDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  String get _selectedAfghanistanDateKey =>
      DateFormat('yyyy-MM-dd').format(_selectedDate);

  int get _selectedAfghanistanDayStart {
    final afghanistanMidnightUtc = DateTime.utc(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    return afghanistanMidnightUtc
        .subtract(TimestampUtils.afghanistanOffset)
        .millisecondsSinceEpoch;
  }

  int get _selectedAfghanistanDayEnd =>
      _selectedAfghanistanDayStart + const Duration(days: 1).inMilliseconds - 1;

  String _normalizeHistoryStatus(String type) {
    switch (type.toUpperCase()) {
      case 'DEVICE_ONLINE':
      case 'DEVICE_RECONNECTED':
        return 'online';
      case 'DEVICE_OFFLINE':
      case 'DEVICE_DISCONNECTED':
        return 'offline';
      default:
        return '';
    }
  }

  DeviceStatusLogModel _mapHistoryEventToDeviceStatusLog(
      HistoryEventModel log) {
    final normalizedStatus = _normalizeHistoryStatus(log.type);
    final isOnline = normalizedStatus == 'online';
    final placeName = isOnline
        ? _readMetadataString(log.metadata, [
            'reconnectedAddress',
            'placeName',
            'locationText',
            'place_name',
          ])
        : _readMetadataString(log.metadata, [
            'lastKnownAddress',
            'placeName',
            'locationText',
            'place_name',
          ]);
    final latitude = isOnline
        ? _readMetadataDouble(log.metadata, ['reconnectedLat']) ?? log.latitude
        : _readMetadataDouble(log.metadata, ['lastKnownLat']) ?? log.latitude;
    final longitude = isOnline
        ? _readMetadataDouble(log.metadata, ['reconnectedLng']) ?? log.longitude
        : _readMetadataDouble(log.metadata, ['lastKnownLng']) ?? log.longitude;

    return DeviceStatusLogModel(
      id: log.id,
      childId: log.childId,
      trackingKey: log.trackingKey,
      childName: widget.childName,
      deviceName: widget.childName,
      status: normalizedStatus,
      statusName: normalizedStatus == 'online' ? 'Online' : 'Offline',
      latitude: latitude,
      longitude: longitude,
      timestamp: log.timestamp,
      formattedTime: TimestampUtils.formatAfghanistan(log.timestamp),
      placeName: placeName,
      source: (log.metadata['source'] ?? 'history_route').toString(),
    );
  }

  String? _readMetadataString(
    Map<String, dynamic> metadata,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  double? _readMetadataDouble(
    Map<String, dynamic> metadata,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = metadata[key];
      if (value is num) {
        return value.toDouble();
      }

      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  bool _isConnectionEvent(String type) {
    switch (type.toUpperCase()) {
      case 'DEVICE_DISCONNECTED':
      case 'DEVICE_RECONNECTED':
      case 'DEVICE_OFFLINE':
      case 'DEVICE_ONLINE':
      case 'DEVICE_STATUS':
        return true;
      default:
        return false;
    }
  }

  Widget _buildDateSelector(BuildContext context, AppLocalizations l10n) {
    final afghanistanToday = _normalizeCalendarDate(_afghanistanToday);
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.primaryColor.withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () async {
              setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 1));
              });
              await _loadHistory();
            },
          ),
          InkWell(
            onTap: _selectDate,
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 20),
                const SizedBox(width: 8),
                Text(
                  DateFormat('MMMM dd, yyyy').format(_selectedDate),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _selectedDate.isBefore(afghanistanToday)
                ? () async {
                    setState(() {
                      _selectedDate =
                          _selectedDate.add(const Duration(days: 1));
                    });
                    await _loadHistory();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSummaryCard(
    RouteDataModel routeData,
    AppLocalizations l10n,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SummaryItem(
                icon: Icons.straighten,
                label: l10n.distance,
                value: '${routeData.totalDistanceKm} ${l10n.kilometersShort}',
              ),
              _SummaryItem(
                icon: Icons.location_on,
                label: l10n.locations,
                value: '${routeData.locationCount}',
              ),
              _SummaryItem(
                icon: Icons.history,
                label: l10n.activityLogs,
                value: '${routeData.eventCount}',
              ),
            ],
          ),
          if (routeData.firstLocationTime > 0) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      l10n.start,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      _formatTime(routeData.firstLocationTime),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Icon(Icons.arrow_forward, color: Colors.grey),
                Column(
                  children: [
                    Text(
                      l10n.end,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      _formatTime(routeData.lastLocationTime),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
    BuildContext context,
    String title,
    String count,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            count,
            style: const TextStyle(
              color: AppColors.primaryColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  void _showDeviceStatusDetails(
    BuildContext context, {
    required String deviceName,
    required String status,
    required String? placeName,
    required double? latitude,
    required double? longitude,
    required int timestamp,
    required String source,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final normalizedStatus = status.trim().toLowerCase();
    final isOnline = normalizedStatus == 'online';
    final accentColor =
        isOnline ? AppColors.successColor : AppColors.errorColor;
    final hasCoordinates = latitude != null && longitude != null;
    final resolvedPlaceName = placeName?.trim() ?? '';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: accentColor,
                      child: Icon(
                        isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deviceName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isOnline ? 'Online Event' : 'Offline Event',
                            style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (hasCoordinates) ...[
                  const SizedBox(height: 16),
                  _StatusMapPreview(
                    latitude: latitude,
                    longitude: longitude,
                    placeName: placeName,
                    markerColor: accentColor,
                    markerTitle: isOnline ? 'Online event' : 'Offline event',
                  ),
                ],
                const SizedBox(height: 14),
                _StatusDetailRow(
                  label: 'Status',
                  value: isOnline ? l10n.online : l10n.offline,
                ),
                _StatusDetailRow(
                  label: 'Address',
                  value: resolvedPlaceName.isNotEmpty
                      ? resolvedPlaceName
                      : 'Not available',
                ),
                _StatusDetailRow(
                  label: 'Timestamp',
                  value: _formatDetailedTimestamp(timestamp),
                ),
                _StatusDetailRow(
                  label: 'Date',
                  value: _formatDetailedDate(timestamp),
                ),
                _StatusDetailRow(
                  label: 'Time',
                  value: _formatDetailedTime(timestamp),
                ),
                _StatusDetailRow(
                  label: 'Latitude',
                  value: latitude?.toStringAsFixed(6) ?? 'Not available',
                ),
                _StatusDetailRow(
                  label: 'Longitude',
                  value: longitude?.toStringAsFixed(6) ?? 'Not available',
                ),
                _StatusDetailRow(
                  label: 'Source',
                  value: source.trim().isNotEmpty ? source : 'system',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: hasCoordinates
                        ? () => _openGoogleMaps(latitude, longitude)
                        : null,
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open in Google Maps'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDetailedTimestamp(int timestamp) {
    return TimestampUtils.formatAfghanistan(
      timestamp,
      pattern: 'yyyy-MM-dd hh:mm:ss a',
    );
  }

  String _formatDetailedDate(int timestamp) {
    return TimestampUtils.formatAfghanistan(timestamp, pattern: 'MMM dd, yyyy');
  }

  String _formatDetailedTime(int timestamp) {
    return TimestampUtils.formatAfghanistan(timestamp, pattern: 'hh:mm:ss a');
  }

  Future<void> _openGoogleMaps(double latitude, double longitude) async {
    final uri = Uri.parse('https://www.google.com/maps?q=$latitude,$longitude');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _formatTime(int timestamp) {
    return TimestampUtils.formatAfghanistan(timestamp, pattern: 'HH:mm');
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primaryColor),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}

class _HistoryMessageState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String buttonLabel;
  final Future<void> Function() onPressed;

  const _HistoryMessageState({
    required this.icon,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.refresh),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceStatusLogTile extends StatelessWidget {
  final DeviceStatusLogModel log;
  final VoidCallback onTap;

  const _DeviceStatusLogTile({
    required this.log,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor =
        log.isOnline ? AppColors.successColor : AppColors.errorColor;
    final statusLabel = log.isOnline ? 'Online Event' : 'Offline Event';
    final trimmedPlaceName = log.placeName?.trim() ?? '';
    final coordinates = [
      if (log.latitude != null) log.latitude!.toStringAsFixed(6),
      if (log.longitude != null) log.longitude!.toStringAsFixed(6),
    ].join(', ');
    final subtitle = trimmedPlaceName.isNotEmpty
        ? trimmedPlaceName
        : coordinates.isNotEmpty
            ? coordinates
            : 'Location unavailable';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accentColor.withValues(alpha: 0.18)),
      ),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: accentColor,
                child: Icon(
                  log.isOnline ? Icons.wifi : Icons.wifi_off,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey[700],
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      TimestampUtils.formatAfghanistan(log.timestamp),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.map_outlined, color: accentColor, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceStatusEventSection extends StatelessWidget {
  final String title;
  final String emptyMessage;
  final Color accentColor;
  final IconData icon;
  final List<DeviceStatusLogModel> logs;
  final ValueChanged<DeviceStatusLogModel> onTapLog;

  const _DeviceStatusEventSection({
    required this.title,
    required this.emptyMessage,
    required this.accentColor,
    required this.icon,
    required this.logs,
    required this.onTapLog,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: accentColor,
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${logs.length}',
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (logs.isEmpty)
            _HistoryInlineMessage(message: emptyMessage)
          else
            Column(
              children: [
                for (var index = 0; index < logs.length; index++) ...[
                  _DeviceStatusLogTile(
                    log: logs[index],
                    onTap: () => onTapLog(logs[index]),
                  ),
                  if (index < logs.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusMapPreview extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String? placeName;
  final Color markerColor;
  final String markerTitle;

  const _StatusMapPreview({
    required this.latitude,
    required this.longitude,
    required this.placeName,
    required this.markerColor,
    required this.markerTitle,
  });

  @override
  Widget build(BuildContext context) {
    final position = LatLng(latitude, longitude);
    final marker = Marker(
      markerId: MarkerId('$markerTitle-$latitude-$longitude'),
      position: position,
      infoWindow: InfoWindow(
        title: markerTitle,
        snippet: placeName?.trim().isNotEmpty == true
            ? placeName!.trim()
            : '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 180,
        child: GoogleMapAvailabilityGuard(
          mapBuilder: (_) => GoogleMap(
            initialCameraPosition: CameraPosition(
              target: position,
              zoom: 15,
            ),
            markers: {marker},
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            scrollGesturesEnabled: false,
            zoomGesturesEnabled: false,
          ),
          fallbackBuilder: (_) => _StatusMapFallback(
            latitude: latitude,
            longitude: longitude,
            markerColor: markerColor,
            placeName: placeName,
          ),
        ),
      ),
    );
  }
}

class _StatusMapFallback extends StatelessWidget {
  final double latitude;
  final double longitude;
  final Color markerColor;
  final String? placeName;

  const _StatusMapFallback({
    required this.latitude,
    required this.longitude,
    required this.markerColor,
    required this.placeName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            markerColor.withValues(alpha: 0.16),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: markerColor,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Map Preview',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            placeName?.trim().isNotEmpty == true
                ? placeName!.trim()
                : 'Location available',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _HistoryInlineMessage extends StatelessWidget {
  final String message;

  const _HistoryInlineMessage({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _StatusDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatusDetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryEventTile extends StatelessWidget {
  final HistoryEventModel event;
  final String childName;

  const _HistoryEventTile({
    required this.event,
    required this.childName,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final offlineSummary = _offlineLocationSummary();
    final onlineSummary = _onlineLocationSummary();
    final hasMapLocations = _primaryCoordinates != null;
    final resolvedMessage = _resolvedHistoryMessage(l10n);
    final primaryLocationSummary = _isOfflineEvent
        ? offlineSummary
        : _isOnlineEvent
            ? onlineSummary
            : null;
    final accentColor = _eventColor(event.type);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: InkWell(
        onTap: hasMapLocations ? () => _showLocationActions(context) : null,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: accentColor,
                child: Icon(
                  _eventIcon(event.type),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _eventLabel(l10n, event.type),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      resolvedMessage,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatTimestamp(event.timestamp),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (primaryLocationSummary != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${_isOfflineEvent ? l10n.offline : l10n.online}: $primaryLocationSummary',
                        style: TextStyle(
                          fontSize: 12,
                          color: accentColor.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                hasMapLocations
                    ? Icons.map_outlined
                    : Icons.chevron_right_rounded,
                color: Colors.black54,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _isOfflineEvent =>
      event.type.toUpperCase() == 'DEVICE_DISCONNECTED' ||
      event.type.toUpperCase() == 'DEVICE_OFFLINE';

  bool get _isOnlineEvent =>
      event.type.toUpperCase() == 'DEVICE_RECONNECTED' ||
      event.type.toUpperCase() == 'DEVICE_ONLINE';

  bool get _isConnectionEvent => _isOfflineEvent || _isOnlineEvent;

  bool get _supportsDetails {
    switch (event.type.toUpperCase()) {
      case 'DEVICE_DISCONNECTED':
      case 'DEVICE_RECONNECTED':
      case 'DEVICE_OFFLINE':
      case 'DEVICE_ONLINE':
      case 'DEVICE_STATUS':
        return true;
      default:
        return false;
    }
  }

  String _resolvedHistoryMessage(AppLocalizations l10n) {
    final localizedMessage = event.message.trim().isEmpty
        ? _eventLabel(l10n, event.type)
        : localizeRawMessage(l10n, event.message);

    if (_isOfflineEvent && _offlineLocationSummary() != null) {
      return '${l10n.deviceOffline} at ${_offlineLocationSummary()!}';
    }

    if (_isOnlineEvent && _onlineLocationSummary() != null) {
      return '${l10n.deviceOnline} at ${_onlineLocationSummary()!}';
    }

    return localizedMessage;
  }

  ({double latitude, double longitude})? get _primaryCoordinates {
    if (_isOfflineEvent) {
      return _offlineCoordinates;
    }
    if (_isOnlineEvent) {
      return _onlineCoordinates;
    }
    if (event.latitude != null && event.longitude != null) {
      return (latitude: event.latitude!, longitude: event.longitude!);
    }
    return null;
  }

  String? _offlineLocationSummary() {
    final lastKnownAddress = _readString(
      event.metadata,
      ['lastKnownAddress', 'locationText', 'placeName', 'place_name'],
    );
    if (lastKnownAddress != null && lastKnownAddress.isNotEmpty) {
      return lastKnownAddress;
    }

    final lastKnownLat = _readDouble(event.metadata, ['lastKnownLat']);
    final lastKnownLng = _readDouble(event.metadata, ['lastKnownLng']);
    if (lastKnownLat != null && lastKnownLng != null) {
      return _formatCoordinates(lastKnownLat, lastKnownLng);
    }

    if (_isOfflineEvent) {
      if (event.latitude != null && event.longitude != null) {
        return _formatCoordinates(event.latitude!, event.longitude!);
      }
    }

    return null;
  }

  ({double latitude, double longitude})? get _offlineCoordinates {
    final lastKnownLat = _readDouble(event.metadata, ['lastKnownLat']);
    final lastKnownLng = _readDouble(event.metadata, ['lastKnownLng']);
    if (lastKnownLat != null && lastKnownLng != null) {
      return (latitude: lastKnownLat, longitude: lastKnownLng);
    }

    if (_isOfflineEvent) {
      if (event.latitude != null && event.longitude != null) {
        return (latitude: event.latitude!, longitude: event.longitude!);
      }
    }

    return null;
  }

  String? _onlineLocationSummary() {
    final reconnectedAddress = _readString(
      event.metadata,
      ['reconnectedAddress', 'locationText', 'placeName', 'place_name'],
    );
    if (reconnectedAddress != null && reconnectedAddress.isNotEmpty) {
      return reconnectedAddress;
    }

    final reconnectedLat = _readDouble(event.metadata, ['reconnectedLat']);
    final reconnectedLng = _readDouble(event.metadata, ['reconnectedLng']);
    if (reconnectedLat != null && reconnectedLng != null) {
      return _formatCoordinates(reconnectedLat, reconnectedLng);
    }

    if (_isOnlineEvent) {
      if (event.latitude != null && event.longitude != null) {
        return _formatCoordinates(event.latitude!, event.longitude!);
      }
    }

    return null;
  }

  ({double latitude, double longitude})? get _onlineCoordinates {
    final reconnectedLat = _readDouble(event.metadata, ['reconnectedLat']);
    final reconnectedLng = _readDouble(event.metadata, ['reconnectedLng']);
    if (reconnectedLat != null && reconnectedLng != null) {
      return (latitude: reconnectedLat, longitude: reconnectedLng);
    }

    if (_isOnlineEvent) {
      if (event.latitude != null && event.longitude != null) {
        return (latitude: event.latitude!, longitude: event.longitude!);
      }
    }

    return null;
  }

  void _showLocationActions(BuildContext context) {
    final primaryCoordinates = _primaryCoordinates;
    final offlineCoordinates = _offlineCoordinates;
    final onlineCoordinates = _onlineCoordinates;

    if (!_isConnectionEvent && primaryCoordinates != null) {
      _openMapLocation(
        context,
        latitude: primaryCoordinates.latitude,
        longitude: primaryCoordinates.longitude,
      );
      return;
    }

    if (_isOfflineEvent && offlineCoordinates != null) {
      _openMapLocation(
        context,
        latitude: offlineCoordinates.latitude,
        longitude: offlineCoordinates.longitude,
      );
      return;
    }

    if (_isOnlineEvent && onlineCoordinates != null) {
      _openMapLocation(
        context,
        latitude: onlineCoordinates.latitude,
        longitude: onlineCoordinates.longitude,
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _eventLabel(AppLocalizations.of(context)!, event.type),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatTimestamp(event.timestamp),
                  style: TextStyle(color: Colors.grey[600]),
                ),
                if (offlineCoordinates != null) ...[
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.errorColor,
                      child: Icon(Icons.portable_wifi_off,
                          color: Colors.white, size: 20),
                    ),
                    title: Text(AppLocalizations.of(context)!.offline),
                    subtitle: Text(_formatCoordinates(
                      offlineCoordinates.latitude,
                      offlineCoordinates.longitude,
                    )),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () {
                      Navigator.pop(context);
                      _openMapLocation(
                        context,
                        latitude: offlineCoordinates.latitude,
                        longitude: offlineCoordinates.longitude,
                      );
                    },
                  ),
                ],
                if (onlineCoordinates != null) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.successColor,
                      child: Icon(Icons.wifi, color: Colors.white, size: 20),
                    ),
                    title: Text(AppLocalizations.of(context)!.online),
                    subtitle: Text(_formatCoordinates(
                      onlineCoordinates.latitude,
                      onlineCoordinates.longitude,
                    )),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () {
                      Navigator.pop(context);
                      _openMapLocation(
                        context,
                        latitude: onlineCoordinates.latitude,
                        longitude: onlineCoordinates.longitude,
                      );
                    },
                  ),
                ],
                if (_supportsDetails) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showEventDetails(context);
                    },
                    icon: const Icon(Icons.info_outline),
                    label: const Text('More Details'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEventDetails(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final disconnectedAt = _readTimestamp(
          event.metadata,
          ['disconnectedAt', 'previousOfflineAt'],
        );
        final reconnectedAt = _readTimestamp(event.metadata, ['reconnectedAt']);
        final lastKnownTimestamp = _readTimestamp(
          event.metadata,
          ['lastKnownTimestamp'],
        );
        final reconnectedTimestamp = _readTimestamp(
          event.metadata,
          ['reconnectedTimestamp'],
        );
        final durationOfflineMs = _readInt(
          event.metadata,
          ['durationOfflineMs'],
        );
        final offlineEventType = event.type.toUpperCase();
        final lastKnownLat = _readDouble(event.metadata, ['lastKnownLat']) ??
            ((offlineEventType == 'DEVICE_DISCONNECTED' ||
                    offlineEventType == 'DEVICE_OFFLINE')
                ? event.latitude
                : null);
        final lastKnownLng = _readDouble(event.metadata, ['lastKnownLng']) ??
            ((offlineEventType == 'DEVICE_DISCONNECTED' ||
                    offlineEventType == 'DEVICE_OFFLINE')
                ? event.longitude
                : null);
        final lastKnownAccuracy = _readDouble(
          event.metadata,
          ['lastKnownAccuracy'],
        );
        final lastKnownAddress = _readString(
          event.metadata,
          ['lastKnownAddress'],
        );
        final reconnectedLat =
            _readDouble(event.metadata, ['reconnectedLat']) ??
                ((offlineEventType == 'DEVICE_RECONNECTED' ||
                        offlineEventType == 'DEVICE_ONLINE')
                    ? event.latitude
                    : null);
        final reconnectedLng =
            _readDouble(event.metadata, ['reconnectedLng']) ??
                ((offlineEventType == 'DEVICE_RECONNECTED' ||
                        offlineEventType == 'DEVICE_ONLINE')
                    ? event.longitude
                    : null);
        final reconnectedAccuracy = _readDouble(
          event.metadata,
          ['reconnectedAccuracy'],
        );
        final reconnectedAddress = _readString(
          event.metadata,
          ['reconnectedAddress'],
        );
        final reason = _readString(event.metadata, ['reason']);

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _eventColor(event.type),
                      child: Icon(
                        _eventIcon(event.type),
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _eventLabel(l10n, event.type),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatTimestamp(event.timestamp),
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _DetailSection(
                  title: 'Overview',
                  children: [
                    _DetailRow(label: 'Child', value: childName),
                    _DetailRow(label: l10n.childId, value: event.childId),
                    if (event.trackingKey.trim().isNotEmpty)
                      _DetailRow(
                        label: 'Tracking Key',
                        value: event.trackingKey,
                      ),
                    _DetailRow(
                      label: 'Message',
                      value: event.message.trim().isEmpty
                          ? l10n.noMessage
                          : localizeRawMessage(l10n, event.message),
                    ),
                    if (reason != null && reason.isNotEmpty)
                      _DetailRow(label: 'Reason', value: reason),
                  ],
                ),
                if (_isOfflineEvent &&
                    (disconnectedAt != null ||
                        lastKnownTimestamp != null ||
                        lastKnownLat != null ||
                        lastKnownLng != null)) ...[
                  const SizedBox(height: 14),
                  _DetailSection(
                    title: l10n.offline,
                    children: [
                      if (disconnectedAt != null)
                        _DetailRow(
                          label: 'Disconnected At',
                          value: _formatTimestamp(disconnectedAt),
                        ),
                      if (lastKnownTimestamp != null)
                        _DetailRow(
                          label: 'Last Known Time',
                          value: _formatTimestamp(lastKnownTimestamp),
                        ),
                      if (lastKnownLat != null && lastKnownLng != null)
                        _DetailRow(
                          label: l10n.location,
                          value: _formatCoordinates(lastKnownLat, lastKnownLng),
                        ),
                      if (lastKnownAccuracy != null)
                        _DetailRow(
                          label: 'Accuracy',
                          value: '${lastKnownAccuracy.toStringAsFixed(1)} m',
                        ),
                      if (lastKnownAddress != null &&
                          lastKnownAddress.isNotEmpty)
                        _DetailRow(
                          label: 'Address',
                          value: lastKnownAddress,
                        ),
                      if (lastKnownLat != null && lastKnownLng != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton.icon(
                            onPressed: () => _openMapLocation(
                              context,
                              latitude: lastKnownLat,
                              longitude: lastKnownLng,
                            ),
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('Open Offline Location'),
                          ),
                        ),
                    ],
                  ),
                ],
                if (_isOnlineEvent &&
                    (reconnectedAt != null ||
                        reconnectedTimestamp != null ||
                        reconnectedLat != null ||
                        reconnectedLng != null)) ...[
                  const SizedBox(height: 14),
                  _DetailSection(
                    title: l10n.online,
                    children: [
                      if (reconnectedAt != null)
                        _DetailRow(
                          label: 'Reconnected At',
                          value: _formatTimestamp(reconnectedAt),
                        ),
                      if (reconnectedTimestamp != null)
                        _DetailRow(
                          label: 'Reconnect Time',
                          value: _formatTimestamp(reconnectedTimestamp),
                        ),
                      if (durationOfflineMs != null)
                        _DetailRow(
                          label: 'Offline Duration',
                          value: _formatDuration(durationOfflineMs),
                        ),
                      if (reconnectedLat != null && reconnectedLng != null)
                        _DetailRow(
                          label: l10n.location,
                          value: _formatCoordinates(
                              reconnectedLat, reconnectedLng),
                        ),
                      if (reconnectedAccuracy != null)
                        _DetailRow(
                          label: 'Accuracy',
                          value: '${reconnectedAccuracy.toStringAsFixed(1)} m',
                        ),
                      if (reconnectedAddress != null &&
                          reconnectedAddress.isNotEmpty)
                        _DetailRow(
                          label: 'Address',
                          value: reconnectedAddress,
                        ),
                      if (reconnectedLat != null && reconnectedLng != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton.icon(
                            onPressed: () => _openMapLocation(
                              context,
                              latitude: reconnectedLat,
                              longitude: reconnectedLng,
                            ),
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('Open Online Location'),
                          ),
                        ),
                    ],
                  ),
                ],
                if ((_isOfflineEvent &&
                        disconnectedAt == null &&
                        lastKnownTimestamp == null &&
                        lastKnownLat == null &&
                        lastKnownLng == null) ||
                    (_isOnlineEvent &&
                        reconnectedAt == null &&
                        reconnectedTimestamp == null &&
                        reconnectedLat == null &&
                        reconnectedLng == null) ||
                    (!_isConnectionEvent &&
                        disconnectedAt == null &&
                        reconnectedAt == null &&
                        lastKnownTimestamp == null &&
                        reconnectedTimestamp == null &&
                        lastKnownLat == null &&
                        reconnectedLat == null))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l10n.noAdditionalDetailsAvailable,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _openMapLocation(
    BuildContext context, {
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open map location.')),
      );
    }
  }

  static int? _readTimestamp(Map<String, dynamic> metadata, List<String> keys) {
    for (final key in keys) {
      final value = TimestampUtils.normalizeEpochMilliseconds(metadata[key]);
      if (value != null && value > 0) {
        return value;
      }
    }
    return null;
  }

  static int? _readInt(Map<String, dynamic> metadata, List<String> keys) {
    for (final key in keys) {
      final value = int.tryParse('${metadata[key]}');
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  static double? _readDouble(Map<String, dynamic> metadata, List<String> keys) {
    for (final key in keys) {
      final value = double.tryParse('${metadata[key]}');
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  static String? _readString(Map<String, dynamic> metadata, List<String> keys) {
    for (final key in keys) {
      final value = metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static String _formatCoordinates(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  static String _formatDuration(int durationMs) {
    final totalSeconds = (durationMs / 1000).round();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final parts = <String>[];

    if (hours > 0) {
      parts.add('${hours}h');
    }
    if (minutes > 0) {
      parts.add('${minutes}m');
    }
    if (seconds > 0 && hours == 0) {
      parts.add('${seconds}s');
    }

    return parts.isEmpty ? '0s' : parts.join(' ');
  }

  static IconData _eventIcon(String type) {
    switch (type.toUpperCase()) {
      case 'GEOFENCE_BREACH':
      case 'SAFE_ZONE_EXIT':
        return Icons.exit_to_app;
      case 'GEOFENCE_RETURN':
      case 'SAFE_ZONE_ENTER':
        return Icons.check_circle;
      case 'DEVICE_ONLINE':
      case 'DEVICE_RECONNECTED':
        return Icons.wifi;
      case 'DEVICE_OFFLINE':
      case 'DEVICE_DISCONNECTED':
      case 'DEVICE_STATUS':
        return Icons.wifi_off;
      case 'SAFE_ZONE_CREATED':
      case 'SAFE_ZONE_UPDATED':
        return Icons.location_on;
      case 'SOS':
        return Icons.warning;
      case 'BATTERY_LOW':
        return Icons.battery_alert;
      default:
        return Icons.info;
    }
  }

  static Color _eventColor(String type) {
    switch (type.toUpperCase()) {
      case 'GEOFENCE_BREACH':
      case 'SAFE_ZONE_EXIT':
        return AppColors.warningColor;
      case 'GEOFENCE_RETURN':
      case 'SAFE_ZONE_ENTER':
        return AppColors.successColor;
      case 'DEVICE_ONLINE':
      case 'DEVICE_RECONNECTED':
        return AppColors.successColor;
      case 'DEVICE_OFFLINE':
      case 'DEVICE_DISCONNECTED':
      case 'DEVICE_STATUS':
        return AppColors.errorColor;
      case 'SAFE_ZONE_CREATED':
      case 'SAFE_ZONE_UPDATED':
        return Colors.deepPurple;
      case 'SOS':
        return Colors.red;
      case 'BATTERY_LOW':
        return Colors.orange;
      default:
        return AppColors.primaryColor;
    }
  }

  static String _eventLabel(AppLocalizations l10n, String type) {
    switch (type.toUpperCase()) {
      case 'GEOFENCE_BREACH':
        return l10n.childOutOfSafeZone;
      case 'GEOFENCE_RETURN':
        return l10n.childBackInSafeZone;
      case 'DEVICE_DISCONNECTED':
      case 'DEVICE_OFFLINE':
        return l10n.deviceOffline;
      case 'DEVICE_RECONNECTED':
      case 'DEVICE_ONLINE':
        return l10n.deviceOnline;
      case 'SAFE_ZONE_CREATED':
        return 'Safe Zone Created';
      case 'SAFE_ZONE_UPDATED':
        return 'Safe Zone Updated';
      case 'DEVICE_STATUS':
        return 'Device Status';
      case 'BATTERY_LOW':
        return l10n.lowBattery;
      default:
        return localizeAlertTypeLabel(l10n, type);
    }
  }

  static String _formatTimestamp(int timestamp) {
    return TimestampUtils.formatAfghanistan(timestamp);
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
