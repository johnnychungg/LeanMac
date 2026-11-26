#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Checks App/Bundle/Localization against the tr("…") calls in the Swift sources.

  Errors   (exit 1): a translation key that no code uses, a placeholder mismatch, a malformed line.
  Warnings:          an English string that a language has not translated yet (error with --strict).

Usage: Scripts/check-l10n.py [--strict]
"""
import glob, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRICT = '--strict' in sys.argv

ESC = {'n': '\n', 't': '\t', '"': '"', '\\': '\\', "'": "'", '0': '\0', 'r': '\r'}


def parse_literal(s, i):
    """s[i] == '"'. Returns (key_format, placeholder_count, end_index)."""
    j = i + 1
    out, count = [], 0
    while j < len(s):
        c = s[j]
        if c == '\\':
            n = s[j + 1]
            if n == '(':
                depth, k = 1, j + 2
                while depth:
                    ch = s[k]
                    if ch == '"':
                        _, _, k = parse_literal(s, k)
                        continue
                    depth += (ch == '(') - (ch == ')')
                    k += 1
                out.append('%@')
                count += 1
                j = k
                continue
            if n == 'u':
                m = re.match(r'\\u\{([0-9a-fA-F]+)\}', s[j:])
                out.append(chr(int(m.group(1), 16)).replace('%', '%%'))
                j += m.end()
                continue
            out.append(ESC[n].replace('%', '%%'))
            j += 2
            continue
        if c == '"':
            return ''.join(out), count, j + 1
        out.append('%%' if c == '%' else c)
        j += 1
    raise ValueError('unterminated string literal')


def code_keys():
    keys = {}
    sources = glob.glob(os.path.join(ROOT, 'Sources/**/*.swift'), recursive=True) + \
        glob.glob(os.path.join(ROOT, 'App/**/*.swift'), recursive=True)
    for path in sources:
        text = open(path, encoding='utf-8').read()
        for m in re.finditer(r'(?<![A-Za-z0-9_.])tr\(\s*"', text):
            if text[max(0, m.start() - 5):m.start()].endswith('func '):
                continue
            try:
                key, count, _ = parse_literal(text, m.end() - 1)
            except Exception as exc:  # pragma: no cover
                print('ERROR cannot parse tr() in %s: %s' % (path, exc))
                sys.exit(1)
            keys[key] = count
    return keys


LINE = re.compile(r'^"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";\s*$')


def unescape(s):
    return re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), s)


def placeholders(value):
    """Returns the sorted list of argument indexes a value consumes (None = plain %@ in order)."""
    plain = 0
    positional = set()
    for m in re.finditer(r'%(?:(\d+)\$)?(%|@)', value):
        if m.group(2) == '%':
            continue
        if m.group(1):
            positional.add(int(m.group(1)))
        else:
            plain += 1
    return plain, positional


def main():
    errors, warnings = [], []
    keys = code_keys()
    files = sorted(glob.glob(os.path.join(ROOT, 'App/Bundle/Localization/*.lproj/Localizable.strings')))
    if not files:
        errors.append('no Localizable.strings found')
    for path in files:
        lang = os.path.basename(os.path.dirname(path))
        seen = {}
        for n, line in enumerate(open(path, encoding='utf-8'), 1):
            raw = line.rstrip('\n')
            if not raw.strip() or raw.lstrip().startswith(('/*', '*', '//')) or raw.strip().endswith('*/'):
                continue
            m = LINE.match(raw)
            if not m:
                errors.append('%s:%d malformed line: %s' % (lang, n, raw[:70]))
                continue
            key, value = unescape(m.group(1)), unescape(m.group(2))
            if key in seen:
                errors.append('%s:%d duplicate key: %s' % (lang, n, key[:70]))
            seen[key] = value
            if key not in keys:
                errors.append('%s:%d unused key (no tr() uses it): %s' % (lang, n, key[:70]))
                continue
            expected = keys[key]
            plain, positional = placeholders(value)
            if positional:
                if plain:
                    errors.append('%s:%d mixes %%@ and %%N$@: %s' % (lang, n, key[:70]))
                elif positional != set(range(1, expected + 1)):
                    errors.append('%s:%d placeholders %s but the code passes %d value(s): %s' % (lang, n, sorted(positional), expected, key[:70]))
            elif plain != expected:
                errors.append('%s:%d has %d placeholder(s) but the code passes %d: %s' % (lang, n, plain, expected, key[:70]))
        missing = sorted(k for k in keys if k not in seen)
        for k in missing:
            warnings.append('%s: not translated yet: %s' % (lang, k[:80]))
    for w in warnings[:40]:
        print('WARNING', w)
    if len(warnings) > 40:
        print('WARNING ... and %d more untranslated strings' % (len(warnings) - 40))
    for e in errors:
        print('ERROR', e)
    print('%d keys in code, %d language file(s), %d error(s), %d untranslated' % (len(keys), len(files), len(errors), len(warnings)))
    sys.exit(1 if errors or (STRICT and warnings) else 0)


main()
