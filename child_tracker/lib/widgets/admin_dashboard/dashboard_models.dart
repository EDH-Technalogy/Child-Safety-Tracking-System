import 'package:flutter/material.dart';

class DashboardMetric {
  const DashboardMetric({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.badgeLabel,
    this.trend,
    this.onTap,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final String? badgeLabel;
  final DashboardTrend? trend;
  final VoidCallback? onTap;
}

class DashboardTrend {
  const DashboardTrend({
    required this.delta,
    required this.label,
    this.positiveIsGood = true,
  });

  final int delta;
  final String label;
  final bool positiveIsGood;

  bool get isNeutral => delta == 0;

  bool get isPositive => delta > 0;

  bool get isGood =>
      isNeutral ? true : (positiveIsGood ? isPositive : !isPositive);

  String get signedValue {
    if (delta == 0) {
      return '0';
    }
    return '${delta > 0 ? '+' : ''}$delta';
  }
}

class DashboardSliceData {
  const DashboardSliceData({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

class DashboardPoint {
  const DashboardPoint({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;
}

class DashboardActivityItem {
  const DashboardActivityItem({
    required this.title,
    required this.description,
    required this.timestampLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.icon,
    required this.accentColor,
    this.metadata,
  });

  final String title;
  final String description;
  final String timestampLabel;
  final String statusLabel;
  final Color statusColor;
  final IconData icon;
  final Color accentColor;
  final String? metadata;
}

class DashboardQuickAction {
  const DashboardQuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
}
