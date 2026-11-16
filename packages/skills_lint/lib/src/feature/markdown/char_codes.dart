// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The ASCII characters that the Markdown scanners compare code units with.
library;

const int tab = 0x09;
const int newline = 0x0A;
const int carriageReturn = 0x0D;
const int space = 0x20;
const int exclamation = 0x21;
const int doubleQuote = 0x22;
const int hash = 0x23;
const int singleQuote = 0x27;
const int openParen = 0x28;
const int closeParen = 0x29;
const int asterisk = 0x2A;
const int plus = 0x2B;
const int hyphen = 0x2D;
const int period = 0x2E;
const int digitZero = 0x30;
const int digitNine = 0x39;
const int colon = 0x3A;
const int lessThan = 0x3C;
const int equals = 0x3D;
const int greaterThan = 0x3E;
const int openBracket = 0x5B;
const int backslash = 0x5C;
const int closeBracket = 0x5D;
const int underscore = 0x5F;
const int backtick = 0x60;
const int tilde = 0x7E;
const int delete = 0x7F;

/// Whether [char] is a space or a tab.
bool isSpaceOrTab(int char) => char == space || char == tab;

/// Whether [char] is a space, tab, line feed or carriage return.
bool isAsciiWhitespace(int char) => isSpaceOrTab(char) || char == newline || char == carriageReturn;

/// Whether [char] is an ASCII digit.
bool isDigit(int char) => char >= digitZero && char <= digitNine;

/// Whether [char] is ASCII punctuation: `!` to `/`, `:` to `@`, `[` to `` ` ``
/// or `{` to `~`.
bool isAsciiPunctuation(int char) =>
    (char >= exclamation && char <= 0x2F) ||
    (char >= colon && char <= 0x40) ||
    (char >= openBracket && char <= backtick) ||
    (char >= 0x7B && char <= tilde);
