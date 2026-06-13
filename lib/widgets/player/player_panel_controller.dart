import '../../services/player_sheet_controller.dart';

/// Thin adapter yang menyatukan semua widget baru agar tidak langsung bergantung
/// pada [PlayerSheetController]. Cukup panggil [PlayerPanelController.instance.open()].
class PlayerPanelController {
  PlayerPanelController._();

  static final PlayerPanelController instance = PlayerPanelController._();

  void open() => PlayerSheetController.open();
  void close() => PlayerSheetController.close();
  void toggle() => PlayerSheetController.toggle();
}
