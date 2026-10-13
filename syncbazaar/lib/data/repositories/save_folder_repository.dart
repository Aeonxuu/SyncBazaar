import 'package:shared_preferences/shared_preferences.dart';

/// Which recurring export a remembered save folder belongs to.
///
/// Kept separate per kind rather than one shared folder because a statement
/// of account goes to a mall's accounts department, an order list to the
/// venue, and a receipt nowhere near either -- three different destinations
/// an owner would reasonably want to keep apart.
enum SaveDocumentKind { soa, orderList, receipts, inventory }

/// Remembers, per [SaveDocumentKind], the folder a macOS "Save As" dialog was
/// last pointed at -- so the next one opens there instead of wherever the OS
/// happened to leave the panel.
///
/// Only macOS needs this. Android/iOS already get a folder choice every time
/// via the system save sheet (see `DocumentSaver.usesSaveSheet`), and a web
/// download has no folder concept for the app to remember in the first
/// place -- the browser owns that decision.
class SaveFolderRepository {
  const SaveFolderRepository();

  static String _key(SaveDocumentKind kind) =>
      'settings.saveFolder.${kind.name}';

  Future<String?> folderFor(SaveDocumentKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(kind));
  }

  Future<void> setFolderFor(SaveDocumentKind kind, String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_key(kind));
      return;
    }
    await prefs.setString(_key(kind), path);
  }
}
