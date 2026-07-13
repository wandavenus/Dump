part of '../settings_widgets.dart';

class SettingsSliderRow extends StatefulWidget {
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Future<void> Function(double) onChanged;
  final bool showReset;
  final VoidCallback? onReset;

  /// Saat true, slider disembunyikan di balik baris header yang bisa diketuk.
  /// Subtitle tampil sebagai value-hint di header saat collapsed.
  final bool expandable;

  /// Deskripsi singkat yang menjelaskan fungsi fitur ini ke user. Tampil di
  /// bawah slider dengan style redup/italic. Opsional — kalau null, tidak
  /// ada baris tambahan yang dirender.
  final String? description;

  const SettingsSliderRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions = 20,
    this.showReset = false,
    this.onReset,
    this.expandable = false,
    this.description,
  });

  @override
  State<SettingsSliderRow> createState() => _SettingsSliderRowState();
}

class _SettingsSliderRowState extends State<SettingsSliderRow>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  Widget _buildSlider() => SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: const Color(0xFFF92D48),
          thumbColor: Colors.white,
          inactiveTrackColor: const Color(0xFF48484A),
          overlayColor: const Color(0x29F92D48),
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        ),
        child: Slider(
          value: widget.value.clamp(widget.min, widget.max).toDouble(),
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          onChanged: widget.onChanged,
        ),
      );

  @override
  Widget build(BuildContext context) {
    // ── Non-expandable: layout asli ──────────────────────────────────────────
    if (!widget.expandable) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(color: Colors.white, fontSize: 16)),
                ),
                if (widget.showReset && widget.onReset != null)
                  GestureDetector(
                    onTap: widget.onReset,
                    child: const Text('Reset',
                        style: TextStyle(color: Color(0xFFF92D48), fontSize: 13)),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(widget.subtitle,
                style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
            _buildSlider(),
            if (widget.description != null) ...[
              const SizedBox(height: 2),
              Text(
                widget.description!,
                style: const TextStyle(
                  color: Color(0xFF6D6D72),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // ── Expandable: accordion ────────────────────────────────────────────────
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — selalu terlihat, bisa diketuk
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                  Text(widget.subtitle,
                      style: const TextStyle(
                          color: Color(0xFF8E8E93), fontSize: 13)),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: Colors.white38, size: 18),
                  ),
                ],
              ),
            ),
          ),

          // Konten collapsible — fade + naik/turun
          SizeTransition(
            sizeFactor: _ctrl,
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: _fade,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showReset && widget.onReset != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: widget.onReset,
                        child: const Text('Reset',
                            style: TextStyle(
                                color: Color(0xFFF92D48), fontSize: 13)),
                      ),
                    ),
                  _buildSlider(),
                  if (widget.description != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        widget.description!,
                        style: const TextStyle(
                          color: Color(0xFF6D6D72),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          height: 1.3,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Info Row ─────────────────────────────────────────────────────────────────
