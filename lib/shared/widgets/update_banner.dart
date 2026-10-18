import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/keel_colors.dart';
import '../../providers/update_provider.dart';
import '../../core/update/self_updater.dart';
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
          Icon(Icons.warning_amber_rounded, size: 14, color: KColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Critical update required — Keel ${info.version}. ${info.releaseNotes}',
              style: TextStyle(color: KColors.amber, fontSize: 12),
            ),
          ),
          _TextButton(
            label: 'Install now',
            onTap: () => context.read<UpdateProvider>().install(info.version),
          ),
          const SizedBox(width: 12),
          _TextButton(
            label: 'Release notes',
            onTap: () =>
                _launch('https://keel-app.dev/changelog#v${info.version}'),
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
              Icon(Icons.system_update_alt, size: 11, color: KColors.amber),
              const SizedBox(width: 5),
              Text(
                'UPDATE AVAILABLE'.toUpperCase(),
                style: TextStyle(
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
            style: TextStyle(
              color: KColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (info.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              info.releaseNotes,
              style: TextStyle(color: KColors.textDim, fontSize: 10),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _ActionButton(
                label: 'Install',
                onTap: () =>
                    context.read<UpdateProvider>().install(info.version),
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
        style: TextStyle(
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

  const _ActionButton({
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: muted ? Colors.transparent : KColors.amberDim,
          border: Border.all(
            color: muted
                ? KColors.border2
                : KColors.amber.withValues(alpha: 0.4),
          ),
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

/// Greys the whole app while an update downloads and installs, with the
/// phase and progress. On failure it shows the reason and a Close; the
/// app underneath is untouched.
class UpdateOverlay extends StatefulWidget {
  final Widget child;
  const UpdateOverlay({super.key, required this.child});

  @override
  State<UpdateOverlay> createState() => _UpdateOverlayState();
}

class _UpdateOverlayState extends State<UpdateOverlay> {
  // Once the relaunch has been handed off, a Close appears after a while
  // so a hand-off that never completes (an installer that refused, say)
  // cannot strand the user behind the barrier.
  DateTime? _relaunchSince;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<UpdateProvider>();
    final progress = p.progress;
    if (progress.phase == UpdatePhase.relaunching) {
      _relaunchSince ??= DateTime.now();
      _tick ??= Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _relaunchSince = null;
      _tick?.cancel();
      _tick = null;
    }
    final stuck =
        _relaunchSince != null &&
        DateTime.now().difference(_relaunchSince!) >
            const Duration(seconds: 30);
    final show = progress.busy || progress.phase == UpdatePhase.failed;
    return Stack(
      children: [
        widget.child,
        if (show) ...[
          const ModalBarrier(dismissible: false, color: Color(0xB3000000)),
          Center(
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: KColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        progress.phase == UpdatePhase.failed
                            ? Icons.error_outline
                            : Icons.system_update_alt,
                        size: 16,
                        color: progress.phase == UpdatePhase.failed
                            ? KColors.red
                            : KColors.amber,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        progress.phase == UpdatePhase.failed
                            ? 'Update failed'
                            : 'Updating Keel',
                        style: TextStyle(
                          color: KColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    progress.message,
                    style: TextStyle(color: KColors.textDim, fontSize: 12),
                  ),
                  if (progress.busy) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: progress.fraction,
                      color: KColors.amber,
                      backgroundColor: KColors.surface2,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Keel will close and reopen as the new version.',
                      style: TextStyle(color: KColors.textMuted, fontSize: 11),
                    ),
                  ],
                  if (progress.phase == UpdatePhase.failed || stuck) ...[
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (stuck)
                          Expanded(
                            child: Text(
                              'Still here? The hand-off did not complete. '
                              'Close this and try again, or install by hand.',
                              style: TextStyle(
                                color: KColors.amber,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        TextButton(
                          onPressed: () => p.clearError(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
