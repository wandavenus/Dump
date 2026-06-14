part of '../scrolling_page_chrome.dart';

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
