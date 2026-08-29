import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../main.dart' show modelServiceProvider;
import '../services/log_service.dart';
import '../services/model_service.dart';
import '../widgets/root_aware_back_leading.dart';

class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  late Future<_StorageSnapshot> _future;
  bool _moving = false;
  double _moveProgress = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_StorageSnapshot> _load() async {
    final service = ref.read(modelServiceProvider);
    final results = await Future.wait<Object>([
      service.getStorageByBackend(),
      service.getStorageHealth(),
    ]);
    return _StorageSnapshot(
      groups: results[0] as List<BackendStorage>,
      health: results[1] as ModelStorageHealth,
    );
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        // #35 — no back button when this was reached by a stack-replacing
        // `go()`; fall back to a home button.
        leading: rootAwareBackLeading(context),
        title: Text(l.storageTitle),
        actions: [
          IconButton(
            tooltip: l.storageRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<_StorageSnapshot>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'));
          }
          final data = snap.data!;
          final groups = data.groups;
          final total = groups.fold<int>(0, (a, g) => a + g.bytes);
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              itemCount: groups.length + 1 + (groups.isEmpty ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _buildHeader(
                      context, total, groups.length, data.health);
                }
                if (groups.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text(l.storageEmpty)),
                  );
                }
                final g = groups[i - 1];
                return _BackendTile(
                  group: g,
                  onDelete: () => _confirmDelete(g),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int totalBytes, int backendCount,
      ModelStorageHealth health) {
    final l = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.storage,
                  color: Theme.of(context).colorScheme.primary, size: 32),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.storageTotalUsed,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(_formatBytes(totalBytes),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(l.storageBackendCount(backendCount),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
            ]),
            const Divider(height: 24),
            Text(l.storageLocation,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(
              health.directory,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(health.freeBytes < 0
                ? l.storageFreeUnknown
                : l.storageFreeAvailable(_formatBytes(health.freeBytes))),
            if (health.isLowSpace) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l.storageLowSpaceHelp)),
                ],
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.drive_file_move_outline),
                label: Text(_moving
                    ? l.storageMoving((_moveProgress * 100).round())
                    : l.storageChangeLocation),
                onPressed: _moving ? null : _moveModelLibrary,
              ),
            ),
            if (_moving) LinearProgressIndicator(value: _moveProgress),
          ],
        ),
      ),
    );
  }

  Future<void> _moveModelLibrary() async {
    final l = AppLocalizations.of(context);
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: l.storagePickDestination,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.storageMoveTitle),
        content: Text(l.storageMoveExplanation(picked)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.storageMoveConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _moving = true;
      _moveProgress = 0;
    });
    try {
      final result = await ref.read(modelServiceProvider).moveModelsTo(
        picked,
        onProgress: (value) {
          if (mounted) setState(() => _moveProgress = value);
        },
      );
      if (!mounted) return;
      final removeOld = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(l.storageMoveCompleteTitle),
          content: Text(l.storageMoveComplete(
              result.fileCount, _formatBytes(result.bytes), picked)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.storageKeepOldCopy),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.storageRemoveOldCopy),
            ),
          ],
        ),
      );
      if (removeOld == true) {
        final removed = await ref
            .read(modelServiceProvider)
            .removeVerifiedOldModelCopy(
                result.sourceDirectory, result.targetDirectory);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(l.storageOldCopyRemoved(_formatBytes(removed)))),
          );
        }
      }
      _refresh();
    } catch (e, st) {
      Log.instance.w('storage', 'model library move failed',
          error: e, stack: st, fields: {'target': picked});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.storageMoveFailed('$e'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _moving = false;
          _moveProgress = 0;
        });
      }
    }
  }

  Future<void> _confirmDelete(BackendStorage g) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.storageDeleteTitle(g.backend)),
        content: Text(l.storageDeleteMessage(g.formattedSize, g.fileCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.storageDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final freed =
          await ref.read(modelServiceProvider).deleteBackendModels(g.backend);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.storageDeletedSnack(_formatBytes(freed)))),
      );
      _refresh();
    } catch (e, st) {
      Log.instance.w('storage', 'delete backend failed',
          error: e, stack: st, fields: {'backend': g.backend});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _StorageSnapshot {
  final List<BackendStorage> groups;
  final ModelStorageHealth health;

  const _StorageSnapshot({required this.groups, required this.health});
}

class _BackendTile extends StatelessWidget {
  final BackendStorage group;
  final VoidCallback onDelete;

  const _BackendTile({required this.group, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isOther = group.backend == '(other)';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            group.backend.isEmpty ? '?' : group.backend[0].toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(
          group.backend,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle:
            Text(l.storageFilesCount(group.formattedSize, group.fileCount)),
        trailing: isOther
            ? null
            : IconButton(
                tooltip: l.storageDeleteAllTooltip,
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
      ),
    );
  }
}
