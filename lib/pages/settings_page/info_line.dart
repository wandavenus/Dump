part of '../settings_page.dart';

class _InfoLine extends StatelessWidget {
  final String label;
  final String val;
  const _InfoLine(this.label, this.val);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
          ),
          Expanded(
            child: Text(
              val,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
