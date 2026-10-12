import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;

import '../data/repositories/save_folder_repository.dart';
import 'mac_file_writer.dart';

/// Writes a rendered receipt to wherever the user will actually find it.
///
/// Two backends rather than one, because "saved" means something different per
/// platform. `file_saver` on Android writes to `Android/data/<pkg>/files/`,
/// which no file manager surfaces — a receipt saved there is a receipt lost.
/// `gal` puts it in the photo gallery via MediaStore, which is one tap from the
/// tablet's home screen and, unlike a system save dialog, costs the cashier
/// nothing per sale. On web and desktop `file_saver` is already right: a
/// browser download, or `~/Downloads`.
///
/// Returns a phrase for the confirmation dialog, since where the file went is
/// the only thing the cashier needs to know and it differs by platform.
class ReceiptSaver {
  const ReceiptSaver({
    SaveFolderRepository folderRepository = const SaveFolderRepository(),
  }) : _folderRepository = folderRepository;

  final SaveFolderRepository _folderRepository;

  Future<String> save(Uint8List bytes, String fileName) async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await Gal.putImageBytes(bytes, name: fileName);
      return 'Saved to Photos';
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      final initialDirectory = await _folderRepository.folderFor(
        SaveDocumentKind.receipts,
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save $fileName',
        fileName: '$fileName.png',
        initialDirectory: initialDirectory,
        // Not `bytes:` -- file_picker throws UnsupportedError if given bytes
        // on macOS. It only returns the chosen path there, so the write
        // below is on us.
      );
      if (path == null) {
        // Not a failure -- the cashier backed out of the dialog. Treated the
        // same as a completed save so the caller does not report an error
        // over a receipt that already printed and rang up fine.
        return 'Not saved';
      }
      await const MacFileWriter().write(path, bytes);
      await _folderRepository.setFolderFor(
        SaveDocumentKind.receipts,
        p.dirname(path),
      );
      return 'Saved $fileName.png';
    }

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      fileExtension: 'png',
      mimeType: MimeType.png,
    );
    return kIsWeb ? 'Downloaded $fileName.png' : 'Saved to Downloads';
  }
}
