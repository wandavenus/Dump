part of '../settings_page.dart';

class _LogFilterChipsState extends State<_LogFilterChips> {
  int _filter = 0; // 0=all, 1=errors, 2=warnings

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(
          label: 'Semua',
          selected: _filter == 0,
          onTap: () => setState(() => _filter = 0),
        ),
        const SizedBox(width: 4),
        _Chip(
          label: 'Error',
          selected: _filter == 1,
          onTap: () => setState(() => _filter = 1),
          color: const Color(0xFFF92D48),
        ),
        const SizedBox(width: 4),
        _Chip(
          label: 'Warning',
          selected: _filter == 2,
          onTap: () => setState(() => _filter = 2),
          color: Colors.orange,
        ),
      ],
    );
  }
}
