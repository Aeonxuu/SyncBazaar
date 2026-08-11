import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

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
  const ReceiptSaver();

  Future<String> save(Uint8List bytes, String fileName) async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await Gal.putImageBytes(bytes, name: fileName);
      return 'Saved to Photos';
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
