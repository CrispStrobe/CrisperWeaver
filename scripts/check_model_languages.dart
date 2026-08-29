// Cross-check ModelService's local language tags against what each
// HuggingFace repo actually advertises in its model card.
//
// Run: `dart run scripts/check_model_languages.dart`
//      (offline mode `--dry-run` skips the HF API hits and just lists
//      the local entries — useful for inspecting the catalogue.)
//
// Why: the `languages` field on ModelDefinition + `defaultLanguages`
// on BackendRepo were populated by hand from each model family's
// README. Real-world catalogue rot is high — repos publish new
// languages, model cards get updated, my tags don't. This script is
// the periodic checker that catches drift.
//
// Output: per repo —
//   * SHOULD ADD     : codes HF advertises that we don't include
//                      (we'd hide models the user might want)
//   * SHOULD DROP    : codes we include that HF doesn't advertise
//                      (we'd surface models that won't work well)
//   * MULTILINGUAL?  : flagged when HF lists ≥6 distinct languages
//                      but we only tag a narrow set — typical signal
//                      we should switch to ['*'].
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

const _hfApiBase = 'https://huggingface.co/api/models';
// HF model cards sometimes use 3-letter codes (eng, deu) or
// non-standard short names (chinese, mandarin). Normalise to the
// ISO 639-1 set the app's filter uses.
const _aliasMap = <String, String>{
  'eng': 'en', 'english': 'en',
  'deu': 'de', 'ger': 'de', 'german': 'de',
  'spa': 'es', 'sp': 'es', 'spanish': 'es',
  'fra': 'fr', 'fre': 'fr', 'french': 'fr',
  'ita': 'it', 'italian': 'it',
  'por': 'pt', 'portuguese': 'pt',
  'rus': 'ru', 'russian': 'ru',
  'jpn': 'ja', 'jp': 'ja', 'japanese': 'ja',
  'kor': 'ko', 'kr': 'ko', 'korean': 'ko',
  'cmn': 'zh', 'zho': 'zh', 'chi': 'zh',
  'chinese': 'zh', 'mandarin': 'zh', 'yue': 'zh',
  'ara': 'ar', 'arabic': 'ar',
  'nld': 'nl', 'dut': 'nl', 'dutch': 'nl',
  'pol': 'pl', 'polish': 'pl',
  'tur': 'tr', 'turkish': 'tr',
  'hin': 'hi', 'hindi': 'hi',
  'tha': 'th', 'thai': 'th',
  'vie': 'vi', 'vietnamese': 'vi',
  'ind': 'id', 'indonesian': 'id',
  'msa': 'ms', 'malay': 'ms',
  'tgl': 'tl', 'tagalog': 'tl',
  'fil': 'tl', 'filipino': 'tl',
  'ces': 'cs', 'cze': 'cs', 'czech': 'cs',
  'swe': 'sv', 'swedish': 'sv',
  'dan': 'da', 'danish': 'da',
  'nor': 'no', 'nob': 'no', 'norwegian': 'no',
  'fin': 'fi', 'finnish': 'fi',
  'ell': 'el', 'gre': 'el', 'greek': 'el',
  'heb': 'he', 'hebrew': 'he',
  'ukr': 'uk', 'ukrainian': 'uk',
  'ron': 'ro', 'rum': 'ro', 'romanian': 'ro',
  'swa': 'sw', 'swahili': 'sw',
};

String _normCode(String raw) {
  final lower = raw.toLowerCase().trim();
  // Check the alias map first — even 2-letter inputs can be non-ISO
  // (jp/kr/sp are HF cardData aliases for ja/ko/es). The previous
  // short-circuit `length == 2 → return lower` skipped these.
  final aliased = _aliasMap[lower];
  if (aliased != null) return aliased;
  if (lower.length == 2) return lower;
  return lower;
}

class _LocalRepo {
  final String key;
  final String repoId;
  final String backend;
  final Set<String> languages;
  _LocalRepo(this.key, this.repoId, this.backend, this.languages);
}

/// Parse `lib/services/model_catalog.dart` for the
/// `backendRepos` map and return one [_LocalRepo] per entry.
/// Regex-based — keeps the cross-check pure-Dart so it runs
/// without the Flutter SDK (and stays in sync with the catalogue
/// automatically, no second copy of the data to maintain).
List<_LocalRepo> _parseBackendRepos(String src) {
  final start = src.indexOf('static const Map<String, BackendRepo> backendRepos');
  if (start < 0) {
    throw StateError(
        'could not find `backendRepos` map declaration in model_catalog.dart');
  }
  // Find the opening brace of the map literal and walk balanced
  // braces to find the matching close — handles the nested
  // BackendRepo(...) constructors cleanly.
  final braceOpen = src.indexOf('{', start);
  if (braceOpen < 0) {
    throw StateError('no `{` after backendRepos declaration');
  }
  int depth = 0;
  int braceClose = -1;
  for (int i = braceOpen; i < src.length; i++) {
    final ch = src[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) {
        braceClose = i;
        break;
      }
    }
  }
  if (braceClose < 0) {
    throw StateError('unbalanced braces walking backendRepos map');
  }
  final body = src.substring(braceOpen + 1, braceClose);

  // Top-level keys (the BackendRepo entries) are quoted strings
  // followed by `: BackendRepo(...)`. Iterate by splitting on each
  // entry's opening pattern, then parse the body of each.
  final entryPattern =
      RegExp(r"'([a-z0-9._-]+)'\s*:\s*BackendRepo\(", multiLine: true);
  final matches = entryPattern.allMatches(body).toList();
  final out = <_LocalRepo>[];
  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    final key = m.group(1)!;
    // Walk balanced parens for this entry's body.
    int depth = 0;
    int j = m.end - 1; // points at '(' of BackendRepo(
    int entryEnd = -1;
    for (; j < body.length; j++) {
      final ch = body[j];
      if (ch == '(') depth++;
      if (ch == ')') {
        depth--;
        if (depth == 0) {
          entryEnd = j;
          break;
        }
      }
    }
    if (entryEnd < 0) continue;
    final entryBody = body.substring(m.end, entryEnd);

    final repoIdMatch =
        RegExp(r"repoId\s*:\s*'([^']+)'").firstMatch(entryBody);
    if (repoIdMatch == null) continue;
    final backendMatch =
        RegExp(r"backend\s*:\s*'([^']+)'").firstMatch(entryBody);
    // Two valid forms — handle each with its own regex so the
    // terminator doesn't have to be a one-size-fits-all alternation:
    //   1. `defaultLanguages: <String>['en', 'fr']` (inline list,
    //      may span multiple lines)
    //   2. `defaultLanguages: langsEU25` (named const, resolved to
    //      its list further down the file)
    final langs = <String>{};
    final inlineMatch = RegExp(
      r'defaultLanguages\s*:\s*(?:const\s+)?<String>\[([\s\S]*?)\]',
    ).firstMatch(entryBody);
    if (inlineMatch != null) {
      for (final il in RegExp(r"'([^']+)'").allMatches(inlineMatch.group(1)!)) {
        langs.add(il.group(1)!.toLowerCase());
      }
    } else {
      final namedMatch = RegExp(
        r'defaultLanguages\s*:\s*([a-zA-Z_][a-zA-Z0-9_]*)',
      ).firstMatch(entryBody);
      if (namedMatch != null) {
        langs.addAll(_resolveNamedLangsConst(src, namedMatch.group(1)!));
      }
    }
    out.add(_LocalRepo(
      key,
      repoIdMatch.group(1)!,
      backendMatch?.group(1) ?? '',
      langs,
    ));
  }
  return out;
}

/// Resolve a `langs<Name>` top-level const back to its list of
/// ISO 639-1 codes. Follows alias chains (`langsX = langsY`) up to
/// 5 hops so the same list can be referenced under multiple names
/// without forcing the resolver to peer through each one. Falls back
/// to the bare name string when nothing resolves so the diff stays
/// informative.
Set<String> _resolveNamedLangsConst(String src, String name) {
  var current = name;
  for (var hop = 0; hop < 5; hop++) {
    // Two shapes: `static const List<String> X = <String>[...]` or
    // `static const List<String> X = Y;` (alias).
    final listMatch = RegExp(
      'static const List<String>\\s+${RegExp.escape(current)}'
      r'\s*=\s*<String>\[([^\]]+)\]',
    ).firstMatch(src);
    if (listMatch != null) {
      return RegExp(r"'([^']+)'")
          .allMatches(listMatch.group(1)!)
          .map((m) => m.group(1)!.toLowerCase())
          .toSet();
    }
    final aliasMatch = RegExp(
      'static const List<String>\\s+${RegExp.escape(current)}'
      r'\s*=\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*;',
    ).firstMatch(src);
    if (aliasMatch == null) break;
    current = aliasMatch.group(1)!;
  }
  return {name};
}

Future<Set<String>> _fetchRepoLanguages(HttpClient http, String repoId) async {
  final uri = Uri.parse('$_hfApiBase/$repoId');
  HttpClientResponse resp;
  try {
    final req = await http.getUrl(uri);
    resp = await req.close();
  } catch (e) {
    stderr.writeln('  ! $repoId — request error: $e');
    return {};
  }
  if (resp.statusCode == 404) {
    stderr.writeln('  ! $repoId — 404 (repo missing or private)');
    return {};
  }
  if (resp.statusCode == 401 || resp.statusCode == 403) {
    stderr.writeln('  ! $repoId — ${resp.statusCode} (gated; needs HF token)');
    return {};
  }
  if (resp.statusCode != 200) {
    stderr.writeln('  ! $repoId — HTTP ${resp.statusCode}');
    return {};
  }
  final body = await resp.transform(utf8.decoder).join();
  final json = jsonDecode(body) as Map<String, Object?>;
  final out = <String>{};

  // 1. cardData.language can be a string or a list.
  final card = json['cardData'];
  if (card is Map) {
    final lang = card['language'];
    if (lang is String) out.add(_normCode(lang));
    if (lang is List) {
      for (final l in lang) {
        if (l is String) out.add(_normCode(l));
      }
    }
  }

  // 2. tags array often contains 'language:xx', 'multilingual', or
  // bare ISO codes.
  final tags = json['tags'];
  if (tags is List) {
    for (final t in tags) {
      if (t is! String) continue;
      if (t.startsWith('language:')) {
        out.add(_normCode(t.substring('language:'.length)));
      } else if (t.length == 2 && RegExp(r'^[a-z]{2}$').hasMatch(t)) {
        out.add(_normCode(t));
      } else if (t == 'multilingual' || t == 'multi') {
        out.add('*');
      }
    }
  }

  // 3. Fallback: when cardData.language is missing or empty but the
  // repo's README.md does carry a YAML language: block, fetch the
  // raw markdown and parse the frontmatter ourselves. Some repos
  // (e.g. ggerganov/whisper.cpp) don't populate cardData via the
  // API even though the README has the right metadata. Only run
  // when we have nothing concrete from the JSON — the API path is
  // cheaper.
  final hasConcrete = out.any((c) => c != '*');
  if (!hasConcrete) {
    final readmeLangs = await _fetchReadmeLanguages(http, repoId);
    out.addAll(readmeLangs);
  }

  return out;
}

/// Last-resort: GET https://huggingface.co/{repoId}/raw/main/README.md
/// and extract the `language:` list from the YAML frontmatter. Some
/// repos have the metadata in the README but the HF API doesn't
/// surface it via cardData (ggerganov/whisper.cpp is the canonical
/// example — empty cardData, 99 langs documented in the README body).
/// Returns the set of ISO codes found, empty when nothing matches.
Future<Set<String>> _fetchReadmeLanguages(
    HttpClient http, String repoId) async {
  final uri = Uri.parse('https://huggingface.co/$repoId/raw/main/README.md');
  try {
    final req = await http.getUrl(uri);
    final resp = await req.close();
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      return {};
    }
    final body = await resp.transform(utf8.decoder).join();
    // Frontmatter is the block between the first two `---` lines.
    final fm = RegExp(r'^---\s*\n([\s\S]*?)\n---', multiLine: true)
        .firstMatch(body);
    if (fm == null) return {};
    final yaml = fm.group(1)!;
    final out = <String>{};
    // Two YAML shapes:
    //   language: en       (scalar)
    //   language:          (list)
    //   - en
    //   - de
    final scalar = RegExp(r'^language:\s*([a-zA-Z0-9_-]+)\s*$', multiLine: true)
        .firstMatch(yaml);
    if (scalar != null) {
      out.add(_normCode(scalar.group(1)!));
    } else {
      final listMatch = RegExp(r'^language:\s*\n((?:\s*-\s*[\w-]+\s*\n?)+)',
              multiLine: true)
          .firstMatch(yaml);
      if (listMatch != null) {
        for (final m
            in RegExp(r'-\s*([a-zA-Z0-9_-]+)').allMatches(listMatch.group(1)!)) {
          out.add(_normCode(m.group(1)!));
        }
      }
    }
    return out;
  } catch (_) {
    return {};
  }
}

void main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  // The catalogue data moved out of model_service.dart into
  // model_catalog.dart; this script kept reading the old file and threw
  // `could not find backendRepos` on every run.
  final src = await File('lib/services/model_catalog.dart').readAsString();
  final repos = _parseBackendRepos(src);
  print('Parsed ${repos.length} BackendRepo entries from model_catalog.dart\n');
  if (dryRun) {
    for (final r in repos) {
      final pretty =
          r.languages.isEmpty ? '(none)' : r.languages.toList().join(',');
      print('  ${r.key.padRight(34)}  ${r.repoId.padRight(50)}  $pretty');
    }
    return;
  }

  final http = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  final problems = <String>[];
  for (final r in repos) {
    final hf = await _fetchRepoLanguages(http, r.repoId);
    final localPretty =
        r.languages.isEmpty ? '(none)' : r.languages.toList().join(',');
    final hfPretty =
        hf.isEmpty ? '(none)' : (hf.toList()..sort()).join(',');

    // The `multilingual` HF tag is informational — it says "this model
    // is not language-specific" but doesn't itself enumerate which
    // languages. A concrete list of N specific codes is strictly more
    // useful for filtering, so we treat the `*` from `multilingual`
    // as noise when HF also returns specific codes alongside it. Only
    // when HF has NO concrete codes and only `multilingual` does it
    // become the signal.
    final hfHadMultilingual = hf.contains('*');
    final hfConcrete = hf.where((c) => c != '*').toSet();

    String? note;
    if (r.languages.isEmpty && hf.isEmpty) {
      // both unknown — silent
    } else if (r.languages.contains('*')) {
      // We tagged `*`. If HF returns a concrete list, we could
      // be more useful by switching to it. Flag for follow-up.
      if (hfConcrete.length >= 3) {
        note = 'we use [\'*\']; HF lists '
            '${hfConcrete.length} concrete langs '
            '(${(hfConcrete.toList()..sort()).join(',')}) — '
            "narrowing the tag would help the user's filter";
        problems.add('${r.key}: $note');
      }
    } else if (hfConcrete.isEmpty && hfHadMultilingual && r.languages.isEmpty) {
      // HF only says "multilingual", no codes. Nothing actionable
      // beyond noting it.
      note = 'HF tags include "multilingual" but no concrete codes; '
          'local tag is empty';
      problems.add('${r.key}: $note');
    } else if (hfConcrete.isNotEmpty && r.languages.isNotEmpty) {
      final missing = hfConcrete.difference(r.languages);
      final extra = r.languages.difference(hfConcrete);
      if (missing.isNotEmpty || extra.isNotEmpty) {
        final parts = <String>[];
        if (missing.isNotEmpty) {
          parts.add('SHOULD ADD: ${(missing.toList()..sort()).join(',')}');
        }
        if (extra.isNotEmpty) {
          parts.add('SHOULD DROP: ${(extra.toList()..sort()).join(',')}');
        }
        note = parts.join(' / ');
        problems.add('${r.key}: $note');
      }
    } else if (hfConcrete.isNotEmpty && r.languages.isEmpty) {
      note = 'untagged locally; HF says '
          '${(hfConcrete.toList()..sort()).join(',')}';
      problems.add('${r.key}: $note');
    }

    final tag = note == null ? 'OK  ' : 'DIFF';
    print('[$tag] ${r.key}'
        '\n       repo:  ${r.repoId}'
        '\n       local: $localPretty'
        '\n       hf:    $hfPretty'
        '${note == null ? '' : '\n       note:  $note'}');
  }
  http.close(force: true);

  print('\n${problems.length} diff(s) flagged.');
  for (final p in problems) {
    print('  • $p');
  }
  if (problems.isNotEmpty) exit(1);
}
