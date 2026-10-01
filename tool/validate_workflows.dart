// Validates that the workflow files parse as YAML and that the keys GitHub
// Actions depends on are present. Run from the repo root:
//
//   dart run tool/validate_workflows.dart
//
// Not shipped in the app - this is a repo-hygiene script.
import 'dart:io';

import 'package:yaml/yaml.dart';

Future<void> main() async {
  var failures = 0;

  final dir = Directory('.github/workflows');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.yml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final name = file.path.split(Platform.pathSeparator).last;

    late final Object? parsed;
    try {
      parsed = loadYaml(file.readAsStringSync());
    } catch (error) {
      stdout.writeln('FAIL  $name: not valid YAML -> $error');
      failures++;
      continue;
    }

    if (parsed is! YamlMap) {
      stdout.writeln('FAIL  $name: top level is not a mapping');
      failures++;
      continue;
    }

    // `on:` is parsed as the boolean true by YAML 1.1, which is how Actions
    // itself sees it, so both spellings have to be accepted.
    final triggers = parsed['on'] ?? parsed[true];
    if (triggers == null) {
      stdout.writeln('FAIL  $name: no trigger block');
      failures++;
      continue;
    }

    final jobs = parsed['jobs'];
    if (jobs is! YamlMap || jobs.isEmpty) {
      stdout.writeln('FAIL  $name: no jobs');
      failures++;
      continue;
    }

    // Every job needs a runs-on, and every step needs a name or an id so a
    // failing run is readable.
    for (final entry in jobs.entries) {
      final job = entry.value;
      if (job is! YamlMap || job['runs-on'] == null) {
        stdout.writeln('FAIL  $name: job "${entry.key}" has no runs-on');
        failures++;
        continue;
      }
      final steps = job['steps'];
      if (steps is! YamlList || steps.isEmpty) {
        stdout.writeln('FAIL  $name: job "${entry.key}" has no steps');
        failures++;
        continue;
      }
      for (final step in steps) {
        if (step is! YamlMap) {
          stdout.writeln('FAIL  $name: job "${entry.key}" has a malformed step');
          failures++;
          continue;
        }
        if (step['uses'] == null && step['run'] == null) {
          stdout.writeln(
            'FAIL  $name: job "${entry.key}" has a step with neither uses nor run',
          );
          failures++;
        }
      }
    }

    stdout.writeln(
      'ok    $name  triggers=${_describe(triggers)} jobs=${jobs.length}',
    );
  }

  stdout.writeln(
    failures == 0
        ? 'RESULT: all workflows parse and are structurally sound'
        : 'RESULT: $failures problem(s)',
  );
  exitCode = failures == 0 ? 0 : 1;
}

String _describe(Object? triggers) {
  if (triggers is YamlMap) return triggers.keys.join(',');
  if (triggers is YamlList) return triggers.join(',');
  return triggers.toString();
}
