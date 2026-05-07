// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'hook_utils.dart';

/// Implements the dart format hook logic.
class DartFormatHook {
  /// Creates a [DartFormatHook].
  DartFormatHook({
    this.runProcess = Process.run,
    this.fileExists = _defaultFileExists,
    this.printStdout = _defaultPrintStdout,
    required this.logToFile,
    this.onExit = exit,
  });

  /// The function used to run processes.
  final Future<ProcessResult> Function(
    String,
    List<String>, {
    bool runInShell,
    String? workingDirectory,
  })
  runProcess;

  /// The function used to check if a file exists.
  final bool Function(String) fileExists;

  /// The function used to print to stdout.
  final void Function(String) printStdout;

  /// The function used to log to a file.
  final Future<void> Function(String) logToFile;

  /// The function used to exit the process.
  final void Function(int) onExit;

  static bool _defaultFileExists(String path) => File(path).existsSync();
  static void _defaultPrintStdout(String message) => stdout.writeln(message);

  /// Runs the format hook.
  Future<void> run(List<String> args, String currentPath) async {
    void emitEmptyResult() {
      printStdout(jsonEncode({}));
    }

    final int sourceIdx = args.indexOf('--source');
    final String triggerSource = (sourceIdx != -1 && sourceIdx + 1 < args.length)
        ? args[sourceIdx + 1].toUpperCase()
        : 'MANUAL';

    await logToFile('dart_format.dart started in $currentPath (Trigger: $triggerSource)');

    try {
      // Get the repo root to resolve paths in monorepo.
      final ProcessResult repoRootResult = await runProcess('git', [
        'rev-parse',
        '--show-toplevel',
      ], runInShell: false);

      if (repoRootResult.exitCode != 0) {
        await logToFile('ERROR: Failed to get git repo root.');
        emitEmptyResult();
        onExit(1);
        return;
      }
      final String repoRoot = (repoRootResult.stdout as String).trim();

      // 1. Check if there are modified .dart files.
      final List<String> modifiedDartFiles;
      try {
        // ignore: invalid_use_of_visible_for_testing_member
        modifiedDartFiles = await getModifiedFilesInternal(
          runProcess: runProcess,
          packageRoot: currentPath,
          repoRoot: repoRoot,
          fileExists: fileExists,
          allowedExtensions: ['.dart'],
        );
      } catch (e) {
        await logToFile('ERROR: Failed to get modified files: $e');
        emitEmptyResult();
        onExit(1);
        return;
      }

      if (modifiedDartFiles.isEmpty) {
        await logToFile('No modified dart files, exiting.');
        emitEmptyResult();
        onExit(0);
        return;
      }

      await logToFile('Running dart format on ${modifiedDartFiles.length} files...');

      // 2. Run dart format ONLY on the modified files.
      final ProcessResult result = await runProcess('dart', [
        'format',
        '--output=write',
        ...modifiedDartFiles,
      ], runInShell: false);

      await logToFile('dart format finished with exit code ${result.exitCode}');
      await logToFile('STDOUT:\n${result.stdout}');
      await logToFile('STDERR:\n${result.stderr}');

      if (result.exitCode != 0) {
        emitEmptyResult();
        onExit(result.exitCode);
        return;
      }

      emitEmptyResult();
      onExit(0);
      return;
    } catch (e, stackTrace) {
      await logToFile('UNHANDLED EXCEPTION: $e');
      await logToFile(stackTrace.toString());
      emitEmptyResult();
      onExit(1);
      return;
    }
  }
}
