import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/generated/app_localizations.dart';
import '../main.dart' show modelServiceProvider;
import '../services/live_translate/live_translate_config.dart';
import '../services/live_translate/live_translate_controller.dart';
import '../services/log_service.dart';
import '../services/model_catalog.dart';
import '../utils/ai_text_disclosure.dart';
import '../services/settings_service.dart';
import '../services/text_translation_service.dart';
import '../utils/file_picker_util.dart';
import '../utils/platform_utils.dart' as plat;
import '../utils/window_fullscreen.dart';

/// §D — live captions + translation for talks, discussions and conferences.
///
/// Two faces: a setup page (routing table, models, audio, display) and a
/// caption board meant to be put fullscreen on a projector. On the board
/// every language has its own colour and a badge with its name, finished
/// sentences scroll up, and the sentence still being spoken sits dimmed at
/// the bottom with a draft translation.
class LiveTranslateScreen extends ConsumerStatefulWidget {
  const LiveTranslateScreen({super.key});

  @override
  ConsumerState<LiveTranslateScreen> createState() =>
      _LiveTranslateScreenState();
}

class _LiveTranslateScreenState extends ConsumerState<LiveTranslateScreen> {
  late final LiveTranslateController _ctl;
  final _focus = FocusNode(debugLabel: 'live-board');
  List<ModelInfo> _models = const [];
  bool _showBoard = false;
  bool _fullscreen = false;
  bool _chrome = true;
  Timer? _chromeTimer;

  @override
  void initState() {
    super.initState();
    _ctl = ref.read(liveTranslateProvider.notifier);
    _showBoard = ref.read(liveTranslateProvider).isActive;
    unawaited(_loadModels());
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _focus.dispose();
    if (_fullscreen) unawaited(WindowFullscreen.set(false));
    unawaited(_wake(false));
    unawaited(_ctl.stop());
    super.dispose();
  }

  Future<void> _wake(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (e) {
      Log.instance.d('live', 'wakelock unavailable: $e');
    }
  }

  Future<void> _loadModels() async {
    try {
      final m = await ref.read(modelServiceProvider).getWhisperCppModels();
      if (mounted) setState(() => _models = m);
    } catch (e) {
      Log.instance.w('live', 'model list failed', error: e);
    }
  }

  LiveTranslateConfig get _cfg => _ctl.config;
  void _set(LiveTranslateConfig c) {
    unawaited(_ctl.updateConfig(c));
    setState(() {});
  }

  Future<void> _start({String? replayFile}) async {
    setState(() => _showBoard = true);
    unawaited(_wake(true));
    _pokeChrome();
    _focus.requestFocus();
    await _ctl.start(replayFile: replayFile);
  }

  Future<void> _stop() async {
    await _ctl.stop();
    unawaited(_wake(false));
    if (mounted) setState(() => _chrome = true);
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    await WindowFullscreen.set(_fullscreen);
    if (mounted) setState(() {});
  }

  void _pokeChrome() {
    if (!_chrome) setState(() => _chrome = true);
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && ref.read(liveTranslateProvider).status == LiveStatus.running) {
        setState(() => _chrome = false);
      }
    });
  }

  void _font(double delta) => _set(_cfg.copyWith(fontSize: _cfg.fontSize + delta));

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) {
      unawaited(_toggleFullscreen());
    } else if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd) {
      _font(4);
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      _font(-4);
    } else if (k == LogicalKeyboardKey.keyL) {
      _set(_cfg.copyWith(
          layout: _cfg.layout == LiveLayout.stacked
              ? LiveLayout.columns
              : LiveLayout.stacked));
    } else if (k == LogicalKeyboardKey.keyS) {
      _set(_cfg.copyWith(showSource: !_cfg.showSource));
    } else if (k == LogicalKeyboardKey.escape) {
      if (_fullscreen) {
        unawaited(_toggleFullscreen());
      } else if (ref.read(liveTranslateProvider).isActive) {
        unawaited(_stop());
      } else {
        setState(() => _showBoard = false);
      }
    } else {
      return KeyEventResult.ignored;
    }
    _pokeChrome();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (plat.isWeb) {
      return Scaffold(
        appBar: AppBar(title: Text(l.liveTitle)),
        body: Center(child: Text(l.liveNotOnWeb)),
      );
    }
    final st = ref.watch(liveTranslateProvider);
    // Once live, the toolbar fades after a few idle seconds; arm that when
    // loading ends (the timer started on Start ran out during loading).
    ref.listen(liveTranslateProvider.select((s) => s.status), (prev, next) {
      if (next == LiveStatus.running && prev != LiveStatus.running) {
        _pokeChrome();
      }
    });
    ref.listen(liveTranslateProvider.select((s) => s.savedHistoryId),
        (prev, id) {
      if (id == null || id == prev || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        // With an action a SnackBar stays until dismissed by default; this
        // is a confirmation, not a question — let it go.
        persist: false,
        duration: const Duration(seconds: 6),
        content: Text(l.liveSavedToHistory),
        action: SnackBarAction(
          label: l.liveOpenInHistory,
          onPressed: () => context.push('/transcript/$id'),
        ),
      ));
    });
    if (_showBoard) return _board(context, l, st);
    return _setup(context, l, st);
  }

  // ===================================================================
  // Caption board
  // ===================================================================

  Widget _board(BuildContext context, AppLocalizations l, LiveTranslateState st) {
    final dark = _cfg.darkBackground;
    final bg = dark ? Colors.black : const Color(0xFFFAFAF7);
    final fg = dark ? Colors.white70 : Colors.black87;
    return Scaffold(
      backgroundColor: bg,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          onHover: (_) => _pokeChrome(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _focus.requestFocus();
              if (_chrome) {
                _chromeTimer?.cancel();
                setState(() => _chrome = false);
              } else {
                _pokeChrome();
              }
            },
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          _cfg.fontSize * 0.8,
                          _chrome ? 72 : _cfg.fontSize * 0.5,
                          _cfg.fontSize * 0.8,
                          _cfg.fontSize * 0.5),
                      child: _boardBody(l, st, dark),
                    ),
                  ),
                  // EU AI Act Art. 50(2) — on-screen disclosure, like the
                  // Translate screen's: small, but always there once a
                  // machine translation is on the board.
                  if (st.units.any((u) => u.translations.isNotEmpty) ||
                      st.drafts.isNotEmpty)
                    Positioned(
                      right: 12,
                      bottom: 6,
                      child: Text(
                        AiTextDisclosure.translation,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: dark ? Colors.white38 : Colors.black45,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: IgnorePointer(
                      ignoring: !_chrome,
                      child: AnimatedOpacity(
                        opacity: _chrome ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _toolbar(l, st, dark, fg),
                            // Non-fatal notices (e.g. "transcript only: no
                            // translator downloaded") ride with the chrome.
                            if (st.message != null && st.status != LiveStatus.error)
                              Container(
                                color: Colors.amber.withValues(alpha: 0.9),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                child: Text(st.message!,
                                    style: const TextStyle(color: Colors.black)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _boardBody(AppLocalizations l, LiveTranslateState st, bool dark) {
    if (st.status == LiveStatus.error) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: dark ? Colors.orangeAccent : Colors.deepOrange),
              const SizedBox(height: 16),
              Text(st.message ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20, color: dark ? Colors.white : Colors.black87)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => setState(() => _showBoard = false),
                icon: const Icon(Icons.tune),
                label: Text(l.liveSetup),
              ),
            ],
          ),
        ),
      );
    }
    final hasOpen = _cfg.showDrafts && (st.held.isNotEmpty || st.tail.isNotEmpty);
    if (st.units.isEmpty && !hasOpen) {
      final waiting = st.status == LiveStatus.loading ? l.liveLoading : l.liveWaiting;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (st.status == LiveStatus.loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: CircularProgressIndicator(),
              ),
            Text(waiting,
                style: TextStyle(
                    fontSize: _cfg.fontSize * 0.8,
                    fontStyle: FontStyle.italic,
                    color: dark ? Colors.white38 : Colors.black38)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                for (final lang in _visibleLangs())
                  _LangBadge(lang: lang, size: _cfg.fontSize * 0.5, dark: dark, long: true),
              ],
            ),
          ],
        ),
      );
    }
    return _cfg.layout == LiveLayout.columns
        ? _columns(st, dark, hasOpen)
        : _stacked(st, dark, hasOpen);
  }

  List<String> _visibleLangs() => [
        for (final x in _cfg.displayLanguages)
          if (!_cfg.hiddenLanguages.contains(x)) x
      ];

  bool _visible(String lang) => !_cfg.hiddenLanguages.contains(lang);

  TextStyle _style(String lang, bool dark,
          {double scale = 1, bool dim = false, bool source = false}) =>
      TextStyle(
        fontSize: _cfg.fontSize * scale,
        height: 1.28,
        fontWeight: source ? FontWeight.w600 : FontWeight.w500,
        fontStyle: dim ? FontStyle.italic : FontStyle.normal,
        color: LanguageColors.of(lang, dark: dark)
            .withValues(alpha: dim ? 0.55 : 1),
      );

  Widget _line(String lang, String text, bool dark,
      {bool dim = false, bool source = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: _cfg.fontSize * 0.12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: _cfg.fontSize * 0.22),
            child: _LangBadge(lang: lang, size: _cfg.fontSize * 0.42, dark: dark),
          ),
          SizedBox(width: _cfg.fontSize * 0.4),
          Expanded(
            child: Text(text, style: _style(lang, dark, dim: dim, source: source)),
          ),
        ],
      ),
    );
  }

  Widget _stacked(LiveTranslateState st, bool dark, bool hasOpen) {
    final units = st.units;
    final count = units.length + (hasOpen ? 1 : 0);
    return ListView.builder(
      reverse: true,
      itemCount: count,
      itemBuilder: (context, i) {
        if (hasOpen && i == 0) return _openStacked(st, dark);
        final u = units[units.length - 1 - (i - (hasOpen ? 1 : 0))];
        final lines = <Widget>[
          if (_cfg.showSource && _visible(u.lang))
            _line(u.lang, u.text, dark, source: true),
          for (final t in u.targets)
            if (_visible(t))
              _line(t, u.translations[t] ?? (u.isPending(t) ? '…' : '—'), dark,
                  dim: !u.translations.containsKey(t)),
        ];
        if (lines.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(bottom: _cfg.fontSize * 0.55),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
        );
      },
    );
  }

  Widget _openStacked(LiveTranslateState st, bool dark) {
    final lang = st.currentLang ?? _cfg.fixedSource;
    final text = [st.held, st.tail].where((s) => s.isNotEmpty).join(' ');
    final targets = _cfg.targetsFor(lang);
    final draftTarget = targets.isEmpty ? null : targets.first;
    final draft = draftTarget == null ? null : st.drafts[draftTarget];
    return Padding(
      padding: EdgeInsets.only(bottom: _cfg.fontSize * 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_cfg.showSource && _visible(lang))
            _line(lang, text, dark, dim: true, source: true),
          if (draftTarget != null && draft != null && draft.isNotEmpty && _visible(draftTarget))
            _line(draftTarget, draft, dark, dim: true),
        ],
      ),
    );
  }

  Widget _columns(LiveTranslateState st, bool dark, bool hasOpen) {
    final cols = _visibleLangs();
    if (cols.isEmpty) return const SizedBox.shrink();
    String cell(LiveUnit u, String lang) {
      if (lang == u.lang) return _cfg.showSource ? u.text : '';
      if (!u.targets.contains(lang)) return '';
      return u.translations[lang] ?? (u.isPending(lang) ? '…' : '');
    }

    Widget row(List<(String, bool)> cells) => Padding(
          padding: EdgeInsets.only(bottom: _cfg.fontSize * 0.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < cols.length; c++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: _cfg.fontSize * 0.3),
                    child: Text(cells[c].$1,
                        style: _style(cols[c], dark, dim: cells[c].$2)),
                  ),
                ),
            ],
          ),
        );

    final rows = <Widget>[];
    if (hasOpen) {
      final lang = st.currentLang ?? _cfg.fixedSource;
      final text = [st.held, st.tail].where((s) => s.isNotEmpty).join(' ');
      rows.add(row([
        for (final c in cols)
          if (c == lang)
            (_cfg.showSource ? text : '', true)
          else
            (st.drafts[c] ?? '', true)
      ]));
    }
    for (final u in st.units.reversed) {
      final cells = [for (final c in cols) (cell(u, c), !u.translations.containsKey(c) && c != u.lang)];
      if (cells.every((x) => x.$1.isEmpty)) continue;
      rows.add(row(cells));
    }
    return Column(
      children: [
        Row(
          children: [
            for (final c in cols)
              Expanded(
                child: Center(
                  child: _LangBadge(lang: c, size: _cfg.fontSize * 0.5, dark: dark, long: true),
                ),
              ),
          ],
        ),
        SizedBox(height: _cfg.fontSize * 0.5),
        Expanded(
          child: ListView(reverse: true, children: rows),
        ),
      ],
    );
  }

  Widget _toolbar(AppLocalizations l, LiveTranslateState st, bool dark, Color fg) {
    final running = st.status == LiveStatus.running;
    final bar = dark ? const Color(0xE6151515) : const Color(0xE6FFFFFF);
    final elapsed = st.startedAt == null
        ? ''
        : _fmtElapsed(DateTime.now().difference(st.startedAt!));
    return Material(
      color: bar,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: l.liveSetup,
              color: fg,
              icon: const Icon(Icons.arrow_back),
              onPressed: () async {
                if (st.isActive) await _stop();
                if (_fullscreen) await _toggleFullscreen();
                if (mounted) setState(() => _showBoard = false);
              },
            ),
            const SizedBox(width: 4),
            if (running) ...[
              const _PulseDot(),
              const SizedBox(width: 8),
              Text('LIVE  $elapsed',
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ] else if (st.status == LiveStatus.loading || st.status == LiveStatus.stopping)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              ),
            if (running && st.behindSec >= 1.5) ...[
              const SizedBox(width: 12),
              Text(l.liveBehind(st.behindSec.toStringAsFixed(1)),
                  style: const TextStyle(color: Colors.orangeAccent)),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final lang in _cfg.displayLanguages)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          visualDensity: VisualDensity.compact,
                          showCheckmark: false,
                          // An explicit fill: the app's chip theme paints a
                          // light surface that made the language colour
                          // unreadable on the dark bar. `color` wins over it.
                          color: WidgetStateProperty.resolveWith((states) =>
                              states.contains(WidgetState.selected)
                                  ? Color.alphaBlend(
                                      LanguageColors.of(lang, dark: dark)
                                          .withValues(alpha: 0.22),
                                      bar)
                                  : bar),
                          selected: _visible(lang),
                          side: BorderSide(color: LanguageColors.of(lang, dark: dark)),
                          label: Text(languageAutonym(lang),
                              style: TextStyle(
                                  color: _visible(lang)
                                      ? LanguageColors.of(lang, dark: dark)
                                      : fg.withValues(alpha: 0.4))),
                          tooltip: l.liveVisibleLanguages,
                          onSelected: (on) {
                            final h = {..._cfg.hiddenLanguages};
                            on ? h.remove(lang) : h.add(lang);
                            _set(_cfg.copyWith(hiddenLanguages: h));
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
                tooltip: l.liveSmaller,
                color: fg,
                icon: const Icon(Icons.text_decrease),
                onPressed: () => _font(-4)),
            IconButton(
                tooltip: l.liveLarger,
                color: fg,
                icon: const Icon(Icons.text_increase),
                onPressed: () => _font(4)),
            IconButton(
              tooltip: l.liveToggleLayout,
              color: fg,
              icon: Icon(_cfg.layout == LiveLayout.stacked
                  ? Icons.view_column_outlined
                  : Icons.view_agenda_outlined),
              onPressed: () => _set(_cfg.copyWith(
                  layout: _cfg.layout == LiveLayout.stacked
                      ? LiveLayout.columns
                      : LiveLayout.stacked)),
            ),
            IconButton(
              tooltip: l.liveCopyTranscript,
              color: fg,
              icon: const Icon(Icons.copy_all),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _ctl.transcriptText()));
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l.liveCopied)));
                }
              },
            ),
            IconButton(
                tooltip: l.liveClear,
                color: fg,
                icon: const Icon(Icons.clear_all),
                onPressed: _ctl.clear),
            IconButton(
              tooltip: l.liveFullscreen,
              color: fg,
              icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
              onPressed: _toggleFullscreen,
            ),
            const SizedBox(width: 4),
            if (st.isActive)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                onPressed: st.status == LiveStatus.stopping ? null : _stop,
                icon: const Icon(Icons.stop),
                label: Text(l.liveStop),
              )
            else
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.play_arrow),
                label: Text(l.liveStart),
              ),
          ],
        ),
      ),
    );
  }

  static String _fmtElapsed(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int x) => x.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  // ===================================================================
  // Setup
  // ===================================================================

  Widget _setup(BuildContext context, AppLocalizations l, LiveTranslateState st) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.liveTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (st.status == LiveStatus.error && st.message != null)
                Card(
                  color: theme.colorScheme.errorContainer,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer),
                    title: Text(st.message!,
                        style: TextStyle(
                            color: theme.colorScheme.onErrorContainer)),
                  ),
                ),
              Text(l.liveIntro, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 16),
              _section(theme, Icons.record_voice_over, l.liveSpokenLanguage, [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                        value: true,
                        icon: const Icon(Icons.auto_awesome),
                        label: Text(l.liveDetectAuto)),
                    ButtonSegment(
                        value: false,
                        icon: const Icon(Icons.lock_outline),
                        label: Text(l.liveFixedLanguage)),
                  ],
                  selected: {_cfg.lidMode != LiveLidMode.fixed},
                  onSelectionChanged: (s) => _set(_cfg.copyWith(
                      lidMode: s.first ? LiveLidMode.auto : LiveLidMode.fixed)),
                ),
                if (_cfg.lidMode == LiveLidMode.fixed) ...[
                  const SizedBox(height: 12),
                  _langDropdown(_cfg.fixedSource, (v) {
                    final routes = {..._cfg.routes};
                    routes.putIfAbsent(v, () => _cfg.targetsFor(v));
                    _set(_cfg.copyWith(fixedSource: v, routes: routes));
                  }),
                ],
              ]),
              _section(theme, Icons.alt_route, l.liveRoutesTitle, [
                Text(l.liveRoutesHelp, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                if (_cfg.lidMode == LiveLidMode.fixed)
                  _routeRow(l, _cfg.fixedSource, _cfg.targetsFor(_cfg.fixedSource),
                      removable: false)
                else ...[
                  for (final e in _cfg.routes.entries) _routeRow(l, e.key, e.value),
                  _routeRow(l, null, _cfg.defaultTargets, removable: false),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add),
                        label: Text(l.liveAddSpokenLanguage),
                        onPressed: () async {
                          final code = await _pickLanguage(
                              exclude: _cfg.routes.keys.toSet());
                          if (code == null) return;
                          _set(_cfg.copyWith(routes: {
                            ..._cfg.routes,
                            code: [
                              for (final t in _cfg.defaultTargets)
                                if (t != code) t
                            ],
                          }));
                        },
                      ),
                      const SizedBox(width: 8),
                      Text('${l.livePresets}:', style: theme.textTheme.labelLarge),
                      for (final p in LiveTranslateConfig.presets.entries)
                        ActionChip(
                          label: Text(p.key),
                          onPressed: () => _set(_cfg.copyWith(
                              routes: {
                                for (final e in p.value.entries) e.key: [...e.value]
                              },
                              lidMode: _cfg.lidMode == LiveLidMode.fixed
                                  ? LiveLidMode.auto
                                  : null)),
                        ),
                    ],
                  ),
                ],
              ]),
              _section(theme, Icons.memory, l.liveModelsTitle, _modelControls(l, theme)),
              _section(theme, Icons.mic, l.liveAudioTitle, [
                SegmentedButton<LiveAudioSource>(
                  segments: [
                    ButtonSegment(
                        value: LiveAudioSource.microphone,
                        icon: const Icon(Icons.mic),
                        label: Text(l.liveMicrophone)),
                    if (plat.isMacOS || plat.isLinux || plat.isWindows || plat.isAndroid)
                      ButtonSegment(
                          value: LiveAudioSource.systemAudio,
                          icon: const Icon(Icons.speaker),
                          label: Text(l.liveSystemAudio)),
                  ],
                  selected: {_cfg.audioSource},
                  onSelectionChanged: (s) => _set(_cfg.copyWith(audioSource: s.first)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.replay),
                      label: Text(l.liveReplayFile),
                      onPressed: _replay,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(l.liveReplayHelp, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ]),
              _section(theme, Icons.tv, l.liveDisplayTitle, _displayControls(l, theme)),
            ],
          ),
        ),
      ),
      // A full-width Start bar: the one action this page exists for.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l.liveStart,
                      style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, IconData icon, String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _routeRow(AppLocalizations l, String? src, List<String> targets,
      {bool removable = true}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    void setTargets(List<String> t) {
      if (src == null) {
        _set(_cfg.copyWith(defaultTargets: t));
      } else {
        _set(_cfg.copyWith(routes: {..._cfg.routes, src: t}));
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 170,
            child: src == null
                ? Text(l.liveOtherLanguages,
                    style: const TextStyle(fontStyle: FontStyle.italic))
                : _LangBadge(lang: src, size: 15, dark: dark, long: true),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward, size: 18),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (targets.isEmpty)
                  Text(l.liveTranscribeOnly,
                      style: TextStyle(color: Theme.of(context).hintColor)),
                for (final t in targets)
                  InputChip(
                    label: Text(languageAutonym(t),
                        style: TextStyle(
                            color: LanguageColors.of(t, dark: dark),
                            fontWeight: FontWeight.w600)),
                    side: BorderSide(color: LanguageColors.of(t, dark: dark)),
                    onDeleted: () => setTargets([...targets]..remove(t)),
                    deleteButtonTooltipMessage: l.liveRemove,
                  ),
                IconButton(
                  tooltip: l.liveAddTarget,
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () async {
                    final code = await _pickLanguage(
                        exclude: {...targets, if (src != null) src});
                    if (code != null) setTargets([...targets, code]);
                  },
                ),
              ],
            ),
          ),
          if (removable && src != null)
            IconButton(
              tooltip: l.liveRemove,
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                final r = {..._cfg.routes}..remove(src);
                _set(_cfg.copyWith(routes: r));
              },
            ),
        ],
      ),
    );
  }

  Widget _langDropdown(String value, ValueChanged<String> onChanged) {
    const langs = TextTranslationService.supportedLanguages;
    return DropdownButtonFormField<String>(
      initialValue: langs.any((e) => e.key == value) ? value : null,
      isExpanded: true,
      items: [
        for (final e in langs)
          DropdownMenuItem(
              value: e.key,
              child: Text('${languageAutonym(e.key)} — ${e.value} (${e.key})')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Future<String?> _pickLanguage({Set<String> exclude = const {}}) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _LanguagePickerDialog(exclude: exclude),
    );
  }

  List<Widget> _modelControls(AppLocalizations l, ThemeData theme) {
    final asr = _models
        .where((m) => m.isDownloaded && m.kind == ModelKind.asr)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final translators = _models
        .where((m) => m.isDownloaded && m.kind == ModelKind.translate)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final defaultName = ref.read(settingsServiceProvider).defaultModel;
    final defaultInfo = _models.where((m) => m.name == defaultName).firstOrNull;
    final hasAudioLid = _models.any((m) =>
        m.isDownloaded &&
        m.kind == ModelKind.lid &&
        RegExp('^(ecapa|firered|silero)').hasMatch(m.name));
    final hasTextLid = _models.any((m) =>
        m.isDownloaded && RegExp('^(cld3|fasttext-lid|glotlid)').hasMatch(m.name));

    return [
      DropdownButtonFormField<String?>(
        initialValue: asr.any((m) => m.name == _cfg.asrModel) ? _cfg.asrModel : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: l.liveRecognizer),
        items: [
          DropdownMenuItem<String?>(
              value: null,
              child: Text(l.liveAppDefaultModel(defaultInfo?.displayName ?? defaultName))),
          for (final m in asr)
            DropdownMenuItem<String?>(value: m.name, child: Text(m.displayName)),
        ],
        onChanged: (v) => _set(v == null
            ? _cfg.copyWith(clearAsrModel: true)
            : _cfg.copyWith(asrModel: v)),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String?>(
        initialValue: translators.any((m) => m.name == _cfg.translatorModel)
            ? _cfg.translatorModel
            : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: l.liveTranslator),
        items: [
          DropdownMenuItem<String?>(
              value: null,
              child: Text(translators.isEmpty
                  ? l.liveNoTranslator
                  : '${LiveTranslateController.defaultTranslator(_models)?.displayName ?? translators.first.displayName} (auto)')),
          for (final m in translators)
            DropdownMenuItem<String?>(value: m.name, child: Text(m.displayName)),
        ],
        onChanged: (v) => _set(v == null
            ? _cfg.copyWith(clearTranslatorModel: true)
            : _cfg.copyWith(translatorModel: v)),
      ),
      if (_cfg.lidMode != LiveLidMode.fixed) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<LiveLidMode>(
          initialValue: _cfg.lidMode,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.liveLanguageDetection),
          items: [
            DropdownMenuItem(value: LiveLidMode.auto, child: Text(l.liveLidAuto)),
            DropdownMenuItem(
                value: LiveLidMode.audio,
                enabled: hasAudioLid,
                child: Text(l.liveLidAudio)),
            DropdownMenuItem(
                value: LiveLidMode.text,
                enabled: hasTextLid,
                child: Text(l.liveLidText)),
            DropdownMenuItem(
                value: LiveLidMode.recognizer, child: Text(l.liveLidRecognizer)),
          ],
          onChanged: (v) {
            if (v != null) _set(_cfg.copyWith(lidMode: v));
          },
        ),
        const SizedBox(height: 4),
        Text(l.liveLidHelp, style: theme.textTheme.bodySmall),
      ],
      if (asr.isEmpty || translators.isEmpty || (!hasAudioLid && !hasTextLid)) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.lightbulb_outline, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(l.liveNoModelsHint, style: theme.textTheme.bodySmall)),
            TextButton(
              onPressed: () async {
                await context.push('/models');
                await _loadModels();
              },
              child: Text(l.liveOpenModels),
            ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _displayControls(AppLocalizations l, ThemeData theme) {
    final dark = _cfg.darkBackground;
    final sample = _cfg.displayLanguages.take(3).toList();
    return [
      Row(
        children: [
          Text(l.liveFontSize),
          Expanded(
            child: Slider(
              min: LiveTranslateConfig.minFont,
              max: LiveTranslateConfig.maxFont,
              divisions: ((LiveTranslateConfig.maxFont - LiveTranslateConfig.minFont) / 2).round(),
              label: _cfg.fontSize.round().toString(),
              value: _cfg.fontSize,
              onChanged: (v) => _set(_cfg.copyWith(fontSize: v)),
            ),
          ),
          SizedBox(width: 40, child: Text('${_cfg.fontSize.round()}')),
        ],
      ),
      // Live preview, in the board's own colours and size (capped so the
      // setup page stays usable at projector sizes).
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dark ? Colors.black : const Color(0xFFFAFAF7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final lang in sample)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _LangBadge(lang: lang, size: (_cfg.fontSize * 0.42).clamp(10, 22), dark: dark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _sampleSentence(lang),
                        style: _style(lang, dark).copyWith(
                            fontSize: _cfg.fontSize.clamp(14, 44)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SegmentedButton<LiveLayout>(
        segments: [
          ButtonSegment(
              value: LiveLayout.stacked,
              icon: const Icon(Icons.view_agenda_outlined),
              label: Text(l.liveLayoutStacked)),
          ButtonSegment(
              value: LiveLayout.columns,
              icon: const Icon(Icons.view_column_outlined),
              label: Text(l.liveLayoutColumns)),
        ],
        selected: {_cfg.layout},
        onSelectionChanged: (s) => _set(_cfg.copyWith(layout: s.first)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l.liveShowSource),
        value: _cfg.showSource,
        onChanged: (v) => _set(_cfg.copyWith(showSource: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l.liveShowDrafts),
        value: _cfg.showDrafts,
        onChanged: (v) => _set(_cfg.copyWith(showDrafts: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l.liveDarkBackground),
        value: _cfg.darkBackground,
        onChanged: (v) => _set(_cfg.copyWith(darkBackground: v)),
      ),
      Text(l.livePauseMs(_cfg.finalSilenceMs), style: theme.textTheme.bodyMedium),
      Slider(
        min: 400,
        max: 2000,
        divisions: 16,
        value: _cfg.finalSilenceMs.toDouble().clamp(400, 2000),
        label: '${_cfg.finalSilenceMs} ms',
        onChanged: (v) => _set(_cfg.copyWith(finalSilenceMs: v.round())),
      ),
      if (!plat.isMobile)
        Text(l.liveKeyboardHint, style: theme.textTheme.bodySmall),
    ];
  }

  static String _sampleSentence(String lang) => switch (lang) {
        'de' => 'Herzlich willkommen zur heutigen Sitzung.',
        'en' => 'A warm welcome to today’s session.',
        'fr' => 'Bienvenue à la séance d’aujourd’hui.',
        'es' => 'Bienvenidos a la sesión de hoy.',
        'it' => 'Benvenuti alla sessione di oggi.',
        'nl' => 'Welkom bij de sessie van vandaag.',
        'pl' => 'Witamy na dzisiejszej sesji.',
        'pt' => 'Bem-vindos à sessão de hoje.',
        _ => languageAutonym(lang),
      };

  Future<void> _replay() async {
    try {
      final pick = await pickFilesRobust(
        type: FileType.audio,
        allowedExtensions: const ['wav', 'mp3', 'flac', 'm4a', 'ogg', 'opus', 'aac'],
      );
      final path = pick.localPaths.firstOrNull;
      if (path == null) return;
      await _start(replayFile: path);
    } catch (e) {
      Log.instance.w('live', 'replay pick failed', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

/// A language's colour badge: the ISO code (compact) or the language's own
/// name ([long]) in its colour, so a viewer learns the colour once.
class _LangBadge extends StatelessWidget {
  const _LangBadge({
    required this.lang,
    required this.size,
    required this.dark,
    this.long = false,
  });
  final String lang;
  final double size;
  final bool dark;
  final bool long;

  @override
  Widget build(BuildContext context) {
    final c = LanguageColors.of(lang, dark: dark);
    return Container(
      constraints: BoxConstraints(minWidth: long ? 0 : size * 2.6),
      padding: EdgeInsets.symmetric(horizontal: size * 0.45, vertical: size * 0.12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: dark ? 0.16 : 0.12),
        border: Border.all(color: c, width: 1.5),
        borderRadius: BorderRadius.circular(size * 0.5),
      ),
      child: Text(
        long ? '${languageAutonym(lang)} · ${lang.toUpperCase()}' : lang.toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: c,
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: long ? 0.2 : 1.2,
          height: 1.2,
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
        child: Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
        ),
      );
}

class _LanguagePickerDialog extends StatefulWidget {
  const _LanguagePickerDialog({required this.exclude});
  final Set<String> exclude;
  @override
  State<_LanguagePickerDialog> createState() => _LanguagePickerDialogState();
}

class _LanguagePickerDialogState extends State<_LanguagePickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final q = _q.toLowerCase();
    final langs = TextTranslationService.supportedLanguages
        .where((e) => !widget.exclude.contains(e.key))
        .where((e) =>
            q.isEmpty ||
            e.key.contains(q) ||
            e.value.toLowerCase().contains(q) ||
            languageAutonym(e.key).toLowerCase().contains(q))
        .toList();
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _q = v),
              onSubmitted: (_) {
                if (langs.isNotEmpty) Navigator.pop(context, langs.first.key);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final e in langs)
                    ListTile(
                      dense: true,
                      leading: _LangBadge(lang: e.key, size: 13, dark: dark),
                      title: Text(languageAutonym(e.key)),
                      subtitle: Text(e.value),
                      onTap: () => Navigator.pop(context, e.key),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
