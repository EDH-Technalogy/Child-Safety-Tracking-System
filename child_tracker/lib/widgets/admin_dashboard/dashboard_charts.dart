import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'dashboard_models.dart';

class UsersByRoleChart extends StatelessWidget {
  const UsersByRoleChart({
    super.key,
    required this.series,
  });

  final List<DashboardSliceData> series;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final maxValue = series.fold<int>(0, (max, item) => math.max(max, item.value));
    final maxY = maxValue == 0 ? 1.0 : maxValue * 1.25;

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: maxY <= 4 ? 1 : maxY / 4,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: const Color(0xFFE2E8F0),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: maxY <= 4 ? 1 : maxY / 4,
                    getTitlesWidget: (value, meta) => Text(
                      NumberFormat.compact(locale: locale).format(value),
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= series.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SizedBox(
                          width: 64,
                          child: Text(
                            series[index].label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < series.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: series[i].value.toDouble(),
                        width: 26,
                        borderRadius: BorderRadius.circular(12),
                        color: series[i].color,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _LegendWrap(series: series),
      ],
    );
  }
}

class DeviceStatusChart extends StatelessWidget {
  const DeviceStatusChart({
    super.key,
    required this.series,
  });

  final List<DashboardSliceData> series;

  @override
  Widget build(BuildContext context) {
    final total = series.fold<int>(0, (sum, item) => sum + item.value);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumn = constraints.maxWidth < 380;
        final chart = SizedBox(
          width: 180,
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: 48,
                  sectionsSpace: 3,
                  sections: [
                    for (final item in series)
                      PieChartSectionData(
                        color: item.color,
                        value: item.value.toDouble(),
                        title: '',
                        radius: 28,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$total',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF14213D),
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context)!.totalDevices,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ],
          ),
        );

        final legend = Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _LegendWrap(
              series: [
                for (final item in series)
                  DashboardSliceData(
                    label: '${item.label} (${item.value})',
                    value: item.value,
                    color: item.color,
                  ),
              ],
            ),
          ),
        );

        if (useColumn) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              chart,
              const SizedBox(height: 16),
              _LegendWrap(
                series: [
                  for (final item in series)
                    DashboardSliceData(
                      label: '${item.label} (${item.value})',
                      value: item.value,
                      color: item.color,
                    ),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            chart,
            const SizedBox(width: 20),
            legend,
          ],
        );
      },
    );
  }
}

class AlertsByTypeChart extends StatelessWidget {
  const AlertsByTypeChart({
    super.key,
    required this.series,
  });

  final List<DashboardSliceData> series;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final maxValue = series.fold<int>(0, (max, item) => math.max(max, item.value));
    final maxY = maxValue == 0 ? 1.0 : maxValue * 1.25;

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: maxY <= 4 ? 1 : maxY / 4,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: const Color(0xFFE2E8F0),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: maxY <= 4 ? 1 : maxY / 4,
                    getTitlesWidget: (value, meta) => Text(
                      NumberFormat.compact(locale: locale).format(value),
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= series.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SizedBox(
                          width: 70,
                          child: Text(
                            series[index].label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < series.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: series[i].value.toDouble(),
                        width: 22,
                        borderRadius: BorderRadius.circular(12),
                        color: series[i].color,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _LegendWrap(series: series),
      ],
    );
  }
}

class LocationUpdatesChart extends StatelessWidget {
  const LocationUpdatesChart({
    super.key,
    required this.points,
  });

  final List<DashboardPoint> points;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final maxValue = points.fold<int>(0, (max, item) => math.max(max, item.value));
    final maxY = maxValue == 0 ? 1.0 : maxValue * 1.25;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: maxY <= 4 ? 1 : maxY / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: const Color(0xFFE2E8F0),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: maxY <= 4 ? 1 : maxY / 4,
              getTitlesWidget: (value, meta) => Text(
                NumberFormat.compact(locale: locale).format(value),
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    points[index].label,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].value.toDouble()),
            ],
            isCurved: true,
            barWidth: 4,
            color: const Color(0xFF2563EB),
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 4.5,
                color: const Color(0xFF2563EB),
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF2563EB).withValues(alpha: 0.24),
                  const Color(0xFF2563EB).withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendWrap extends StatelessWidget {
  const _LegendWrap({
    required this.series,
  });

  final List<DashboardSliceData> series;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: [
        for (final item in series)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF475569),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
      ],
    );
  }
}
