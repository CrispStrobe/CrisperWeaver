// lib/widgets/narrow_tabbed_body.dart — phone-width 3-tab layout.
// Extracted from transcription_screen.dart (§8.1).

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

/// Layer-3 narrow layout — three tabs (Input / Run / Output)
/// each filling the viewport one at a time. Stateful only so
/// the TabController persists across rebuilds; the tab content
/// itself is just whatever the caller passes in.
class NarrowTabbedBody extends StatefulWidget {
  const NarrowTabbedBody({
    super.key,
    required this.input,
    required this.controls,
    required this.output,
    required this.initialIndex,
  });

  final Widget input;
  final Widget controls;
  final Widget output;
  final int initialIndex;

  @override
  State<NarrowTabbedBody> createState() => _NarrowTabbedBodyState();
}

class _NarrowTabbedBodyState extends State<NarrowTabbedBody>
    with SingleTickerProviderStateMixin {
  late final TabController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialIndex,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: TabBar(
            controller: _ctrl,
            tabs: [
              Tab(
                icon: const Icon(Icons.input, size: 20),
                child: Text(l.tabInput),
              ),
              Tab(
                icon: const Icon(Icons.play_arrow, size: 20),
                child: Text(l.tabRun),
              ),
              Tab(
                icon: const Icon(Icons.subtitles_outlined, size: 20),
                child: Text(l.tabOutput),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _ctrl,
            // The transcript view inside `output` does its own
            // scrolling. Input is naturally tall and uses a
            // SingleChildScrollView. Controls is short and
            // benefits from being scrollable on tiny phones
            // where the row of action buttons + progress
            // indicator may grow.
            children: [
              SingleChildScrollView(child: widget.input),
              SingleChildScrollView(child: widget.controls),
              widget.output,
            ],
          ),
        ),
      ],
    );
  }
}
