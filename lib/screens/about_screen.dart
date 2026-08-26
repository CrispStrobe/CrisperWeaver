import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../build_info.dart';
import '../l10n/generated/app_localizations.dart';
import '../main.dart' show modelServiceProvider;
import '../services/diagnostics_service.dart';

/// About / legal info screen — mirrors the layout used by our sibling
/// CrispSorter app: service provider, contact, disclaimer, then the
/// auto-aggregated open-source license list Flutter collects from every
/// pub dep via `LicenseRegistry`.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static const _email = 'postmaster@crispstro.be';
  static const _phone = '+49 176 6421 8601';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsAboutCrisperWeaver)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AppHeader(),
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.business,
            label: l.aboutServiceProvider,
            child: const Text(_providerJoin),
          ),
          _SectionCard(
            icon: Icons.alternate_email,
            label: l.aboutContact,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => _open('mailto:$_email'),
                  child: Text(l.aboutEmail(_email),
                      style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline)),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _open('tel:${_phone.replaceAll(' ', '')}'),
                  child: Text(l.aboutPhone(_phone),
                      style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline)),
                ),
              ],
            ),
          ),
          _SectionCard(
            icon: Icons.privacy_tip_outlined,
            label: l.aboutPrivacy,
            child: Text(l.aboutPrivacyText),
          ),
          _SectionCard(
            icon: Icons.memory_outlined,
            label: l.aboutBundledEngines,
            child: SelectableText(
              'CrispASR $kCrispAsrVersion (${_short(kCrispAsrRevision)})\n'
              'CrispEmbed $kCrispEmbedVersion (${_short(kCrispEmbedRevision)})\n'
              'glint $kGlintVersion (${_short(kGlintRevision)})\n'
              'App ${_short(kBuildGitHashFull)} • $kBuildTimestamp',
            ),
          ),
          _SectionCard(
            icon: Icons.verified_user,
            label: l.aboutSyntheticCompliance,
            child: Text(l.aboutSyntheticComplianceText),
          ),
          _SectionCard(
            icon: Icons.gavel,
            label: l.aboutDisclaimer,
            child: Text(l.aboutDisclaimerText),
          ),
          _SectionCard(
            icon: Icons.copyright,
            label: l.aboutLicense,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.aboutLicenseText),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () =>
                      _open('https://www.gnu.org/licenses/agpl-3.0.html'),
                  child: const Text(
                    'https://www.gnu.org/licenses/agpl-3.0.html',
                    style: TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            icon: const Icon(Icons.bug_report_outlined),
            label: Text(l.aboutReviewDiagnostics),
            onPressed: () => _showDiagnostics(context, ref),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined),
            label: Text(l.aboutOpenSourceLicenses),
            onPressed: () async {
              final info = await PackageInfo.fromPlatform();
              if (!context.mounted) return;
              showLicensePage(
                context: context,
                applicationName: 'CrisperWeaver',
                applicationVersion: '${info.version}+${info.buildNumber}',
                applicationLegalese:
                    '© ${DateTime.now().year} Christian Ströbele — AGPL-3.0',
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Joined at compile time for the provider card.
  static const _providerJoin =
      'Christian Ströbele\nNikolausstr. 5\n70190 Stuttgart\nDeutschland / Germany';

  static Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  static String _short(String revision) =>
      revision.length > 7 ? revision.substring(0, 7) : revision;

  static Future<void> _showDiagnostics(
      BuildContext context, WidgetRef ref) async {
    final report = await DiagnosticsService.buildReport(
      modelService: ref.read(modelServiceProvider),
    );
    if (!context.mounted) return;
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.aboutDiagnosticsTitle),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(child: SelectableText(report)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(l.historyCopy),
          ),
          if (!kIsWeb)
            FilledButton.icon(
              icon: const Icon(Icons.share_outlined),
              onPressed: () async {
                final file = await DiagnosticsService.exportReport(report);
                await SharePlus.instance.share(ShareParams(
                  files: [XFile(file.path)],
                  subject: 'CrisperWeaver diagnostics',
                ));
              },
              label: Text(l.logsShare),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final v = snap.hasData
            ? '${snap.data!.version} (${snap.data!.buildNumber})'
            : '…';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.graphic_eq,
                    size: 28,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CrisperWeaver',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(AppLocalizations.of(context).aboutVersion(v),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                        'On-device speech recognition via ggml / CrispASR',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
