import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../providers/location_provider.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';
import '../utils/timestamp_utils.dart';
import '../models/location_model.dart';
import 'package:intl/intl.dart';

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
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    await locationProvider.getRouteData(
      widget.childId,
      dateStr,
      timezoneOffsetMinutes: _selectedDate.timeZoneOffset.inMinutes,
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
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
          return Column(
            children: [
              _buildDateSelector(context, l10n),
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (locationProvider.isLoading && routeData == null) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (locationProvider.error != null && routeData == null) {
                      return _HistoryMessageState(
                        icon: Icons.error_outline,
                        message: locationProvider.error!,
                        buttonLabel: l10n.retry,
                        onPressed: _loadHistory,
                      );
                    }

                    if (routeData == null || !hasAnyHistory) {
                      return _HistoryMessageState(
                        icon: Icons.location_off,
                        message: l10n.noLocationDataForDate,
                        buttonLabel: l10n.retry,
                        onPressed: _loadHistory,
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: _loadHistory,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          _buildRouteSummaryCard(routeData, l10n),
                          if (routeData.coordinates.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildRoutePlaceholderCard(routeData, l10n),
                            const SizedBox(height: 16),
                            _buildSectionTitle(
                              context,
                              l10n.locationPoints,
                              '${routeData.coordinates.length}',
                            ),
                            const SizedBox(height: 12),
                            ...List.generate(
                              routeData.coordinates.length,
                              (index) {
                                final coord = routeData.coordinates[index];
                                return _LocationTile(
                                  index: index + 1,
                                  coordinate: coord,
                                  isFirst: index == 0,
                                  isLast:
                                      index == routeData.coordinates.length - 1,
                                );
                              },
                            ),
                          ],
                          if (routeData.logs.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildSectionTitle(
                              context,
                              l10n.activityLogs,
                              '${routeData.logs.length}',
                            ),
                            const SizedBox(height: 12),
                            ...routeData.logs.map(
                              (log) => _HistoryEventTile(
                                event: log,
                                childName: widget.childName,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDateSelector(BuildContext context, AppLocalizations l10n) {
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
            onPressed: _selectedDate
                    .isBefore(DateTime.now().subtract(const Duration(days: 1)))
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

  Widget _buildRoutePlaceholderCard(
    RouteDataModel routeData,
    AppLocalizations l10n,
  ) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.map,
                  size: 64,
                  color: AppColors.primaryColor,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.routeMap,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${routeData.coordinates.length} ${l10n.points}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              onPressed: () {},
              child: const Icon(Icons.fullscreen),
            ),
          ),
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

  String _formatTime(int timestamp) {
    final date = TimestampUtils.toLocalDateTime(timestamp);
    if (date == null) {
      return '--';
    }

    return DateFormat('HH:mm').format(date);
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

class _LocationTile extends StatelessWidget {
  final int index;
  final CoordinateModel coordinate;
  final bool isFirst;
  final bool isLast;

  const _LocationTile({
    required this.index,
    required this.coordinate,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isFirst
                    ? AppColors.successColor
                    : (isLast ? AppColors.errorColor : AppColors.primaryColor),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isFirst
                    ? const Icon(Icons.play_arrow,
                        size: 16, color: Colors.white)
                    : isLast
                        ? const Icon(Icons.stop, size: 16, color: Colors.white)
                        : Text(
                            '$index',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10),
                          ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: AppColors.primaryColor.withValues(alpha: 0.3),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTime(coordinate.time),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${AppLocalizations.of(context)!.latitude}: ${coordinate.latitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  '${AppLocalizations.of(context)!.longitude}: ${coordinate.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatTime(int timestamp) {
    final date = TimestampUtils.toLocalDateTime(timestamp);
    if (date == null) {
      return '--';
    }

    return DateFormat('MMM dd, yyyy - HH:mm:ss').format(date);
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

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: _supportsDetails ? () => _showEventDetails(context) : null,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: _eventColor(event.type),
            child: Icon(
              _eventIcon(event.type),
              color: Colors.white,
              size: 18,
            ),
          ),
          title: Text(
            _eventLabel(l10n, event.type),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.message.trim().isEmpty
                    ? _eventLabel(l10n, event.type)
                    : localizeRawMessage(l10n, event.message),
              ),
              const SizedBox(height: 4),
              Text(
                _formatTimestamp(event.timestamp),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (offlineSummary != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${l10n.offline}: $offlineSummary',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              if (onlineSummary != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${l10n.online}: $onlineSummary',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
          ),
          trailing:
              _supportsDetails ? const Icon(Icons.chevron_right_rounded) : null,
          isThreeLine: true,
        ),
      ),
    );
  }

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

  String? _offlineLocationSummary() {
    final lastKnownAddress = _readString(
      event.metadata,
      ['lastKnownAddress', 'locationText'],
    );
    if (lastKnownAddress != null && lastKnownAddress.isNotEmpty) {
      return lastKnownAddress;
    }

    final lastKnownLat = _readDouble(event.metadata, ['lastKnownLat']);
    final lastKnownLng = _readDouble(event.metadata, ['lastKnownLng']);
    if (lastKnownLat != null && lastKnownLng != null) {
      return _formatCoordinates(lastKnownLat, lastKnownLng);
    }

    if (event.type.toUpperCase() == 'DEVICE_DISCONNECTED' ||
        event.type.toUpperCase() == 'DEVICE_OFFLINE') {
      if (event.latitude != null && event.longitude != null) {
        return _formatCoordinates(event.latitude!, event.longitude!);
      }
    }

    return null;
  }

  String? _onlineLocationSummary() {
    final reconnectedAddress = _readString(
      event.metadata,
      ['reconnectedAddress', 'locationText'],
    );
    if (reconnectedAddress != null && reconnectedAddress.isNotEmpty) {
      return reconnectedAddress;
    }

    final reconnectedLat = _readDouble(event.metadata, ['reconnectedLat']);
    final reconnectedLng = _readDouble(event.metadata, ['reconnectedLng']);
    if (reconnectedLat != null && reconnectedLng != null) {
      return _formatCoordinates(reconnectedLat, reconnectedLng);
    }

    if (event.type.toUpperCase() == 'DEVICE_RECONNECTED' ||
        event.type.toUpperCase() == 'DEVICE_ONLINE') {
      if (event.latitude != null && event.longitude != null) {
        return _formatCoordinates(event.latitude!, event.longitude!);
      }
    }

    return null;
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
        final lastKnownLat =
            _readDouble(event.metadata, ['lastKnownLat']) ??
                ((offlineEventType == 'DEVICE_DISCONNECTED' ||
                        offlineEventType == 'DEVICE_OFFLINE')
                    ? event.latitude
                    : null);
        final lastKnownLng =
            _readDouble(event.metadata, ['lastKnownLng']) ??
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
                if (disconnectedAt != null ||
                    lastKnownTimestamp != null ||
                    lastKnownLat != null ||
                    lastKnownLng != null) ...[
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
                if (reconnectedAt != null ||
                    reconnectedTimestamp != null ||
                    reconnectedLat != null ||
                    reconnectedLng != null ||
                    durationOfflineMs != null) ...[
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
                if (disconnectedAt == null &&
                    reconnectedAt == null &&
                    lastKnownTimestamp == null &&
                    reconnectedTimestamp == null &&
                    lastKnownLat == null &&
                    reconnectedLat == null)
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
        return Icons.signal_wifi_statusbar_connected_no_internet_4;
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
        return AppColors.primaryColor;
      case 'DEVICE_OFFLINE':
      case 'DEVICE_DISCONNECTED':
      case 'DEVICE_STATUS':
        return Colors.grey;
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
    final date = TimestampUtils.toLocalDateTime(timestamp);
    if (date == null) {
      return '--';
    }

    return DateFormat('MMM dd, yyyy - HH:mm:ss').format(date);
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
