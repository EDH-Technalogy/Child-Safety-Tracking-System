import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/child_provider.dart';
import '../../utils/constants.dart';
import '../../utils/photo_provider.dart';
import '../../models/child_model.dart';
import '../../widgets/admin_drawer.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final childProvider = Provider.of<ChildProvider>(context, listen: false);

    if (authProvider.user != null) {
      await childProvider.loadChildren(authProvider.user!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: Text(l10n.myChildren),
        backgroundColor: AppColors.primaryColor,
      ),
      body: Consumer2<AuthProvider, ChildProvider>(
        builder: (context, authProvider, childProvider, child) {
          if (childProvider.isLoading) {
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
                    l10n.noChildren,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.addYourFirstChild,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/add-child');
                    },
                    icon: const Icon(Icons.add),
                    label: Text(l10n.addChild),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadChildren,
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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/add-child');
        },
        backgroundColor: AppColors.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final ChildModel child;

  const _ChildCard({required this.child});

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
                          onPressed: () {
                            Provider.of<ChildProvider>(context, listen: false)
                                .selectChild(child);
                            Navigator.pushNamed(context, '/edit-child',
                                arguments: child.id);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${l10n.age}: ${child.age}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: child.status == 'active'
                                ? AppColors.successColor.withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            child.status == 'active'
                                ? l10n.active
                                : l10n.inactive,
                            style: TextStyle(
                              fontSize: 12,
                              color: child.status == 'active'
                                  ? AppColors.successColor
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        if (child.device != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            child.device!.status == 'online'
                                ? Icons.battery_full
                                : Icons.battery_alert,
                            size: 16,
                            color: child.device!.status == 'online'
                                ? AppColors.successColor
                                : AppColors.warningColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${child.device!.batteryLevel}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
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
