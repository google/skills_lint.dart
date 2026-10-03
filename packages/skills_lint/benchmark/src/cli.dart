// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Argument parsing and report writing shared by the benchmark scripts.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

/// Option that names a file to write the JSON report to.
const String jsonOption = 'json';

/// Option that names a file to write the Markdown report to.
const String markdownOption = 'markdown';

const String _helpFlag = 'help';

/// Exit code for a command line that doesn't parse.
const int usageExitCode = 64;

/// Adds the [jsonOption], [markdownOption] and `--help` options to [parser].
ArgParser addOutputOptions(ArgParser parser) => parser
  ..addOption(jsonOption, valueHelp: 'path', help: 'Also write a JSON report to this file.')
  ..addOption(
    markdownOption,
    valueHelp: 'path',
    help: 'Also write the Markdown report to this file.',
  )
  ..addFlag(_helpFlag, abbr: 'h', negatable: false, help: 'Show usage information.');

/// Parses [arguments] with [parser].
///
/// Returns `null`, after printing usage, when the arguments don't parse or
/// ask for help. A parse failure also sets [exitCode] to [usageExitCode].
ArgResults? parseArguments(ArgParser parser, List<String> arguments, {required String script}) {
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln(parser.usage);
    exitCode = usageExitCode;
    return null;
  }
  if (args.flag(_helpFlag)) {
    stdout
      ..writeln('Usage: dart run $script [options]')
      ..writeln(parser.usage);
    return null;
  }
  return args;
}

/// Prints [markdown], and writes it and [json] to the files that [args]
/// names.
void writeOutputs(ArgResults args, {required String markdown, required Object? json}) {
  stdout.write(markdown);
  final String? markdownPath = args.option(markdownOption);
  if (markdownPath != null) {
    File(markdownPath).writeAsStringSync(markdown);
  }
  final String? jsonPath = args.option(jsonOption);
  if (jsonPath != null) {
    File(jsonPath).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
  }
}
