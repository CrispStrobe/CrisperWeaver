import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/log_service.dart';
import '../widgets/root_aware_back_leading.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  StreamSubscription<LogEntry>? _sub;
  List<LogEntry> _entries = const [];
  final TextEditingController _filter = TextEditingController();
  LogLevel _minDisplay = LogLevel.trace;
  bool _autoScroll = true;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _entries = Log.instance.snapshot();
    _sub = Log.instance.stream.listen((e) {
      if (!mounted) return;
      setState(() {
        _entries = [..._entries, e];
      });
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _filter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<LogEntry> get _visible {
    final q = _filter.text.trim().toLowerCase();
    return _entries.where((e) {
      if (e.level.rank < _minDisplay.rank) return false;
      if (q.isEmpty) return true;
      return e.message.toLowerCase().contains(q) ||
          e.tag.toLowerCase().contains(q) ||
          (e.error?.toString().toLowerCase().contains(q) ?? false);
    }).toList(growable: false);
  }

  Color _colorFor(LogLevel l) {
    switch (l) {
      case LogLevel.trace:
        return Colors.blueGrey;
      case LogLevel.debug:
        return Colors.blue;
      case LogLevel.info:
        return Colors.teal;
      case LogLevel.warn:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        // #35 — no back button when this was reached by a stack-replacing
        // `go()`; fall back to a home button.
        leading: rootAwareBackLeading(context),
        title: Text(l.logsTitle),
        actions: [
          PopupMenuButton<LogLevel>(
            tooltip: l.tooltipDisplayLevel,
            icon: const Icon(Icons.filter_list),
            initialValue: _minDisplay,
            onSelected: (v) => setState(() => _minDisplay = v),
            itemBuilder: (_) => LogLevel.values
                .map((lv) => PopupMenuItem(
                      value: lv,
                      child: Text(l.logsShowLevel(lv.tag)),
                    ))
                .toList(),
          ),
          IconButton(
            tooltip: _autoScroll
                ? l.tooltipPauseAutoScroll
                : l.tooltipResumeAutoScroll,
            icon: Icon(_autoScroll ? Icons.pause : Icons.play_arrow),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          PopupMenuButton<String>(
            onSelected: _action,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'copy', child: Text(l.logsCopyVisible)),
              PopupMenuItem(value: 'copy_all', child: Text(l.logsCopyAll)),
              PopupMenuItem(value: 'export', child: Text(l.logsExport)),
              PopupMenuItem(value: 'share', child: Text(l.logsShare)),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'clear', child: Text(l.clear)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _filter,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.logsFilterHint,
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemCount: items.length,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemBuilder: (context, i) {
                final e = items[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      children: [
                        TextSpan(
                          text: '${e.timestamp.toIso8601String()} ',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        TextSpan(
                          text: e.level.tag,
                          style: TextStyle(
                            color: _colorFor(e.level),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: ' [${e.tag}] ',
                          style: const TextStyle(color: Colors.purple),
                        ),
                        TextSpan(text: e.message),
                        if (e.error != null)
                          TextSpan(
                            text: '  :: ${e.error}',
                            style: const TextStyle(color: Colors.red),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _action(String a) async {
    // Resolved before the first await: every toast below sits after one,
    // and reading `context` across an async gap is an analyzer error.
    final l = AppLocalizations.of(context);
    switch (a) {
      case 'copy':
        await Clipboard.setData(ClipboardData(
          text: _visible.map((e) => e.format()).join('\n'),
        ));
        _toast(l.logsVisibleCopied);
        break;
      case 'copy_all':
        await Clipboard.setData(ClipboardData(text: Log.instance.dumpAll()));
        _toast(l.logsAllCopied);
        break;
      case 'export':
        final path = await Log.instance.exportToFile();
        _toast(l.logsExportedTo(path));
        break;
      case 'share':
        final path = await Log.instance.exportToFile();
        await SharePlus.instance.share(ShareParams(
          files: [XFile(path)],
          subject: 'CrisperWeaver logs',
        ));
        break;
      case 'clear':
        await Log.instance.clear();
        if (!mounted) return;
        setState(() => _entries = const []);
        break;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
