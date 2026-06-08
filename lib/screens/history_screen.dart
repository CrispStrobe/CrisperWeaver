import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/history_service.dart';
import '../services/semantic_search_service.dart';
import '../utils/file_utils.dart';
import '../utils/responsive.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late Future<List<HistoryEntry>> _future;
  // §5.1.4 history search — naive client-side substring filter.
  // Matches against the entry's title (source filename or URL) +
  // every segment's text concatenated as fullText. Case-insensitive.
  // Empty query = no filter. The TextField is mounted in the
  // AppBar bottom so the keyboard doesn't push the list around.
  String _searchQuery = '';
  late final TextEditingController _searchController;
  /// §5.25.2 — When true, use TF-IDF semantic search instead of
  /// substring matching. Toggle via the search bar suffix icon.
  bool _semanticSearch = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    final service = ref.read(historyServiceProvider);
    _future = service.list();
  }

  /// Return only the entries whose title or fullText matches the
  /// current search query. Uses either substring or TF-IDF semantic
  /// search depending on the [_semanticSearch] toggle.
  List<HistoryEntry> _applyFilter(List<HistoryEntry> all) {
    if (_searchQuery.isEmpty) return all;
    if (!_semanticSearch) {
      final q = _searchQuery.toLowerCase();
      return all
          .where((e) =>
              e.title.toLowerCase().contains(q) ||
              e.fullText.toLowerCase().contains(q))
          .toList(growable: false);
    }
    // §5.25.2 — Semantic search: score each entry's segments against
    // the query, keep entries with at least one matching segment.
    final scored = <(HistoryEntry, double)>[];
    for (final entry in all) {
      final results = SemanticSearchService.search(
        query: _searchQuery,
        segments: entry.segments,
        maxResults: 1,
      );
      if (results.isNotEmpty) {
        scored.add((entry, results.first.score));
      }
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.map((e) => e.$1).toList();
  }

  Future<void> _deleteAll() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.historyClearAll),
        content: Text(l.historyClearAllPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.historyClearAll),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(historyServiceProvider).clear();
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.historyTitle),
        actions: [
          IconButton(
            tooltip: l.historyRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_reload),
          ),
          IconButton(
            tooltip: l.historyClearAll,
            icon: const Icon(Icons.delete_sweep),
            onPressed: _deleteAll,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                hintText: l.historySearchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // §5.25.2 — Toggle semantic (TF-IDF) vs substring search.
                    IconButton(
                      icon: Icon(
                        _semanticSearch ? Icons.psychology : Icons.abc,
                        size: 18,
                        color: _semanticSearch
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      tooltip: _semanticSearch
                          ? l.historySearchSemanticTooltip
                          : l.historySearchSubstringTooltip,
                      onPressed: () =>
                          setState(() => _semanticSearch = !_semanticSearch),
                    ),
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                  ],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.12),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 0),
              ),
              onChanged: (v) =>
                  setState(() => _searchQuery = v.trim()),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<HistoryEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
                child: Text(AppLocalizations.of(context)
                    .historyFailedToLoad('${snap.error}')));
          }
          final all = snap.data ?? const <HistoryEntry>[];
          if (all.isEmpty) {
            return const _EmptyHistory();
          }
          final items = _applyFilter(all);
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l.historySearchNoResults(_searchQuery),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            );
          }
          return Column(
            children: [
              // Per-search filter count strip. Hidden when not
              // filtering so the list stays clean for normal use.
              if (_searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l.historySearchMatchCount(items.length, all.length),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, i) => _HistoryTile(
                    entry: items[i],
                    searchQuery: _searchQuery,
                    allEntries: all,
                    onDelete: () async {
                      await ref
                          .read(historyServiceProvider)
                          .delete(items[i].id);
                      setState(_reload);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: isPhoneWidth(context)
          ? const PhoneNavBar(current: PhoneNavDestination.history)
          : null,
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            l.historyEmpty,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            l.historyEmptyHint,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.onDelete,
    this.searchQuery = '',
    this.allEntries = const [],
  });

  final HistoryEntry entry;
  final VoidCallback onDelete;
  /// All history entries — needed for "Compare with..." picker (§5.25.7).
  final List<HistoryEntry> allEntries;
  /// Active history search query. When non-empty, the expanded
  /// transcript shows a yellow highlight on matching substrings
  /// + auto-expands so the user can see the hit without an extra
  /// tap. See §5.1.4.
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd().add_Hm();
    return Card(
      child: ExpansionTile(
        // Auto-expand when an active search matches this entry's
        // body so users see the hit without clicking through.
        initiallyExpanded: searchQuery.isNotEmpty &&
            entry.fullText
                .toLowerCase()
                .contains(searchQuery.toLowerCase()),
        title: _highlightedTitle(context, entry.title, searchQuery),
        subtitle: Text(
          '${fmt.format(entry.createdAt)} · ${entry.engineId}'
          '${entry.modelId != null ? ' · ${entry.modelId}' : ''}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _highlightedBody(context, entry.fullText, searchQuery),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: Text(AppLocalizations.of(context).historyCopy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: entry.fullText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text(AppLocalizations.of(context).copied)),
                        );
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.save_alt, size: 16),
                      label:
                          Text(AppLocalizations.of(context).historyExportSrt),
                      onPressed: () => _exportAs(context, TranscriptFormat.srt),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.save_alt, size: 16),
                      label:
                          Text(AppLocalizations.of(context).historyExportTxt),
                      onPressed: () => _exportAs(context, TranscriptFormat.txt),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.save_alt, size: 16),
                      label:
                          Text(AppLocalizations.of(context).historyExportJson),
                      onPressed: () =>
                          _exportAs(context, TranscriptFormat.json),
                    ),
                    // §5.25.7 — Compare with another history entry.
                    OutlinedButton.icon(
                      icon: const Icon(Icons.compare_arrows, size: 16),
                      label: Text(AppLocalizations.of(context).historyCompareButton),
                      onPressed: () => _showComparePicker(context),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      style:
                          OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      label: Text(AppLocalizations.of(context).historyDelete),
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// §5.25.7 — Show a picker dialog listing all other history entries.
  /// On selection, navigate to the transcript comparison screen.
  void _showComparePicker(BuildContext context) {
    final others = allEntries.where((e) => e.id != entry.id).toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).historyCompareNoOtherEntries)),
      );
      return;
    }
    final fmt = DateFormat.yMMMd().add_Hm();
    showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppLocalizations.of(context).historyComparePickerTitle),
        children: [
          for (final other in others)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(other.id),
              child: Text(
                '${other.title}\n${fmt.format(other.createdAt)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    ).then((rightId) {
      if (rightId != null && context.mounted) {
        context.push('/compare?left=${entry.id}&right=$rightId');
      }
    });
  }

  /// §5.1.4 — render `text` with `query` highlighted in yellow.
  /// Returns the body text widget; uses SelectableText.rich so the
  /// user can still copy-paste from the highlighted body. When
  /// the query is empty, falls back to a plain SelectableText.
  Widget _highlightedBody(
      BuildContext context, String text, String query) {
    if (query.isEmpty) return SelectableText(text);
    final spans = _highlightSpans(text, query);
    return SelectableText.rich(TextSpan(children: spans));
  }

  /// Title-row variant — same highlight machinery but as Text.rich
  /// (titles aren't user-selectable to keep tap-to-expand working).
  Widget _highlightedTitle(
      BuildContext context, String text, String query) {
    if (query.isEmpty) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final spans = _highlightSpans(text, query);
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Build a list of TextSpans alternating plain + highlighted
  /// based on case-insensitive substring matches of [query] in
  /// [text]. Matches the user-visible color hint with
  /// `Colors.yellow.shade300` on the highlighted runs.
  List<TextSpan> _highlightSpans(String text, String query) {
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final out = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      final hit = lower.indexOf(q, i);
      if (hit < 0) {
        out.add(TextSpan(text: text.substring(i)));
        break;
      }
      if (hit > i) {
        out.add(TextSpan(text: text.substring(i, hit)));
      }
      out.add(TextSpan(
        text: text.substring(hit, hit + query.length),
        style: TextStyle(
          backgroundColor: Colors.yellow.shade300,
          color: Colors.black,
        ),
      ));
      i = hit + query.length;
    }
    return out;
  }

  Future<void> _exportAs(BuildContext context, TranscriptFormat fmt) async {
    try {
      final file = await FileUtils.saveTranscription(
        entry.fullText,
        entry.title,
        format: fmt,
        segments: entry.segments,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context).historySaved(file.path))),
      );
      await FileUtils.shareFile(file.path, subject: entry.title);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context).historyExportFailed('$e'))),
      );
    }
  }
}
