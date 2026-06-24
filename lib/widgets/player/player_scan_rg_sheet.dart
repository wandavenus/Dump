import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/local_song.dart';
import '../../services/replay_gain_scanner_service.dart';

void showScanRgSheet(BuildContext context, LocalSong song) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.68,
      child: _ScanRgSheet(song: song),
    ),
  );
}

class _ScanRgSheet extends StatefulWidget {
  final LocalSong song;
  const _ScanRgSheet({required this.song});

  @override
  State<_ScanRgSheet> createState() => _ScanRgSheetState();
}

enum _ScanState { idle, scanning, done, error }

class _ScanRgSheetState extends State<_ScanRgSheet>
    with SingleTickerProviderStateMixin {
  _ScanState _state = _ScanState.idle;
  RgScanResult? _result;
  String _errorMsg = '';

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _startScan();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _state = _ScanState.scanning);
    try {
      final result = await ReplayGainScannerService.scan(widget.song.path);
      if (mounted) setState(() { _state = _ScanState.done; _result = result; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _ScanState.error;
          _errorMsg = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF92D48).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: Color(0xFFF92D48),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ReplayGain Scanner',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Divider(color: Colors.white12, height: 1),
          ),

          Expanded(child: _buildBody()),

          // Bottom button
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: _buildBottomButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return switch (_state) {
      _ScanState.idle     => const SizedBox(),
      _ScanState.scanning => _buildScanning(),
      _ScanState.done     => _buildResult(),
      _ScanState.error    => _buildError(),
    };
  }

  Widget _buildScanning() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF92D48).withValues(alpha: 0.12),
              ),
              child: const Center(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    color: Color(0xFFF92D48),
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Analyzing audio…',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Decoding PCM · Measuring LUFS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final r = _result!;
    final gainPositive = r.trackGainDb >= 0;
    final gainColor = gainPositive ? const Color(0xFF30D158) : const Color(0xFFFF9F0A);
    final lufsStr   = r.integratedLufs.toStringAsFixed(1);
    final gainStr   = (gainPositive ? '+' : '') + r.trackGainDb.toStringAsFixed(2);
    final peakStr   = r.trackPeak.toStringAsFixed(4);
    final peakDb    = r.trackPeak > 0
        ? 20.0 * math.log(r.trackPeak.clamp(1e-10, 2.0)) / math.ln10
        : -99.0;
    final peakDbStr = (peakDb >= 0 ? '+' : '') + peakDb.toStringAsFixed(1);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _resultCard(children: [
            _resultRow(
              icon: Icons.volume_up_rounded,
              label: 'Integrated Loudness',
              value: '$lufsStr LUFS',
              valueColor: Colors.white,
            ),
            const _RowDivider(),
            _resultRow(
              icon: Icons.tune_rounded,
              label: 'Track Gain',
              value: '$gainStr dB',
              valueColor: gainColor,
            ),
            const _RowDivider(),
            _resultRow(
              icon: Icons.show_chart_rounded,
              label: 'True Peak',
              value: '$peakStr  ($peakDbStr dBFS)',
              valueColor: r.trackPeak >= 1.0
                  ? const Color(0xFFFF453A)
                  : Colors.white,
            ),
          ]),
          const SizedBox(height: 14),
          _statusBadge(r.tagsWritten),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF453A).withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.error_outline_rounded,
                  color: Color(0xFFFF453A), size: 32),
            ),
            const SizedBox(height: 18),
            const Text(
              'Scan Failed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMsg.isNotEmpty ? _errorMsg : 'Could not decode audio file.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    if (_state == _ScanState.scanning) {
      return const SizedBox(height: 48);
    }
    if (_state == _ScanState.error) {
      return Row(
        children: [
          Expanded(child: _outlineButton('Retry', _startScan)),
          const SizedBox(width: 12),
          Expanded(
            child: _filledButton('Close', () => Navigator.of(context).pop()),
          ),
        ],
      );
    }
    return _filledButton('Done', () => Navigator.of(context).pop());
  }

  Widget _resultCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(children: children),
    );
  }

  Widget _resultRow({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white60, fontSize: 14)),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(bool tagsWritten) {
    final color   = tagsWritten ? const Color(0xFF30D158) : const Color(0xFFFF9F0A);
    final icon    = tagsWritten ? Icons.check_circle_outline_rounded
                                : Icons.warning_amber_rounded;
    final message = tagsWritten
        ? 'Tags written to file successfully'
        : 'Could not write tags — file may be read-only';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filledButton(String label, VoidCallback onTap) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF92D48),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }

  Widget _outlineButton(String label, VoidCallback onTap) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: Colors.white12, indent: 48);
}
