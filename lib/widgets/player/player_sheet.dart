import 'package:flutter/material.dart';

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
    return const Material(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(top: 50),
          child: Center(
            child: Text(
              'STEP 2',
              style: TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
