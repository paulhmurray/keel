import 'dart:io';

bool directoryExists(String path) => Directory(path).existsSync();
