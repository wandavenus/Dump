part of '../settings_page.dart';

class _AudioSessionInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.audioEngineInfo,
              style: TextStyle(color: c.primaryLabel, fontSize: 15)),
          const SizedBox(height: 6),
          _InfoLine(context.l10n.dspPipeline,
              DeviceDsp.isAndroid ? context.l10n.androidDsp : context.l10n.webFallback),
          _InfoLine(context.l10n.bassBoost,
              DeviceDsp.bassBoostSupported
                  ? context.l10n.supported
                  : context.l10n.unavailable),
        ],
      ),
    );
  }
}
