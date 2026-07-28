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
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: Color(0xFFF92D48),
              ),
            ),
          ),
          Row(
            children: [
              InkWell(
                onTap: () => Navigator.of(context).push(
                  ZoomFadeRoute<void>(page: const DownloadQueuePage()),
                ),
                child: const Icon(Icons.cast_rounded, size: 22, color: Color(0xFFF92D48)),
              ),
              SizedBox(width: 20),
              const Icon(Icons.add, size: 22, color: Color(0xFFF92D48)),
              SizedBox(width: 20),
              const Icon(
                CupertinoIcons.ellipsis_vertical,
                size: 22,
                color: Color(0xFFF92D48),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
