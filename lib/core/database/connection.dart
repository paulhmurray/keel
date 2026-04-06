// Platform-conditional database connection factory.
// Uses conditional imports so that dart:ffi (native) is never referenced on web.
import 'package:drift/drift.dart';
import 'connection_native.dart' if (dart.library.html) 'connection_web.dart';

/// Returns the platform-appropriate [QueryExecutor] for the Keel database.
LazyDatabase openAppConnection() => createConnection();

/// Returns an in-memory [QueryExecutor] for testing (native only).
QueryExecutor openMemoryConnection() => createMemoryConnection();
