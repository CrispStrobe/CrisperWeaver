import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/generated/app_localizations.dart';
import '../services/batch_queue_service.dart';
import '../services/log_service.dart';
import '../utils/audio_utils.dart';

/// Always-visible drop target for multi-file transcription queues.
///
/// Two ways to populate it:
///   1. drop files directly on this card → *every* file is enqueued;
///   2. drop more-than-one file on the main window → first file is
///      still picked as the active selection, subsequent files land
///      here (see `_onFilesDropped` in `transcription_screen.dart`).
///
/// Drops on this card set `BatchQueueNotifier._lastReceivedDropAt` so
/// the page-level DropTarget can dedup when the underlying OS delivers
/// the drop to both DropTargets (nested).
class BatchQueueCard extends ConsumerStatefulWidget {
  const BatchQueueCard({super.key});

  @override
  ConsumerState<BatchQueueCard> createState() => _BatchQueueCardState();
}

class _BatchQueueCardState extends ConsumerState<BatchQueueCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(batchQueueProvider);
    final l = AppLocalizations.of(context);

    final queued = jobs.where((j) => j.status == BatchJobStatus.queued).length;
    final running =
        jobs.where((j) => j.status == BatchJobStatus.running).length;
    final done = jobs.where((j) => j.status == BatchJobStatus.done).length;
    final errored = jobs.where((j) => j.status == BatchJobStatus.error).length;
    // §5.23 Q1 ETA badge: sum of probed durations across still-to-run
    // jobs (queued + running) so the card shows total audio left.
    // Probes that haven't returned yet contribute 0; the badge reads
    // "≥ Xm" so the user knows it's a lower bound when some files
    // are still being measured.
    final pendingDurationSec = jobs
        .where((j) =>
            j.status == BatchJobStatus.queued ||
            j.status == BatchJobStatus.running)
        .map((j) => j.durationSec ?? 0.0)
        .fold<double>(0.0, (a, b) => a + b);
    final probedCount = jobs
        .where((j) =>
            (j.status == BatchJobStatus.queued ||
                j.status == BatchJobStatus.running) &&
            j.durationSec != null)
        .length;
    final pendingTotal = queued + running;
    final hasUnprobed = pendingTotal > 0 && probedCount < pendingTotal;
    final etaLabel = _formatEta(pendingDurationSec, partial: hasUnprobed);

    return DropTarget(
      onDragEntered: (_) => setState(() => _hover = true),
      onDragExited: (_) => setState(() => _hover = false),
      onDragDone: _onDrop,
      child: Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        color: _hover ? Theme.of(context).colorScheme.primaryContainer : null,
        shape: _hover
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.playlist_play, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l.batchQueueTitle,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                jobs.isEmpty
                                    ? l.batchQueueDropHint
                                    : l.batchQueueSummary(
                                        queued, running, done, errored),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700),
                              ),
                            ),
                            // §5.23 Q1 ETA badge — total pending audio
                            // (queued + running). Shows "~ 12m" when
                            // some files haven't been probed yet,
                            // "12m" when every pending job has a
                            // measured duration. Hidden when zero.
                            if (etaLabel.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  etaLabel,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade800,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ]),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (done > 0)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.cleaning_services_outlined,
                          size: 18),
                      tooltip: l.batchClearCompleted,
                      onPressed: () => ref
                          .read(batchQueueProvider.notifier)
                          .clearCompleted(),
                    ),
                ],
              ),
              if (jobs.isEmpty)
                _EmptyDropHint()
              else ...[
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: jobs.length,
                    itemBuilder: (_, i) => _JobRow(job: jobs[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _hover = false);
    if (details.files.isEmpty) return;
    final supported = details.files
        .where((f) => AudioUtils.isSupportedAudioFile(f.path))
        .toList();
    if (supported.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .transcribeUnsupportedFile(details.files.first.name))),
      );
      return;
    }

    final q = ref.read(batchQueueProvider.notifier);
    final l = AppLocalizations.of(context);
    int enqueued = 0;
    for (final f in supported) {
      // §5.25.11 — Fingerprint dedup: single file → prompt, batch → auto-skip.
      final dup = await q.checkFingerprintDedup(f.path);
      if (dup != null) {
        if (supported.length == 1 && mounted) {
          final again = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l.fingerprintDedupTitle),
              content: Text(l.fingerprintDedupBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l.dialogCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l.fingerprintDedupTranscribeAgain),
                ),
              ],
            ),
          );
          if (again != true) continue;
        } else {
          continue;
        }
      }
      q.enqueue(f.path);
      enqueued++;
    }
    q.markDropReceived();

    Log.instance.i('batch', 'drop enqueued', fields: {
      'count': enqueued,
    });

    if (enqueued > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.batchEnqueueAdded(enqueued)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Render the §5.23 Q1 ETA badge. Returns empty string when the
  /// caller should hide the chip (no pending audio measured yet).
  /// `partial` = true means some pending jobs haven't been probed; we
  /// prefix with "≥ " so the user reads it as a lower bound.
  String _formatEta(double seconds, {required bool partial}) {
    if (seconds <= 0) return '';
    final mins = seconds / 60.0;
    final String body;
    if (mins < 1) {
      body = '< 1m';
    } else if (mins < 60) {
      body = '${mins.round()}m';
    } else {
      final h = (mins / 60).floor();
      final m = (mins.round() % 60);
      body = m == 0 ? '${h}h' : '${h}h${m}m';
    }
    return partial ? '~ $body' : body;
  }
}

class _EmptyDropHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(Icons.cloud_upload_outlined,
              size: 32, color: Colors.grey.shade500),
          const SizedBox(height: 6),
          Text(
            l.batchQueueDropHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

class _JobRow extends ConsumerWidget {
  const _JobRow({required this.job});
  final BatchJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = p.basename(job.filePath);
    final (icon, color) = switch (job.status) {
      BatchJobStatus.queued => (Icons.schedule, Colors.grey.shade600),
      BatchJobStatus.running => (Icons.refresh, Colors.blue.shade700),
      BatchJobStatus.done => (Icons.check, Colors.green.shade700),
      BatchJobStatus.error => (Icons.error_outline, Colors.red.shade700),
      BatchJobStatus.cancelled => (Icons.block, Colors.grey.shade500),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                if (job.status == BatchJobStatus.running)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: LinearProgressIndicator(
                      value: job.progress,
                      minHeight: 2,
                    ),
                  )
                else if (job.status == BatchJobStatus.error &&
                    job.errorMessage != null)
                  Text(
                    job.errorMessage!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                  ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 16),
            tooltip: AppLocalizations.of(context).batchRemove,
            onPressed: () =>
                ref.read(batchQueueProvider.notifier).remove(job.id),
          ),
        ],
      ),
    );
  }
}
