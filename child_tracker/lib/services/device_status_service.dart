import 'package:cloud_firestore/cloud_firestore.dart' hide Query;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/device_status_model.dart';
import '../utils/constants.dart';
import '../utils/firebase_bootstrap.dart';
import 'realtime_database_auth_service.dart';

class DeviceStatusService {
  Stream<DeviceStatusCardModel?> watchDeviceStatusCard(String childId) async* {
    await FirebaseBootstrap.ensureInitialized();
    final ref = FirebaseFirestore.instance
        .collection('device_status_cards')
        .doc(childId);
    yield* ref.snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return null;
      }
      return DeviceStatusCardModel.fromJson(data);
    });
  }

  Stream<List<DeviceStatusLogModel>> watchDeviceStatusLogs(
    String childId, {
    int limit = 20,
  }) async* {
    final database = await _database();
    final ref = database
        .ref('device_status_logs/$childId')
        .orderByChild('timestamp')
        .limitToLast(limit);

    yield* _watchLogQuery(ref);
  }

  Stream<List<DeviceStatusLogModel>> watchDeviceStatusLogsForRange(
    String childId, {
    required int startTimestamp,
    required int endTimestamp,
  }) async* {
    final database = await _database();
    final ref = database
        .ref('device_status_logs/$childId')
        .orderByChild('timestamp')
        .startAt(startTimestamp)
        .endAt(endTimestamp);

    yield* _watchLogQuery(ref);
  }

  Stream<List<DeviceStatusLogModel>> _watchLogQuery(Query query) {
    return query.onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) {
        return const <DeviceStatusLogModel>[];
      }

      final logs = raw.entries
          .map((entry) {
            try {
              final value = entry.value;
              final map = value is Map<String, dynamic>
                  ? value
                  : value is Map
                      ? Map<String, dynamic>.from(
                          value.map(
                            (key, nestedValue) => MapEntry(
                              key.toString(),
                              nestedValue,
                            ),
                          ),
                        )
                      : <String, dynamic>{};
              return DeviceStatusLogModel.fromJson({
                'id': entry.key.toString(),
                ...map,
              });
            } catch (_) {
              return null;
            }
          })
          .whereType<DeviceStatusLogModel>()
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return logs;
    });
  }

  Future<FirebaseDatabase> _database() async {
    await FirebaseBootstrap.ensureInitialized();
    await RealtimeDatabaseAuthService.ensureSignedIn();
    return FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: AppConstants.firebaseDatabaseUrl,
    );
  }
}
