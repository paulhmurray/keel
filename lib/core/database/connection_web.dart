import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

LazyDatabase createConnection() {
  return LazyDatabase(() async => driftDatabase(
        name: 'keel',
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.dart.js'),
        ),
      ));
}

QueryExecutor createMemoryConnection() {
  throw UnsupportedError('In-memory database not available on web');
}
