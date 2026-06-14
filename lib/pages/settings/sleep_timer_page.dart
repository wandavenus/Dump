import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../services/sleep_timer_service.dart';

class SleepTimerPage extends StatelessWidget {
  const SleepTimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(child: _SleepTimerBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(CupertinoIcons.back, color: Colors.white),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Sleep Timer',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Cancel button — only visible when timer is active
          ValueListenableBuilder<bool>(
            valueListenable: SleepTimerService.isActive,
            builder: (_, active, __) => active
                ? CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: SleepTimerService.cancel,
                    child: const Text(
                      'Batalkan',
                      style: TextStyle(
                          color: Color(0xFFF92D48), fontSize: 15),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SleepTimerBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SleepTimerService.isActive,
      builder: (_, active, __) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (active) ...[
              _ActiveTimerCard(),
              const SizedBox(height: 24),
            ],
            const Padding(
              padding: EdgeInsets.only(left: 0, bottom: 8),
              child: Text(
                'PILIH DURASI',
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            _PresetList(),
          ],
        );
      },
    );
  }
}

// ─── Active timer card ────────────────────────────────────────────────────────

class _ActiveTimerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF92D48).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bedtime, color: Color(0xFFF92D48), size: 18),
              SizedBox(width: 8),
              Text(
                'Sleep Timer Aktif',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<Duration?>(
            valueListenable: SleepTimerService.remaining,
            builder: (_, remaining, __) {
              if (remaining == null) {
                // End-of-song mode
                return const Text(
                  'Berhenti setelah lagu ini selesai',
                  style: TextStyle(
                      color: Color(0xFF8E8E93), fontSize: 14),
                );
              }
              final h = remaining.inHours;
              final m = remaining.inMinutes % 60;
              final s = remaining.inSeconds % 60;
              final label = h > 0
                  ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
                  : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
              return Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFF92D48),
                  fontSize: 40,
                  fontWeight: FontWeight.w200,
                  letterSpacing: 2,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Musik akan berhenti saat timer habis',
            style: TextStyle(color: Color(0xFF636366), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─── Preset list ──────────────────────────────────────────────────────────────

class _PresetList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(SleepTimerService.presets.length, (i) {
          final preset = SleepTimerService.presets[i];
          final isLast = i == SleepTimerService.presets.length - 1;
          return Column(
            children: [
              InkWell(
                borderRadius: isLast
                    ? const BorderRadius.vertical(bottom: Radius.circular(12))
                    : BorderRadius.zero,
                onTap: () => _startPreset(context, preset),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(
                        preset.duration == null
                            ? Icons.music_note
                            : Icons.timer,
                        color: const Color(0xFF8E8E93),
                        size: 20,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          preset.label,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16),
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: Color(0xFF48484A), size: 20),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                const Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: Color(0xFF38383A),
                  indent: 50,
                ),
            ],
          );
        }),
      ),
    );
  }

  void _startPreset(
      BuildContext context,
      ({String label, Duration? duration}) preset) {
    if (preset.duration == null) {
      SleepTimerService.startEndOfSong();
    } else {
      SleepTimerService.startDuration(preset.duration!);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          preset.duration == null
              ? 'Timer: berhenti setelah lagu ini'
              : 'Timer: ${preset.label}',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1C1C1E),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
