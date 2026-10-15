part of '../../settings_page.dart';

// ── AutoMix Section ──────────────────────────────────────────────────────
//
// Offline AI-free DJ-style auto-mixing: configuration, library analysis and
// crossfade guidance for [AutomixService]. Ordering is applied from the
// player's overflow menu ("AutoMix") on the active queue — this section only
// tunes how the AutomixEngine plans transitions.

class _AutomixSection extends StatelessWidget {
  const _AutomixSection();

  static const List<AutomixProfile> _profileOrder = [
    AutomixProfile.dj,
    AutomixProfile.harmonic,
    AutomixProfile.energy,
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ValueListenableBuilder<AutomixSettings>(
      valueListenable: AutomixService.settings,
      builder: (context, settings, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsSectionHeader(l.automixTitle),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l.automixDescription,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.8),
                    ),
              ),
            ),
            const SizedBox(height: 10),

            // ── Profile picker ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.automixProfileLabel,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final profile in _profileOrder) ...[
                        Expanded(
                          child: _AutomixProfileChip(
                            profile: profile,
                            selected: settings.profile == profile,
                            onTap: () => unawaited(_selectProfile(profile)),
                          ),
                        ),
                        if (profile != _profileOrder.last)
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _profileDesc(context, settings.profile),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SettingsDivider(),

            // ── BPM tolerance ─────────────────────────────────────────
            SettingsSliderRow(
              title: l.automixBpmTolerance,
              subtitle:
                  '${settings.bpmTolerancePercent.toStringAsFixed(0)} %',
              value: settings.bpmTolerancePercent,
              min: 2.0,
              max: 20.0,
              divisions: 9,
              onChanged: (v) => _update(
                settings.copyWith(bpmTolerancePercent: v),
              ),
              expandable: true,
              description: l.automixBpmToleranceDesc,
            ),
            const SettingsDivider(),

            // ── Crossfade beats ───────────────────────────────────────
            SettingsSliderRow(
              title: l.automixCrossfadeBeats,
              subtitle: l.automixBeats(settings.crossfadeBeats),
              value: settings.crossfadeBeats.toDouble(),
              min: 4.0,
              max: 64.0,
              divisions: 15,
              onChanged: (v) =>
                  _update(settings.copyWith(crossfadeBeats: v.toInt())),
              expandable: true,
              description: l.automixCrossfadeBeatsDesc,
            ),
            const SettingsDivider(),

            // ── Toggles ───────────────────────────────────────────────
            SettingsToggleRow(
              title: l.automixArtistVariety,
              value: settings.avoidArtistRepeat,
              onChanged: (v) => _update(
                settings.copyWith(avoidArtistRepeat: v),
              ),
            ),
            const SettingsDivider(),
            SettingsToggleRow(
              title: l.automixHarmonicFilter,
              value: settings.harmonicFilter,
              onChanged: (v) => _update(
                settings.copyWith(harmonicFilter: v),
              ),
            ),
            const SettingsDivider(),

            // ── Library analysis ──────────────────────────────────────
            _AutomixAnalyzerSection(),
          ],
        );
      },
    );
  }

  Future<void> _update(AutomixSettings value) =>
      AutomixService.saveSettings(value);

  Future<void> _selectProfile(AutomixProfile profile) {
    return _update(AutomixService.settings.value.copyWith(profile: profile));
  }

  static String _profileDesc(BuildContext context, AutomixProfile profile) {
    final l = context.l10n;
    return switch (profile) {
      AutomixProfile.dj => l.automixProfileDjDesc,
      AutomixProfile.harmonic => l.automixProfileHarmonicDesc,
      AutomixProfile.energy => l.automixProfileEnergyDesc,
    };
  }
}

class _AutomixProfileChip extends StatelessWidget {
  const _AutomixProfileChip({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final AutomixProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.18)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : theme.dividerColor,
          ),
        ),
        child: Text(
          switch (profile) {
            AutomixProfile.dj => l.automixProfileDj,
            AutomixProfile.harmonic => l.automixProfileHarmonic,
            AutomixProfile.energy => l.automixProfileEnergy,
          },
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.primary
                : theme.textTheme.bodyMedium?.color,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ── Batch library analysis ────────────────────────────────────────────────

class _AutomixAnalyzerSection extends StatefulWidget {
  @override
  State<_AutomixAnalyzerSection> createState() =>
      _AutomixAnalyzerSectionState();
}

class _AutomixAnalyzerSectionState extends State<_AutomixAnalyzerSection> {
  Future<void> _startScan() async {
    final l = context.l10n;
    try {
      final songs = await MediaStoreService.getSongs();
      if (!mounted) return;
      if (songs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.noSongsInLibrary)),
        );
        return;
      }
      unawaited(AutomixService.analyzeLibrary(songs));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.scanLibraryLoadFailed(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ValueListenableBuilder<AutomixAnalysisProgress>(
      valueListenable: AutomixService.analysisProgress,
      builder: (context, progress, _) {
        final running = progress.running;
        final rowLabel = running
            ? l.automixAnalyzingProgress(progress.done, progress.total)
            : l.automixAnalyzeLibrary;
        final sub = running
            ? (progress.currentTitle.length > 44
                ? '${progress.currentTitle.substring(0, 44)}…'
                : progress.currentTitle)
            : l.automixAnalyzeHint;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(rowLabel, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (running) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: progress.total > 0
                            ? progress.done / progress.total
                            : null,
                        minHeight: 3,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: running
                    ? AutomixService.cancelAnalysis
                    : _startScan,
                child: Text(running ? l.cancel : l.automixAnalyzeAction),
              ),
            ],
          ),
        );
      },
    );
  }
}
