part of '../settings_page.dart';

class _AudioSessionInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Info Audio Engine',
              style: TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 6),
          _InfoLine('DSP Pipeline',
              DeviceDsp.isAndroid ? 'Android DSP' : 'Web / Fallback'),
          _InfoLine('Virtualizer',
              DeviceDsp.virtualizerSupported ? 'Didukung ✓' : 'Tidak tersedia ✗'),
          _InfoLine('BassBoost',
              DeviceDsp.bassBoostSupported ? 'Didukung ✓' : 'Tidak tersedia ✗'),
        ],
      ),
    );
  }
}
