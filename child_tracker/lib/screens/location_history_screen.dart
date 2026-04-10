import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/location_provider.dart';
import '../utils/constants.dart';
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
    await locationProvider.getRouteData(widget.childId, dateStr);
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
          if (locationProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              // Date Selector
              Container(
                padding: const EdgeInsets.all(16),
                color: AppColors.primaryColor.withValues(alpha: 0.1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () async {
                        setState(() {
                          _selectedDate =
                              _selectedDate.subtract(const Duration(days: 1));
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
                      onPressed: _selectedDate.isBefore(
                              DateTime.now().subtract(const Duration(days: 1)))
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
              ),

              // Route Summary
              if (locationProvider.routeData != null)
                Container(
                  margin: const EdgeInsets.all(16),
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
                            value:
                                '${locationProvider.routeData!.totalDistanceKm} ${l10n.kilometersShort}',
                          ),
                          _SummaryItem(
                            icon: Icons.location_on,
                            label: l10n.locations,
                            value:
                                '${locationProvider.routeData!.locationCount}',
                          ),
                        ],
                      ),
                      if (locationProvider.routeData!.firstLocationTime >
                          0) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(l10n.start,
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                                Text(
                                  _formatTime(locationProvider
                                      .routeData!.firstLocationTime),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Icon(Icons.arrow_forward, color: Colors.grey),
                            Column(
                              children: [
                                Text(l10n.end,
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                                Text(
                                  _formatTime(locationProvider
                                      .routeData!.lastLocationTime),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

              // Map placeholder
              if (locationProvider.routeData != null &&
                  locationProvider.routeData!.coordinates.isNotEmpty)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
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
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${locationProvider.routeData!.coordinates.length} ${l10n.points}',
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
                            onPressed: () {
                              // View route on map
                            },
                            child: const Icon(Icons.fullscreen),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Location List
              if (locationProvider.routeData == null ||
                  locationProvider.routeData!.coordinates.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_off,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          l10n.noLocationDataForDate,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),

              // Location List (alternative view)
              if (locationProvider.routeData != null &&
                  locationProvider.routeData!.coordinates.isNotEmpty)
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: locationProvider.routeData!.coordinates.length,
                    itemBuilder: (context, index) {
                      final coord =
                          locationProvider.routeData!.coordinates[index];
                      return _LocationTile(
                        index: index + 1,
                        coordinate: coord,
                        isFirst: index == 0,
                        isLast: index ==
                            locationProvider.routeData!.coordinates.length - 1,
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

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
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
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('MMM dd, yyyy - HH:mm:ss').format(date);
  }
}
