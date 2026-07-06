part of '../detail_sections.dart';

class DetailTopBar extends StatelessWidget {
  const DetailTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 16, right: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.red),
            ),
          ),
          const Row(
            children: [
              Icon(Icons.cast_rounded, size: 22, color: Colors.red),
              SizedBox(width: 20),
              Icon(Icons.add, size: 22, color: Colors.red),
              SizedBox(width: 20),
              Icon(Icons.more_vert, size: 22, color: Colors.red),
            ],
          ),
        ],
      ),
    );
  }
}
