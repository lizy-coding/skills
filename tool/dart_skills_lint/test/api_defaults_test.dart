// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:dart_skills_lint/dart_skills_lint.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('validateSkills applies default rules when not specified', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('api_test.');
    try {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();

      // Create a skill with invalid YAML metadata (missing frontmatter)
      // valid-yaml-metadata is error by default.
      await File('${skillDir.path}/SKILL.md').writeAsString('Invalid YAML No Frontmatter');

      // Call validateSkills with empty overrides.
      // It should apply default rules, including valid-yaml-metadata.
      final bool isValid = await validateSkills(individualSkillPaths: [skillDir.path]);

      expect(isValid, isFalse, reason: 'Should fail due to default rule valid-yaml-metadata.');
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('Validator skips disabled rules', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('api_test.');
    try {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();

      // Create a skill with invalid YAML metadata (missing frontmatter)
      await File('${skillDir.path}/SKILL.md').writeAsString('Invalid YAML No Frontmatter');

      // Create validator with the rule disabled.
      final validator = Validator(
        ruleOverrides: {'valid-yaml-metadata': AnalysisSeverity.disabled},
      );
      final ValidationResult result = await validator.validate(skillDir);

      final bool hasYamlError = result.validationErrors.any(
        (e) => e.ruleId == 'valid-yaml-metadata',
      );
      expect(
        hasYamlError,
        isFalse,
        reason: 'Should not have valid-yaml-metadata error when disabled.',
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('loadConfig resolves tilde in custom config path', () async {
    final String? home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    expect(home, isNotNull, reason: 'HOME or USERPROFILE environment variable must be set.');

    final tempFile = File(p.join(home!, 'dart_skills_lint_temp_test.yaml'));
    await tempFile.writeAsString('''
dart_skills_lint:
  rules:
    check-relative-paths: error
''');

    try {
      // Under the current code, this will fail because loadConfig does not do tilde expansion.
      final Configuration config = await ConfigParser.loadConfig(
        path: '~/dart_skills_lint_temp_test.yaml',
      );
      expect(config.configuredRules, contains('check-relative-paths'));
    } finally {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
    }
  });

  test('Path resolution avoids collision with prefix-sharing directories', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('api_test.');
    try {
      // We create two directories: 'skills-tests/test-skill' (the one being evaluated)
      // and 'skills' (the one defined in config)
      final configDir = Directory(p.join(tempDir.path, 'skills'));
      final Directory skillDir = await Directory(
        p.join(tempDir.path, 'skills-tests', 'test-skill'),
      ).create(recursive: true);

      // Create SKILL.md with trailing whitespace
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('''
---
name: test-skill
description: A test skill
---
Line with space 
'''); // Trailing space

      // Create a Configuration with rules enabled specifically for 'skills'
      final config = Configuration(
        directoryConfigs: [
          DirectoryConfig(
            path: configDir.path,
            rules: {'check-trailing-whitespace': AnalysisSeverity.error},
          ),
        ],
      );

      // Call validateSkills. Under unsafe prefix-matching, 'skills-tests'
      // starts with 'skills' (prefix collision) and enables trailing whitespace checks as error.
      // It should pass because 'skills-tests' is NOT the same directory as 'skills'.
      final bool isValid = await validateSkills(
        individualSkillPaths: [skillDir.path],
        config: config,
      );

      expect(
        isValid,
        isTrue,
        reason: 'Should pass because skills-tests does not match configuration for skills.',
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
