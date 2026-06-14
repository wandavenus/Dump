part of '../search_sections.dart';

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final bool loading;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
    required this.loading,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 10),
      child: GestureDetector(
        // Request focus ONLY when user explicitly taps the search bar
        onTap: () => focusNode.requestFocus(),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const SizedBox(width: 10),
              const Icon(Icons.search, color: Color(0xFF8E8E93), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: false,   // Never autofocus on page load
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  cursorColor: const Color(0xFFF92D48),
                  decoration: const InputDecoration(
                    hintText: 'Artis, Lagu, Album, dan lainnya',
                    hintStyle:
                        TextStyle(color: Color(0xFF8E8E93), fontSize: 15),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => focusNode.unfocus(),
                  onTapOutside: (_) => focusNode.unfocus(),
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                )
              else if (isSearching)
                GestureDetector(
                  onTap: onClear,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child:
                        Icon(Icons.cancel, color: Color(0xFF8E8E93), size: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Search Results ───────────────────────────────────────────────────────────
