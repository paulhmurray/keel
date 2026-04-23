import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/keel_colors.dart';
import '../../providers/update_provider.dart';
import '../../core/update/update_service.dart';

/// Full-width amber banner for critical updates — not dismissible.
class CriticalUpdateBanner extends StatelessWidget {
  const CriticalUpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final info = context.watch<UpdateProvider>().updateInfo;
    if (info == null || !info.critical) return const SizedBox.shrink();

    return _UpdateBannerBar(info: info, dismissible: false);
  }
}

/// Subtle notice rendered inside the left panel for standard updates.
class StandardUpdateNotice extends StatelessWidget {
  const StandardUpdateNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final info = context.watch<UpdateProvider>().updateInfo;
    if (info == null || info.critical) return const SizedBox.shrink();

    return _UpdatePanelNotice(info: info);
  }
}

class _UpdateBannerBar extends StatelessWidget {
  final UpdateInfo info;
  final bool dismissible;

  const _UpdateBannerBar({required this.info, required this.dismissible});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: KColors.amberDim,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 14, color: KColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Critical update required — Keel ${info.version}. ${info.releaseNotes}',
              style: const TextStyle(
                  color: KColors.amber, fontSize: 12),
            ),
          ),
          _TextButton(
            label: 'Download now',
            onTap: () => _launch(info.downloadUrl),
          ),
          const SizedBox(width: 12),
          _TextButton(
            label: 'Release notes',
            onTap: () => _launch(
                'https://keel-app.dev/changelog#v${info.version}'),
          ),
        ],
      ),
    );
  }

  void _launch(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) launchUrl(uri);
  }
}

class _UpdatePanelNotice extends StatelessWidget {
  final UpdateInfo info;

  const _UpdatePanelNotice({required this.info});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: KColors.surface2,
        border: Border.all(color: KColors.border2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_alt,
                  size: 11, color: KColors.amber),
              const SizedBox(width: 5),
              Text(
                'UPDATE AVAILABLE'.toUpperCase(),
                style: const TextStyle(
                  color: KColors.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Keel ${info.version}',
            style: const TextStyle(
                color: KColors.text, fontSize: 11, fontWeight: FontWeight.w500),
          ),
          if (info.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              info.releaseNotes,
              style: const TextStyle(color: KColors.textDim, fontSize: 10),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _ActionButton(
                label: 'Download',
                onTap: () {
                  final uri = Uri.tryParse(info.downloadUrl);
                  if (uri != null) launchUrl(uri);
                },
              ),
              const SizedBox(width: 6),
              _ActionButton(
                label: 'Later',
                onTap: () => context.read<UpdateProvider>().dismiss(),
                muted: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TextButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: KColors.amber,
          fontSize: 12,
          decoration: TextDecoration.underline,
          decorationColor: KColors.amber,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool muted;

  const _ActionButton(
      {required this.label, required this.onTap, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: muted ? Colors.transparent : KColors.amberDim,
          border: Border.all(
              color: muted ? KColors.border2 : KColors.amber.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: muted ? KColors.textDim : KColors.amber,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
