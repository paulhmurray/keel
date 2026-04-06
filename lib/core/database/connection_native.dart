import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

LazyDatabase createConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, 'keel.db'));
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    return NativeDatabase.createInBackground(file);
  });
}

QueryExecutor createMemoryConnection() => NativeDatabase.memory();

