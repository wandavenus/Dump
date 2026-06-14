part of '../detail_sections.dart';

class DetailTopBar extends StatelessWidget {
  const DetailTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 30, left: 10, right: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 15),
            padding: const EdgeInsets.all(5),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.red),
            ),
          ),
          const Row(children: [_CircleIcon(icon: Icons.add), SizedBox(width: 18), _CircleIcon(icon: Icons.more_horiz)]),
        ],
      ),
    );
  }
}
