import 'package:flutter/services.dart';

/// A macOS folder picker with "New Folder" enabled.
///
/// Not `file_picker`'s own `getDirectoryPath`: its NSOpenPanel leaves
/// `canCreateDirectories` at whatever the OS defaults to, which does not show
/// the button, unlike `file_picker`'s own save dialog, which sets the flag
/// explicitly. Routed instead through a small native channel this app owns --
/// see `macos/Runner/MainFlutterWindow.swift` -- so a folder that doesn't
/// exist yet can be created right there, matching the Save As dialog.
class MacFolderPicker {
  const MacFolderPicker();

  static const _channel = MethodChannel('syncbazaar/folder_picker');

  /// Returns the chosen path, or null if the dialog was dismissed.
  Future<String?> pickDirectory({String? initialDirectory}) {
    return _channel.invokeMethod<String>('pickDirectory', {
      'initialDirectory': initialDirectory,
    });
  }
}
