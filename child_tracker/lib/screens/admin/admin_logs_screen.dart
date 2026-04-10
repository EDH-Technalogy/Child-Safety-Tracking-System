import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/admin_api_service.dart';
import '../../utils/localization_helpers.dart';
import '../../widgets/admin_drawer.dart';

class AdminLogsScreen extends StatefulWidget {
  const AdminLogsScreen({super.key});

  @override
  State<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

class _AdminLogsScreenState extends State<AdminLogsScreen> {
  final AdminApiService _adminApi = AdminApiService();
  List<dynamic> _logs = [];
  final Set<String> _selectedLogKeys = <String>{};
  bool _isLoading = true;
  bool _isMutatingLogs = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final logs = await _adminApi.getSystemLogs(limit: 200);
      final visibleKeys =
          logs.map((log) => _logKey(Map<String, dynamic>.from(log))).toSet();
      setState(() {
        _logs = logs;
        _selectedLogKeys.removeWhere((key) => !visibleKeys.contains(key));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = localizeErrorMessage(context.l10n, e);
        _isLoading = false;
      });
    }
  }

  String _logCollection(Map<String, dynamic> log) {
    final explicitCollection = log['logCollection']?.toString();
    if (explicitCollection != null && explicitCollection.isNotEmpty) {
      return explicitCollection;
    }
    return log['source']?.toString() == 'legacy'
        ? 'activity_log'
        : 'audit_logs';
  }

  String _logId(Map<String, dynamic> log) {
    return (log['id'] ?? '').toString();
  }

  String _logKey(Map<String, dynamic> log) {
    return '${_logCollection(log)}:${_logId(log)}';
  }

  bool _isSelected(Map<String, dynamic> log) {
    return _selectedLogKeys.contains(_logKey(log));
  }

  bool get _hasSelectedLogs => _selectedLogKeys.isNotEmpty;

  bool get _allVisibleSelected {
    if (_logs.isEmpty) return false;
    return _logs.every(
      (log) =>
          _selectedLogKeys.contains(_logKey(Map<String, dynamic>.from(log))),
    );
  }

  void _toggleLogSelection(Map<String, dynamic> log) {
    final key = _logKey(log);
    setState(() {
      if (_selectedLogKeys.contains(key)) {
        _selectedLogKeys.remove(key);
      } else {
        _selectedLogKeys.add(key);
      }
    });
  }

  void _toggleSelectAllVisible() {
    if (_logs.isEmpty) return;

    final visibleKeys =
        _logs.map((log) => _logKey(Map<String, dynamic>.from(log))).toSet();

    setState(() {
      if (_allVisibleSelected) {
        _selectedLogKeys.removeAll(visibleKeys);
      } else {
        _selectedLogKeys.addAll(visibleKeys);
      }
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    String? confirmLabel,
  }) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(confirmLabel ?? l10n.delete),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<void> _deleteLog(Map<String, dynamic> log) async {
    final l10n = context.l10n;
    final confirmed = await _confirmAction(
      title: l10n.deleteLog,
      message: l10n.deleteLogEntryConfirm,
    );
    if (!confirmed) return;

    final logKey = _logKey(log);

    setState(() {
      _isMutatingLogs = true;
    });

    try {
      await _adminApi.deleteSystemLog(
        logId: _logId(log),
        collection: _logCollection(log),
      );

      if (!mounted) return;

      setState(() {
        _logs = _logs.where((entry) {
          final logEntry = Map<String, dynamic>.from(entry);
          return _logKey(logEntry) != logKey;
        }).toList();
        _selectedLogKeys.remove(logKey);
        _isMutatingLogs = false;
      });

      _showSnackBar(l10n.logDeletedSuccessfully);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isMutatingLogs = false;
        });
      }
      _showSnackBar(
        localizeErrorMessage(l10n, e),
        isError: true,
      );
    }
  }

  Future<void> _deleteAllLogs() async {
    final l10n = context.l10n;
    if (_logs.isEmpty) return;

    final confirmed = await _confirmAction(
      title: l10n.deleteAllLogs,
      message: l10n.deleteAllLogsConfirm,
      confirmLabel: l10n.deleteAll,
    );
    if (!confirmed) return;

    setState(() {
      _isMutatingLogs = true;
    });

    try {
      await _adminApi.deleteAllSystemLogs();

      if (!mounted) return;

      setState(() {
        _logs = [];
        _selectedLogKeys.clear();
        _error = null;
        _isMutatingLogs = false;
      });

      _showSnackBar(l10n.allSystemLogsDeletedSuccessfully);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isMutatingLogs = false;
        });
      }
      _showSnackBar(
        localizeErrorMessage(l10n, e),
        isError: true,
      );
    }
  }

  Future<void> _deleteSelectedLogs() async {
    final l10n = context.l10n;
    if (_selectedLogKeys.isEmpty) return;

    final selectedLogs = _logs
        .map((entry) => Map<String, dynamic>.from(entry))
        .where(_isSelected)
        .toList();

    if (selectedLogs.isEmpty) {
      setState(() {
        _selectedLogKeys.clear();
      });
      return;
    }

    final selectedKeys = selectedLogs.map(_logKey).toList();
    debugPrint(
      '[AdminLogsScreen._deleteSelectedLogs] selectedKeys=$selectedKeys',
    );

    final confirmed = await _confirmAction(
      title: l10n.deleteSelectedLogs,
      message:
          '${l10n.deleteSelectedLogsConfirm} (${selectedLogs.length})',
      confirmLabel: l10n.deleteSelected,
    );
    if (!confirmed) return;

    setState(() {
      _isMutatingLogs = true;
    });

    try {
      for (final log in selectedLogs) {
        await _adminApi.deleteSystemLog(
          logId: _logId(log),
          collection: _logCollection(log),
        );
      }

      if (!mounted) return;

      final selectedKeySet = selectedKeys.toSet();
      setState(() {
        _logs = _logs.where((entry) {
          final logEntry = Map<String, dynamic>.from(entry);
          return !selectedKeySet.contains(_logKey(logEntry));
        }).toList();
        _selectedLogKeys.removeAll(selectedKeySet);
        _isMutatingLogs = false;
      });

      _showSnackBar('${selectedLogs.length} ${l10n.selectedLogsDeleted}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isMutatingLogs = false;
        });
      }
      await _loadLogs();
      _showSnackBar(
        localizeErrorMessage(l10n, e),
        isError: true,
      );
    }
  }

  String _eventType(Map<String, dynamic> log) {
    return (log['eventType'] ?? log['event_type'] ?? context.l10n.unknown)
        .toString();
  }

  String _title(Map<String, dynamic> log) {
    final title = log['title']?.toString();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return _eventType(log);
  }

  String _description(Map<String, dynamic> log) {
    return (log['description'] ?? context.l10n.noDescriptionAvailable)
        .toString();
  }

  String _status(Map<String, dynamic> log) {
    return (log['status'] ?? log['result'] ?? context.l10n.unknown).toString();
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      final millis = timestamp is int
          ? timestamp
          : int.tryParse(timestamp.toString()) ?? 0;
      final date = DateTime.fromMillisecondsSinceEpoch(millis);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'N/A';
    }
  }

  String _formatActor(dynamic actor) {
    if (actor is! Map) return context.l10n.unavailable;
    final parts = [
      if (actor['name'] != null && actor['name'].toString().isNotEmpty)
        actor['name'].toString(),
      if (actor['email'] != null && actor['email'].toString().isNotEmpty)
        actor['email'].toString(),
      if (actor['role'] != null && actor['role'].toString().isNotEmpty)
        '${context.l10n.role}: ${actor['role']}',
    ];
    return parts.isEmpty ? context.l10n.unavailable : parts.join(' | ');
  }

  String _formatTarget(dynamic target) {
    if (target is! Map) return context.l10n.unavailable;
    final parts = [
      if (target['name'] != null && target['name'].toString().isNotEmpty)
        target['name'].toString(),
      if (target['email'] != null && target['email'].toString().isNotEmpty)
        target['email'].toString(),
      if (target['imei'] != null && target['imei'].toString().isNotEmpty)
        '${context.l10n.imei}: ${target['imei']}',
      if (target['type'] != null && target['type'].toString().isNotEmpty)
        'Type: ${target['type']}',
      if (target['id'] != null && target['id'].toString().isNotEmpty)
        'ID: ${target['id']}',
    ];
    return parts.isEmpty ? context.l10n.unavailable : parts.join(' | ');
  }

  String _prettyJson(dynamic value) {
    if (value == null) return context.l10n.noAdditionalDetailsAvailable;
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value.isEmpty ? context.l10n.unavailable : value,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _showLogDetails(Map<String, dynamic> log) {
    final metadata = log['metadata'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_title(log)),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow(context.l10n.eventType, _eventType(log)),
                _buildDetailRow(context.l10n.description, _description(log)),
                _buildDetailRow(
                  context.l10n.dateTime,
                  _formatTimestamp(log['timestamp'] ?? log['created_at']),
                ),
                _buildDetailRow(context.l10n.actor, _formatActor(log['performedBy'])),
                _buildDetailRow(context.l10n.target, _formatTarget(log['target'])),
                _buildDetailRow(context.l10n.status, _status(log)),
                _buildDetailRow(
                  context.l10n.source,
                  (log['source'] ?? context.l10n.unknown).toString(),
                ),
                _buildDetailRow(
                  context.l10n.changedFields,
                  metadata is Map && metadata['changedFields'] is List
                      ? (metadata['changedFields'] as List).join(', ')
                      : context.l10n.noData,
                ),
                _buildDetailRow(
                  context.l10n.additionalMetadata,
                  _prettyJson(metadata),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: Text(l10n.systemLogsTitle),
        actions: [
          if (_logs.isNotEmpty)
            IconButton(
              icon: Icon(
                _allVisibleSelected ? Icons.deselect : Icons.select_all,
              ),
              tooltip: _allVisibleSelected
                  ? l10n.clearSelection
                  : l10n.selectAll,
              onPressed: _isLoading || _isMutatingLogs
                  ? null
                  : _toggleSelectAllVisible,
            ),
          if (_logs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: _hasSelectedLogs
                  ? l10n.deleteSelected
                  : l10n.deleteAll,
              onPressed: _isLoading || _isMutatingLogs
                  ? null
                  : (_hasSelectedLogs ? _deleteSelectedLogs : _deleteAllLogs),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isMutatingLogs ? null : _loadLogs,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('${l10n.error}: $_error'))
              : _logs.isEmpty
                  ? Center(child: Text(l10n.noLogsFound))
                  : RefreshIndicator(
                      onRefresh: _loadLogs,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = Map<String, dynamic>.from(_logs[index]);
                          final isSelected = _isSelected(log);
                          return Card(
                            color: isSelected
                                ? const Color.fromRGBO(33, 150, 243, 0.04)
                                : null,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap: _hasSelectedLogs
                                  ? () => _toggleLogSelection(log)
                                  : () => _showLogDetails(log),
                              onLongPress: () => _toggleLogSelection(log),
                              leading: CircleAvatar(
                                backgroundColor: isSelected
                                    ? const Color.fromRGBO(33, 150, 243, 0.1)
                                    : const Color.fromRGBO(158, 158, 158, 0.1),
                                child: Icon(
                                  isSelected ? Icons.check : Icons.history,
                                  color: isSelected ? Colors.blue : Colors.grey,
                                ),
                              ),
                              title: Text(
                                _title(log),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _description(log),
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTimestamp(
                                      log['timestamp'] ?? log['created_at'],
                                    ),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: Colors.red[400],
                                ),
                                tooltip: l10n.deleteLog,
                                onPressed: _isMutatingLogs
                                    ? null
                                    : () => _deleteLog(log),
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
