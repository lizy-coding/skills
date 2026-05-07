// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

/// Checks if a file path points to a generated file.
bool isGeneratedFile(String filePath) {
  return filePath.endsWith('.g.dart') || filePath.endsWith('.mocks.dart');
}

/// Gets modified files from Git.
///
/// Uses defaults for [runProcess] and [fileExists].
Future<List<String>> getModifiedFiles({
  required String packageRoot,
  required String repoRoot,
  List<String>? allowedExtensions,
}) {
  return getModifiedFilesInternal(
    runProcess: Process.run,
    packageRoot: packageRoot,
    repoRoot: repoRoot,
    fileExists: (path) => File(path).existsSync(),
    allowedExtensions: allowedExtensions,
  );
}

/// Gets modified files from Git.
///
/// Exposed for testing.
@visibleForTesting
Future<List<String>> getModifiedFilesInternal({
  required Future<ProcessResult> Function(
    String,
    List<String>, {
    bool runInShell,
    String? workingDirectory,
  })
  runProcess,
  required String packageRoot,
  required String repoRoot,
  required bool Function(String) fileExists,
  List<String>? allowedExtensions,
}) async {
  final ProcessResult gitResult = await runProcess(
    'git',
    ['status', '--porcelain', '-z'],
    runInShell: false,
    workingDirectory: packageRoot,
  );

  if (gitResult.exitCode != 0) {
    throw Exception('git status failed with exit code ${gitResult.exitCode}');
  }

  final List<String> modifiedFiles = [];
  final List<String> entries = (gitResult.stdout as String).split('\x00');
  for (var i = 0; i < entries.length; i++) {
    final String entry = entries[i];

    // git status --porcelain output format starts with "XY path".
    // where XY is the 2-character status.
    if (entry.length < 4) {
      continue;
    }

    final String status = entry.substring(0, 2);
    String filePath = entry.substring(3);

    // For renames (R) and copies (C) with -z, the next NUL-terminated
    // string contains the new path. We skip the original path.
    if (status.startsWith('R') || status.startsWith('C')) {
      if (i + 1 < entries.length) {
        filePath = entries[++i];
      }
    }

    // Filter by language if requested.
    if (allowedExtensions != null) {
      if (!allowedExtensions.any((ext) => filePath.endsWith(ext))) {
        continue;
      }
    }

    // Skip generated files for Dart.
    if (filePath.endsWith('.dart') && isGeneratedFile(filePath)) {
      continue;
    }

    final String fullPath = path.join(repoRoot, filePath);
    if (fileExists(fullPath)) {
      modifiedFiles.add(fullPath);
    }
  }
  return modifiedFiles;
}
