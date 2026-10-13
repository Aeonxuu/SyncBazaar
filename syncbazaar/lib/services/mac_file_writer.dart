/// Writes bytes to a path chosen by macOS's Save As dialog.
///
/// Needed because `file_picker`'s `saveFile` throws `UnsupportedError` if
/// handed a `bytes:` argument on macOS -- unlike web and mobile, it only
/// returns the chosen path there and expects the caller to write the file.
/// `dart:io`, which does the actual writing, does not exist for a web build,
/// so this is a conditional export rather than a plain import: a web build
/// compiles against `mac_file_writer_stub.dart` instead, which is never
/// reached at runtime since it is only called from a macOS-only branch.
library;

export 'mac_file_writer_stub.dart'
    if (dart.library.io) 'mac_file_writer_io.dart';
