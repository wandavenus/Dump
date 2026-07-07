part of '../scrolling_page_chrome.dart';

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
      padding: const EdgeInsets.fromLTRB(kPageLeftPadding, 14, kPageLeftPadding, 6),
      child: align ? Align(alignment: Alignment.centerLeft, child: text) : text,
    );
  }
}
