// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import '../models/validation_result.dart';
import '../rule_catalog.dart';
import 'reporter.dart';

/// Machine-readable JSON array reporter.
class JsonReporter extends Reporter {
  JsonReporter({super.out, super.err, this.pretty = true});

  final bool pretty;

  @override
  void onSessionComplete(
    List<ValidationResult> results, {
    RuleCatalog catalog = const RuleCatalog(),
  }) {
    final List<Map<String, Object?>> jsonList = results.map((r) => r.toJson()).toList();
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    out.writeln(encoder.convert(jsonList));
  }
}
