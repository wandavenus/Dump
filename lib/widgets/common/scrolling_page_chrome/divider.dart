part of '../scrolling_page_chrome.dart';

class HeaderDivider extends StatelessWidget {
  const HeaderDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(color: AppColors.of(context).separator, thickness: 0.5, height: 0),
    );
  }
}
