import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the app's own font, and the icon font, into a widget test.
///
/// `flutter test` draws every glyph as a fixed-width block unless a font is
/// loaded, which is far wider than Inter. A layout that fits with blocks fits
/// for real, but one measured against blocks says nothing about where text
/// wraps or whether a dialog is tall enough, and that is exactly what the
/// design checks need to know. Call from `setUpAll`.
Future<void> loadAppFonts() async {
  final inter = FontLoader('Inter');
  for (final name in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final file = File('assets/fonts/Inter-$name.ttf');
    if (file.existsSync()) {
      inter.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
  }
  await inter.load();

  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
    }
  }
}
