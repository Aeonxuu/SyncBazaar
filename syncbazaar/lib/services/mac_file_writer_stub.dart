import 'dart:typed_data';

/// The web stand-in. Never actually called -- `DocumentSaver`/`ReceiptSaver`
/// only reach [MacFileWriter] from their macOS branch -- but `dart:io` does
/// not exist for a web build, so this file, not `mac_file_writer_io.dart`, is
/// what a web build compiles against. See `mac_file_writer.dart`.
class MacFileWriter {
  const MacFileWriter();

  Future<void> write(String path, Uint8List bytes) {
    throw UnsupportedError('File writing is not available on the web.');
  }
}
