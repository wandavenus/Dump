part of '../settings_page.dart';

class _AudioSessionInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Info Audio Engine',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 6),
          _InfoLine(
            'DSP Pipeline',
            AudioEngine.isAndroid ? 'Android DSP' : 'Web / Fallback',
          ),
          _InfoLine(
            'Virtualizer',
            AudioEngine.virtualizerSupported
                ? 'Didukung ✓'
                : 'Tidak tersedia ✗',
          ),
          _InfoLine(
            'BassBoost',
            AudioEngine.bassBoostSupported ? 'Didukung ✓' : 'Tidak tersedia ✗',
          ),
          _InfoLine(
            'PresetReverb',
            AudioEngine.reverbSupported ? 'Didukung ✓' : 'Tidak tersedia ✗',
          ),
        ],
      ),
    );
  }
}
