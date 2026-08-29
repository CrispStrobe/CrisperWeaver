import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engines/transcription_engine.dart';
import '../l10n/generated/app_localizations.dart';
import '../main.dart' show historyServiceProvider;
import '../widgets/root_aware_back_leading.dart';

/// §5.25.7 — Transcript diff / comparison view.
///
/// Side-by-side comparison of two transcriptions of the same audio,
/// highlighting word-level differences. Helps users pick the best
/// model/settings for their domain.
class TranscriptCompareScreen extends ConsumerStatefulWidget {
  final String leftEntryId;
  final String rightEntryId;

  const TranscriptCompareScreen({
    super.key,
    required this.leftEntryId,
    required this.rightEntryId,
  });

  @override
  ConsumerState<TranscriptCompareScreen> createState() =>
      _TranscriptCompareScreenState();
}

class _TranscriptCompareScreenState
    extends ConsumerState<TranscriptCompareScreen> {
  List<TranscriptionSegment>? _leftSegments;
  List<TranscriptionSegment>? _rightSegments;
  String _leftTitle = '';
  String _rightTitle = '';

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final historyService = ref.read(historyServiceProvider);
    final left = await historyService.loadEntry(widget.leftEntryId);
    final right = await historyService.loadEntry(widget.rightEntryId);
    if (mounted) {
      setState(() {
        _leftSegments = left?.segments;
        _rightSegments = right?.segments;
        _leftTitle = left?.title ?? AppLocalizations.of(context).compareLeftFallback;
        _rightTitle = right?.title ?? AppLocalizations.of(context).compareRightFallback;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // #35 — no back button when this was reached by a stack-replacing
        // `go()`; fall back to a home button.
        leading: rootAwareBackLeading(context),
        title: Text(AppLocalizations.of(context).compareTranscriptsTitle),
      ),
      body: _leftSegments == null || _rightSegments == null
          ? const Center(child: CircularProgressIndicator())
          : _buildComparisonView(),
    );
  }

  Widget _buildComparisonView() {
    final aligned = _alignSegments(_leftSegments!, _rightSegments!);

    return Column(
      children: [
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _leftTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _rightTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // Stats row
        Padding(
          padding: const EdgeInsets.all(8),
          child: _buildStats(),
        ),
        const Divider(height: 1),
        // Aligned segments
        Expanded(
          child: ListView.builder(
            itemCount: aligned.length,
            itemBuilder: (context, index) {
              final pair = aligned[index];
              return _buildAlignedRow(pair);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStats() {
    final leftWords = _leftSegments!
        .expand((s) => s.text.split(RegExp(r'\s+')))
        .where((w) => w.isNotEmpty)
        .length;
    final rightWords = _rightSegments!
        .expand((s) => s.text.split(RegExp(r'\s+')))
        .where((w) => w.isNotEmpty)
        .length;

    // Compute simple word-error-rate-style similarity
    final leftText = _leftSegments!.map((s) => s.text).join(' ').toLowerCase();
    final rightText =
        _rightSegments!.map((s) => s.text).join(' ').toLowerCase();
    final similarity = _computeSimilarity(leftText, rightText);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _statChip(AppLocalizations.of(context).compareLeftWords, leftWords.toString()),
        _statChip(AppLocalizations.of(context).compareRightWords, rightWords.toString()),
        _statChip(AppLocalizations.of(context).compareSimilarity, '${(similarity * 100).toStringAsFixed(1)}%'),
      ],
    );
  }

  Widget _statChip(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildAlignedRow(_AlignedPair pair) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildDiffCell(pair.leftText, pair.rightText, true)),
          const SizedBox(width: 8),
          Expanded(child: _buildDiffCell(pair.rightText, pair.leftText, false)),
        ],
      ),
    );
  }

  Widget _buildDiffCell(String? text, String? otherText, bool isLeft) {
    if (text == null || text.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('—',
            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
      );
    }

    if (otherText == null || otherText.isEmpty) {
      // Only in this side
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (isLeft ? Colors.red : Colors.green).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text),
      );
    }

    // Both sides have text — highlight word-level differences
    final leftWords = text.split(RegExp(r'\s+'));
    final rightWords = otherText.split(RegExp(r'\s+'));
    final diff = _wordDiff(leftWords, rightWords);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: diff.map((wd) {
            Color? bg;
            if (wd.status == _DiffStatus.added) {
              bg = Colors.green.withValues(alpha: 0.2);
            } else if (wd.status == _DiffStatus.removed) {
              bg = Colors.red.withValues(alpha: 0.2);
            }
            return TextSpan(
              text: '${wd.word} ',
              style: TextStyle(backgroundColor: bg),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Align segments from two transcripts by timestamp overlap.
  List<_AlignedPair> _alignSegments(
    List<TranscriptionSegment> left,
    List<TranscriptionSegment> right,
  ) {
    final result = <_AlignedPair>[];
    var li = 0, ri = 0;

    while (li < left.length || ri < right.length) {
      if (li >= left.length) {
        result.add(_AlignedPair(null, right[ri].text));
        ri++;
      } else if (ri >= right.length) {
        result.add(_AlignedPair(left[li].text, null));
        li++;
      } else {
        final ls = left[li], rs = right[ri];
        // Check temporal overlap
        final overlap = math.min(ls.endTime, rs.endTime) -
            math.max(ls.startTime, rs.startTime);
        if (overlap > 0) {
          result.add(_AlignedPair(ls.text, rs.text));
          li++;
          ri++;
        } else if (ls.startTime < rs.startTime) {
          result.add(_AlignedPair(ls.text, null));
          li++;
        } else {
          result.add(_AlignedPair(null, rs.text));
          ri++;
        }
      }
    }
    return result;
  }

  /// Simple word-level diff using LCS.
  List<_DiffWord> _wordDiff(List<String> source, List<String> target) {
    // For display purposes, mark words in source that don't appear in
    // the LCS as "different"
    final lcs = _lcs(source, target);
    final result = <_DiffWord>[];
    var lcsIdx = 0;
    for (final word in source) {
      if (lcsIdx < lcs.length && word.toLowerCase() == lcs[lcsIdx].toLowerCase()) {
        result.add(_DiffWord(word, _DiffStatus.same));
        lcsIdx++;
      } else {
        result.add(_DiffWord(word, _DiffStatus.removed));
      }
    }
    return result;
  }

  /// Longest common subsequence of two word lists.
  List<String> _lcs(List<String> a, List<String> b) {
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (a[i - 1].toLowerCase() == b[j - 1].toLowerCase()) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = math.max(dp[i - 1][j], dp[i][j - 1]);
        }
      }
    }
    // Backtrack
    final result = <String>[];
    var i = m, j = n;
    while (i > 0 && j > 0) {
      if (a[i - 1].toLowerCase() == b[j - 1].toLowerCase()) {
        result.add(a[i - 1]);
        i--;
        j--;
      } else if (dp[i - 1][j] > dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }
    return result.reversed.toList();
  }

  /// Jaccard-style word similarity.
  double _computeSimilarity(String a, String b) {
    final wordsA = a.split(RegExp(r'\s+')).toSet();
    final wordsB = b.split(RegExp(r'\s+')).toSet();
    if (wordsA.isEmpty && wordsB.isEmpty) return 1.0;
    final intersection = wordsA.intersection(wordsB).length;
    final union = wordsA.union(wordsB).length;
    return union == 0 ? 1.0 : intersection / union;
  }
}

class _AlignedPair {
  final String? leftText;
  final String? rightText;
  _AlignedPair(this.leftText, this.rightText);
}

enum _DiffStatus { same, added, removed }

class _DiffWord {
  final String word;
  final _DiffStatus status;
  _DiffWord(this.word, this.status);
}
