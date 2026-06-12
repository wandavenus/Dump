import 'package:flutter/material.dart';
import '../../services/player_sheet_controller.dart';

class PlayerSheet extends StatelessWidget {
  final bool expanded;
  final VoidCallback? onCollapse;

  const PlayerSheet({
    super.key,
    required this.expanded,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !expanded,
      child: AnimatedPositioned(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        left: 0,
        right: 0,
        top: expanded ? 0 : MediaQuery.of(context).size.height,
        bottom: 0,
        child: Material(
          color: const Color(0xFF000000),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: PlayerSheetController.close,
                  child: Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Now Playing',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
