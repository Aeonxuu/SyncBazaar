import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

/// Writes an exported report to the user's Downloads folder.
///
/// Separate from [ReceiptSaver] despite the resemblance, because the two have
/// different destinations for a reason. A receipt goes to the photo gallery on
/// a tablet: it is produced dozens of times a shift and has to be one tap from
/// the home screen. A statement of account is produced once per bazaar, by an
/// owner, and is going to be emailed to a mall's accounts department — so it
/// belongs in Downloads, as a file, on every platform. `gal` could not take it
/// anyway; a .docx is not an image.
class DocumentSaver {
  const DocumentSaver();

  /// Returns a phrase for the confirmation, since where it landed is the only
  /// thing the user needs told.
  Future<String> save({
    required Uint8List bytes,
    required String fileName,
    required DocumentFormat format,
  }) async {
    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      fileExtension: format.extension,
      mimeType: format.mimeType,
    );
    return kIsWeb
        ? 'Downloaded $fileName.${format.extension}'
        : 'Saved to Downloads as $fileName.${format.extension}';
  }
}

/// The formats a report can be exported in.
enum DocumentFormat {
  /// Word, for documents someone will read or sign — the statement of account.
  docx,

  /// For the list of orders, which is a table someone will open in Excel.
  csv;

  String get extension => switch (this) {
    DocumentFormat.docx => 'docx',
    DocumentFormat.csv => 'csv',
  };

  MimeType get mimeType => switch (this) {
    DocumentFormat.docx => MimeType.microsoftWord,
    DocumentFormat.csv => MimeType.csv,
  };

  /// What the API expects in `?export=`.
  String get apiValue => switch (this) {
    DocumentFormat.docx => 'docx',
    DocumentFormat.csv => 'csv',
  };
}
