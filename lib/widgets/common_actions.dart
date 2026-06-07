import 'package:flutter/material.dart';

class CommonActions extends StatelessWidget {
  const CommonActions({super.key});

  void _cast(BuildContext context) {
    // TODO: Cast function
  }

  void _more(BuildContext context) {
    // TODO: More menu function
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: const Offset(0, -0.0),
          child: IconButton(
            onPressed: () => _cast(context),
            icon: const Icon(Icons.cast),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -0.0),
          child: IconButton(
            onPressed: () => _more(context),
            icon: const Icon(Icons.more_vert),
          ),
        ),
      ],
    );
  }
}