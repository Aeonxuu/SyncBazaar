import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    if let screenFrame = self.screen?.visibleFrame {
      self.setFrame(screenFrame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    // file_picker's own directory chooser (getDirectoryPath) leaves
    // NSOpenPanel.canCreateDirectories at its default, which does not show a
    // "New Folder" button -- unlike file_picker's own saveFile, which sets
    // the flag explicitly and does show one. This channel is the Settings
    // "Choose folder" picker's own NSOpenPanel with that flag set, so a
    // folder that doesn't exist yet can be created right there. See
    // lib/services/mac_folder_picker.dart for the Dart side.
    let folderPickerChannel = FlutterMethodChannel(
      name: "syncbazaar/folder_picker",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    folderPickerChannel.setMethodCallHandler { call, result in
      guard call.method == "pickDirectory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      let dialog = NSOpenPanel()
      dialog.canChooseDirectories = true
      dialog.canChooseFiles = false
      dialog.canCreateDirectories = true
      dialog.allowsMultipleSelection = false
      dialog.showsHiddenFiles = false
      if let initialDirectory = args?["initialDirectory"] as? String,
        !initialDirectory.isEmpty
      {
        dialog.directoryURL = URL(fileURLWithPath: initialDirectory)
      }
      if dialog.runModal() == .OK, let url = dialog.url {
        result(url.path)
      } else {
        // User dismissed the dialog.
        result(nil)
      }
    }

    super.awakeFromNib()
  }
}
