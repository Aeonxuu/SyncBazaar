import 'dart:io';
import 'dart:typed_data';

/// The real implementation, for every platform that has `dart:io` -- which in
/// practice here means macOS, since this is only ever reached from
/// `DocumentSaver`/`ReceiptSaver`'s macOS branch.
class MacFileWriter {
  const MacFileWriter();

  Future<void> write(String path, Uint8List bytes) =>
      File(path).writeAsBytes(bytes);
}
