import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/admin_api_service.dart';
import '../../utils/localization_helpers.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_users_screen.dart';
import 'admin_devices_screen.dart';
import 'admin_children_screen.dart';
import 'admin_alerts_screen.dart';
import 'admin_logs_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminApiService _adminApi = AdminApiService();
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final stats = await _adminApi.getSystemStats();
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: Text(l10n.adminPanelTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(
                    '${l10n.error}: ${localizeRawMessage(l10n, _error!)}',
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadStats,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Stats Grid
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1.35,
                          children: [
                            _StatCard(
                              title: l10n.totalUsers,
                              value: '${_stats?['total_users'] ?? 0}',
                              icon: Icons.people,
                              color: Colors.blue,
                            ),
                            _StatCard(
                              title: l10n.activeUsers,
                              value: '${_stats?['active_users'] ?? 0}',
                              icon: Icons.people_alt,
                              color: Colors.green,
                            ),
                            _StatCard(
                              title: l10n.totalDevices,
                              value: '${_stats?['total_devices'] ?? 0}',
                              icon: Icons.phone_android,
                              color: Colors.orange,
                            ),
                            _StatCard(
                              title: l10n.activeDevices,
                              value: '${_stats?['active_devices'] ?? 0}',
                              icon: Icons.gps_fixed,
                              color: Colors.purple,
                            ),
                            _StatCard(
                              title: l10n.totalChildren,
                              value: '${_stats?['total_children'] ?? 0}',
                              icon: Icons.child_care,
                              color: Colors.teal,
                            ),
                            _StatCard(
                              title: l10n.totalAlerts,
                              value: '${_stats?['total_alerts'] ?? 0}',
                              icon: Icons.notifications,
                              color: Colors.red,
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // Quick Actions
                        Text(
                          l10n.management,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        _MenuCard(
                          title: l10n.userManagement,
                          subtitle: l10n.viewAddEditDeleteUsers,
                          icon: Icons.people,
                          color: Colors.blue,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminUsersScreen(),
                              ),
                            );
                          },
                        ),
                        _MenuCard(
                          title: l10n.deviceManagement,
                          subtitle: l10n.viewAddEditDeleteDevices,
                          icon: Icons.phone_android,
                          color: Colors.orange,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminDevicesScreen(),
                              ),
                            );
                          },
                        ),
                        _MenuCard(
                          title: l10n.childrenManagement,
                          subtitle: l10n.viewDeleteChildren,
                          icon: Icons.child_care,
                          color: Colors.teal,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminChildrenScreen(),
                              ),
                            );
                          },
                        ),
                        _MenuCard(
                          title: l10n.alertsManagement,
                          subtitle: l10n.viewDeleteAlerts,
                          icon: Icons.notifications,
                          color: Colors.red,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminAlertsScreen(),
                              ),
                            );
                          },
                        ),
                        _MenuCard(
                          title: l10n.systemLogs,
                          subtitle: l10n.viewSystemActivity,
                          icon: Icons.history,
                          color: Colors.grey,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminLogsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 28),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
