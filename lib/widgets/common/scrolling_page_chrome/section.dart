part of '../scrolling_page_chrome.dart';

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
