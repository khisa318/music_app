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

    failures += _checkTagFilters(name, triggers);
    failures += _checkSecretWiring(name, jobs);

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

/// Checks that a workflow triggered by tag names the tags it will actually be
/// given.
///
/// This is here because of a bug that cost a release. The Release workflow
/// filtered on `v[0-9]+.[0-9]+.[0-9]+`, written as though the filter were a
/// regular expression. GitHub's filters are globs, and in a glob `+` is a
/// literal plus, so the pattern describes a tag spelled `v1+0+0`. The workflow
/// parsed, validated, and sat at zero runs while the tagging workflow pushed
/// `v1.0.0` correctly and reported success. Nothing about the file was wrong in
/// any way a structural check could see.
///
/// So the filters are compiled as globs and matched against real tag names.
/// Only patterns that mention `tags` are checked.
int _checkTagFilters(String name, Object? triggers) {
  if (triggers is! YamlMap) return 0;

  final push = triggers['push'];
  if (push is! YamlMap) return 0;

  final tags = push['tags'];
  if (tags == null) return 0;

  final patterns = tags is YamlList ? tags : [tags];
  if (patterns.isEmpty) return 0;

  // What the tagging workflow is capable of producing, including a pre-release
  // suffix, since that is a documented, supported spelling.
  const realTags = ['v1.0.0', 'v1.2.3', 'v0.1.0', 'v1.2.3-rc1', 'v1.0.0-beta.2'];

  var failures = 0;
  for (final tag in realTags) {
    final matched = patterns.any(
      (pattern) => _globMatches(pattern.toString(), tag),
    );
    if (!matched) {
      stdout.writeln(
        'FAIL  $name: no tag filter matches "$tag", so this workflow would '
        'never run for it. Filters: ${patterns.join(', ')}',
      );
      failures++;
    }
  }

  if (failures == 0) {
    stdout.writeln(
      'ok    $name  tag filters match '
      '${realTags.take(2).join(', ')} and pre-releases',
    );
  }

  return failures;
}

/// Checks that a step reading a repository secret as a shell variable actually
/// asks for that secret.
///
/// A GitHub secret is not an environment variable. A step that reads
/// `$SOME_SECRET` gets an empty string unless the step's `env:` maps it from
/// `secrets.`, so the script runs, the variable is unset, and under `set -u`
/// the step dies - or worse, with `${!name:-}` it reads as "not configured" and
/// reports every secret as missing when all four are present.
///
/// That is not hypothetical. release.yml checked for the four MUSIX_* signing
/// secrets this way, mapped none of them, and failed a real release with
/// "Missing GitHub Secret(s)" printed for secrets that were configured. The
/// build step had the same gap, which is worse: without them the APK is signed
/// with the Android debug key and still builds.
int _checkSecretWiring(String name, YamlMap jobs) {
  // The same shape the workflows use: MUSIX_FOO in a script, $MUSIX_FOO read.
  final pattern = RegExp(r'\$(?:\{)?(MUSIX_[A-Z0-9_]+)');

  var failures = 0;

  for (final jobEntry in jobs.entries) {
    final steps = jobEntry.value['steps'];
    if (steps is! YamlList) continue;

    for (final step in steps) {
      if (step is! YamlMap) continue;

      final script = step['run'];
      if (script is! String) continue;

      final used = pattern
          .allMatches(script)
          .map((m) => m.group(1)!)
          .toSet()
          .toList()
        ..sort();
      if (used.isEmpty) continue;

      final env = step['env'];
      final provided = <String>{};
      if (env is YamlMap) {
        for (final entry in env.entries) {
          final value = entry.value?.toString() ?? '';
          if (value.contains('secrets.')) provided.add(entry.key.toString());
        }
      }

      for (final secret in used) {
        if (!provided.contains(secret)) {
          stdout.writeln(
            'FAIL  $name: step "${step['name'] ?? jobEntry.key}" reads \$$secret '
            'but does not map it from secrets. in env:, so it will be empty.',
          );
          failures++;
        }
      }
    }
  }

  return failures;
}

/// Matches [tag] against a GitHub filter pattern.
///
/// A small glob rather than RegExp, deliberately: the point is to reproduce the
/// dialect the filter is actually interpreted in, and in that dialect `+`, `?`
/// and `*` are ordinary characters with only `*` and `?` doing anything. The
/// mistake being guarded against is reaching for a regex, where `+` is a
/// quantifier and the pattern would look correct while matching nothing.
///
/// Character classes are passed through as written rather than escaped, so the
/// contents are trusted to be regex-safe. Every filter in this repository uses
/// only digit ranges, which is all this needs to be correct for.
bool _globMatches(String pattern, String tag) {
  final buffer = StringBuffer('^');

  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];

    if (char == '*') {
      buffer.write('.*');
    } else if (char == '?') {
      buffer.write('.');
    } else if (char == '[') {
      final close = pattern.indexOf(']', i + 1);
      if (close == -1) {
        buffer.write(RegExp.escape(char));
        continue;
      }
      var body = pattern.substring(i + 1, close);
      if (body.startsWith('!') || body.startsWith('^')) {
        body = '^${body.substring(1)}';
      }
      buffer.write('[$body]');
      i = close;
    } else {
      buffer.write(RegExp.escape(char));
    }
  }

  buffer.write(r'$');
  return RegExp(buffer.toString()).hasMatch(tag);
}
