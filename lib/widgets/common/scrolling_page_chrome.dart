import 'package:flutter/material.dart';

import '../common_actions.dart';

class FadingTitleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FadingTitleAppBar({
    super.key,
    required this.title,
    required this.scrollOffset,
  });

  final String title;
  final double scrollOffset;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 0.5);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      title: Transform.translate(
        offset: Offset(0, (1 - (scrollOffset / 100).clamp(0.0, 1.0)) * 40),
        child: Opacity(
          opacity: ((((scrollOffset - 25) / 25).clamp(0.0, 1.0)) * 1.5)
              .clamp(0.0, 1.0),
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      centerTitle: false,
      actions: const [CommonActions()],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Opacity(
          opacity: (scrollOffset / 140).clamp(0.0, 1.0),
          child: Container(height: 0.9, color: const Color(0xFF48484A)),
        ),
      ),
    );
  }
}

class LargePageTitle extends StatelessWidget {
  const LargePageTitle({super.key, required this.title, this.align = true});

  final String title;
  final bool align;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      style: const TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: align ? Align(alignment: Alignment.centerLeft, child: text) : text,
    );
  }
}

class HeaderDivider extends StatelessWidget {
  const HeaderDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(color: Color(0xFF48484A), thickness: 0.5, height: 0),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.routeName,
    this.topMargin = 20,
    this.horizontalPadding = 15,
    this.showChevron = true,
  });

  final String title;
  final String? routeName;
  final double topMargin;
  final double horizontalPadding;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        if (showChevron)
          const Icon(Icons.chevron_right_rounded,
              color: Color.fromARGB(255, 186, 186, 186)),
      ],
    );

    return Container(
      margin: EdgeInsets.only(top: topMargin),
      height: 30,
      padding: EdgeInsets.only(left: horizontalPadding),
      child: routeName == null
          ? row
          : InkWell(
              onTap: () => Navigator.pushNamed(context, routeName!),
              child: row,
            ),
    );
  }
}
