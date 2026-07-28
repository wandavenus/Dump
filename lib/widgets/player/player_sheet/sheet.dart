part of '../player_sheet.dart';

class PlayerSheet extends StatefulWidget {
  final bool expanded;
  final VoidCallback? onCollapse;

  const PlayerSheet({super.key, required this.expanded, this.onCollapse});

  @override
  State<PlayerSheet> createState() => _PlayerSheetState();
}
