// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Blockquote markers (`>`) and list item markers (`-`, `+`, `*`, `1.` or
/// `1)`) at the start of a line, with the whitespace before them.
final RegExp _containerPrefixPattern = RegExp(
  r'(?:[ \t]*(?:>|(?:[-+*]|\d{1,9}[.)])(?=[ \t\r\n]|$)))+',
);
final RegExp _listMarkerPattern = RegExp(r'[-+*]|(\d{1,9})[.)]');
final RegExp _fencePattern = RegExp(r'[ \t]*(`{3,}|~{3,})(.*)');
final RegExp _atxHeadingPattern = RegExp(r'[ \t]*#{1,6}(?:[ \t]|$)');
final RegExp _notLineEnding = RegExp(r'[^\r\n]');

/// The Markdown text that can hold links, split into blocks.
typedef MarkdownBlocks = ({
  /// The scanned Markdown with fenced code blocks and line-start `>` and list
  /// markers replaced by spaces, so every offset matches the source.
  String text,

  /// The `[start, end)` offsets of each run of text lines: a paragraph, a
  /// list item or an ATX heading. Links and code spans do not cross blocks.
  List<(int, int)> blocks,

  /// The 0-based offset where each line starts.
  List<int> lineStarts,
});

/// Splits [markdown] into the blocks of text that can hold links.
///
/// Skips fenced code blocks at any indentation, including those inside
/// blockquotes and list items, and reads indented code blocks as text.
MarkdownBlocks scanMarkdownBlocks(String markdown) => _BlockScanner(markdown).scan();

// Telling an indented code block apart from indented list content needs
// CommonMark's full container rules. No `SKILL.md` in `third_party/skill-repos`
// puts link syntax in an indented code block, so the scanner reads them as
// text and tracks only fences, blockquote markers and list markers.
class _BlockScanner {
  _BlockScanner(this._markdown);

  final String _markdown;
  final _text = StringBuffer();
  final _blocks = <(int, int)>[];
  final _lineStarts = <int>[];
  int? _blockStart;
  bool _blockInList = false;

  // The open fence's marker run, and the container it sits in: a blockquote,
  // or a list item whose content starts at column _fenceIndent.
  String? _openFence;
  bool _fenceQuoted = false;
  int _fenceIndent = 0;

  MarkdownBlocks scan() {
    var lineStart = 0;
    while (lineStart < _markdown.length) {
      _lineStarts.add(lineStart);
      final int newline = _markdown.indexOf('\n', lineStart);
      final int lineEnd = newline == -1 ? _markdown.length : newline + 1;
      _scanLine(lineStart, lineEnd);
      lineStart = lineEnd;
    }
    _endBlock(_markdown.length);
    return (text: _text.toString(), blocks: _blocks, lineStarts: _lineStarts);
  }

  void _scanLine(int lineStart, int lineEnd) {
    final String line = _markdown.substring(lineStart, lineEnd);
    final String prefix = _containerPrefixPattern.matchAsPrefix(line)?[0] ?? '';
    final String content = line.substring(prefix.length);
    final Match? fence = _fencePattern.matchAsPrefix(content);
    final bool isBlank = content.trim().isEmpty;
    final Match? listMarker = _listMarkerPattern.firstMatch(prefix);
    // Whether the line would continue a paragraph that is not in a list.
    final bool continuesParagraph = _blockStart != null && !_blockInList;

    if (_openFence != null && _leavesFenceContainer(line, prefix, isBlank: isBlank)) {
      _openFence = null;
    }
    if (_openFence case final String openFence?) {
      if (fence != null && _closes(fence, openFence)) {
        _openFence = null;
      }
      _blankOut(line);
    } else if (fence != null && _opens(fence)) {
      _endBlock(lineStart);
      _openFence = fence[1];
      _fenceQuoted = prefix.contains('>');
      _fenceIndent = listMarker == null ? 0 : prefix.length;
      _blankOut(line);
    } else if (isBlank && !(listMarker != null && continuesParagraph)) {
      _endBlock(lineStart);
      _blankOut(line);
    } else {
      // CommonMark §5.2: outside a list, an empty item or an ordered item not
      // numbered 1 cannot interrupt a paragraph, so a hard-wrapped line such
      // as `2. Configuration` continues it.
      final bool startsItem =
          listMarker != null && !(continuesParagraph && (isBlank || !_canInterrupt(listMarker)));
      _textLine(lineStart, lineEnd, prefix, content, startsItem: startsItem);
    }
  }

  /// Whether [line] ends the blockquote or list item that holds the open
  /// fence, which ends the fence too.
  bool _leavesFenceContainer(String line, String prefix, {required bool isBlank}) => _fenceQuoted
      ? !prefix.contains('>')
      : !isBlank && line.length - line.trimLeft().length < _fenceIndent;

  void _textLine(
    int lineStart,
    int lineEnd,
    String prefix,
    String content, {
    required bool startsItem,
  }) {
    final isHeading = _atxHeadingPattern.matchAsPrefix(content) != null;
    if (isHeading || startsItem) {
      _endBlock(lineStart);
    }
    if (_blockStart == null) {
      _blockStart = lineStart;
      _blockInList = startsItem;
    }
    _text
      ..write(' ' * prefix.length)
      ..write(content);
    if (isHeading) {
      _endBlock(lineEnd);
    }
  }

  void _blankOut(String line) => _text.write(line.replaceAll(_notLineEnding, ' '));

  void _endBlock(int end) {
    if (_blockStart case final int start) {
      _blocks.add((start, end));
    }
    _blockStart = null;
  }
}

/// Whether [fence] opens a code block. A backtick fence's info string cannot
/// hold a backtick, because the line is then a code span.
bool _opens(Match fence) => !(fence[1]!.startsWith('`') && fence[2]!.contains('`'));

/// Whether [fence] closes the code block that [openFence] opened: it uses the
/// same character, is at least as long, and has nothing after it.
bool _closes(Match fence, String openFence) =>
    fence[1]![0] == openFence[0] &&
    fence[1]!.length >= openFence.length &&
    fence[2]!.trim().isEmpty;

/// Whether a list item that starts with [marker] can interrupt a paragraph:
/// it is a bullet, or it is ordered and numbered 1.
bool _canInterrupt(Match marker) => marker[1] == null || int.parse(marker[1]!) == 1;
