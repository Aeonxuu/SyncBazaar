import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/repositories/save_folder_repository.dart';
import 'mac_file_writer.dart';

/// Writes an exported report somewhere the person who asked for it can find it.
///
/// Separate from [ReceiptSaver] despite the resemblance, because the two have
/// different destinations for a reason. A receipt goes to the photo gallery on
/// a tablet: it is produced dozens of times a shift and has to be one tap from
/// the home screen. A statement of account is produced once per bazaar, by an
/// owner, and is going to be emailed to a mall's accounts department, so it
/// belongs in a folder as a file. `gal` could not take it anyway; a .docx is
/// not an image.
///
/// Android takes a different route from everywhere else. `saveFile` there
/// writes to `Android/data/<package>/files/`, which is private to the app and
/// hidden by most file managers, so the export announced "Saved to Downloads"
/// and then could not be found in Downloads or anywhere else. `saveAs` hands
/// the system's own save sheet to the user instead: they choose the folder,
/// which means they also know where it went. That trade would be wrong for a
/// receipt, where a dialog per sale would be unbearable, and is right here,
/// where an export happens once at the end of a bazaar.
class DocumentSaver {
  const DocumentSaver({
    SaveFolderRepository folderRepository = const SaveFolderRepository(),
  }) : _folderRepository = folderRepository;

  final SaveFolderRepository _folderRepository;

  /// Returns a phrase for the confirmation, or null if the user backed out of
  /// the save sheet. Null is not a failure and must not be reported as one.
  Future<String?> save({
    required Uint8List bytes,
    required String fileName,
    required DocumentFormat format,
    required SaveDocumentKind kind,
  }) async {
    if (usesSaveSheet) {
      final path = await FileSaver.instance.saveAs(
        name: fileName,
        bytes: bytes,
        fileExtension: format.extension,
        mimeType: format.mimeType,
      );
      // Null means the sheet was dismissed without choosing anywhere.
      return path == null ? null : 'Saved $fileName.${format.extension}';
    }

    if (usesMacSaveDialog) {
      return _saveOnMac(
        bytes: bytes,
        fileName: fileName,
        format: format,
        kind: kind,
      );
    }

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

  /// A native "Save As" dialog, like the mobile save sheet but for macOS.
  ///
  /// Opens on whichever folder [kind] was saved to last, via
  /// [SaveFolderRepository], and remembers wherever the user points it this
  /// time -- so a statement of account and an order list can each land in
  /// their own folder without asking twice in the same run.
  Future<String?> _saveOnMac({
    required Uint8List bytes,
    required String fileName,
    required DocumentFormat format,
    required SaveDocumentKind kind,
  }) async {
    final initialDirectory = await _folderRepository.folderFor(kind);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save $fileName',
      fileName: '$fileName.${format.extension}',
      initialDirectory: initialDirectory,
      // Not `bytes:` -- file_picker throws UnsupportedError if given bytes
      // on macOS. It only returns the chosen path there, so the write below
      // is on us.
    );
    // Null means the dialog was dismissed without choosing anywhere.
    if (path == null) {
      return null;
    }
    await const MacFileWriter().write(path, bytes);
    await _folderRepository.setFolderFor(kind, p.dirname(path));
    return 'Saved $fileName.${format.extension}';
  }

  /// Only the mobile platforms, where the plain save has nowhere visible to put
  /// a file. Web still lands in Downloads with no folder concept to offer, and
  /// macOS gets its own dialog below rather than this one -- see
  /// [usesMacSaveDialog].
  ///
  /// Public so a test can assert the routing without going near a platform
  /// channel, which is the part that cannot be exercised here.
  static bool get usesSaveSheet =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// macOS only. Windows/Linux are not a build target for this app (see
  /// CLAUDE.md), so they are left on the plain Downloads save rather than
  /// wired up to a dialog nobody has tested.
  static bool get usesMacSaveDialog =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
}

/// The formats a report can be exported in.
enum DocumentFormat {
  /// Word, for documents someone will read or sign — the statement of account.
  docx,

  /// For the list of orders, which is a table someone will open in Excel.
  csv,

  /// Excel proper, for the list of orders. Chosen over [csv] because that
  /// report is a workbook -- one sheet per payment method, with columns that
  /// differ between them -- and a .csv is a single flat table by definition.
  xlsx;

  String get extension => switch (this) {
    DocumentFormat.docx => 'docx',
    DocumentFormat.csv => 'csv',
    DocumentFormat.xlsx => 'xlsx',
  };

  MimeType get mimeType => switch (this) {
    DocumentFormat.docx => MimeType.microsoftWord,
    DocumentFormat.csv => MimeType.csv,
    DocumentFormat.xlsx => MimeType.microsoftExcel,
  };

  /// What the API expects in `?export=`. Null for a format the server does
  /// not render -- [xlsx] is built on the device, so it never asks.
  String? get apiValue => switch (this) {
    DocumentFormat.docx => 'docx',
    DocumentFormat.csv => 'csv',
    DocumentFormat.xlsx => null,
  };
}
