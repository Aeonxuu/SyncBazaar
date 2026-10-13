import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/remote/api_client.dart';
import '../../data/repositories/save_folder_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../models/company.dart';
import '../../services/mac_folder_picker.dart';

class SettingsState {
  const SettingsState({
    this.companies = const [],
    this.autoSync = true,
    this.storeName = '',
    this.storeNameIsVendor = false,
    this.storeNameError,
    this.saveFolders = const {},
  });

  final List<Company> companies;
  final bool autoSync;

  /// The seller's name, printed as the receipt header.
  final String storeName;

  /// Whether editing [storeName] renames the vendor on the server rather than
  /// only this device. Drives what the screen tells the user it is doing.
  final bool storeNameIsVendor;

  /// Why the last rename did not save, or null. Held in state rather than
  /// thrown at a snackbar because the field keeps showing what the user
  /// typed, and they need to know it is not what is stored.
  final String? storeNameError;

  /// The remembered save folder for each export, macOS only. Absent from the
  /// map rather than null-valued when nothing has been chosen yet, so the
  /// screen can tell "not set" apart from "cleared" without a second flag.
  final Map<SaveDocumentKind, String> saveFolders;

  SettingsState copyWith({
    List<Company>? companies,
    bool? autoSync,
    String? storeName,
    bool? storeNameIsVendor,
    String? storeNameError,
    bool clearStoreNameError = false,
    Map<SaveDocumentKind, String>? saveFolders,
  }) {
    return SettingsState(
      companies: companies ?? this.companies,
      autoSync: autoSync ?? this.autoSync,
      storeName: storeName ?? this.storeName,
      storeNameIsVendor: storeNameIsVendor ?? this.storeNameIsVendor,
      storeNameError: clearStoreNameError
          ? null
          : (storeNameError ?? this.storeNameError),
      saveFolders: saveFolders ?? this.saveFolders,
    );
  }
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(
    this._settingsRepository, {
    SaveFolderRepository folderRepository = const SaveFolderRepository(),
    MacFolderPicker folderPicker = const MacFolderPicker(),
  }) : _folderRepository = folderRepository,
       _folderPicker = folderPicker,
       super(const SettingsState());

  final SettingsRepository _settingsRepository;
  final SaveFolderRepository _folderRepository;
  final MacFolderPicker _folderPicker;

  /// Drops back to the default state, synchronously.
  ///
  /// Called right before [load] on a fresh login so the nav rail shows the
  /// generic "SyncBazaar" placeholder for the moment it takes [load] to
  /// resolve, rather than the previous account's store name still sitting in
  /// state.
  void reset() => emit(const SettingsState());

  Future<void> load() async {
    final saveFolders = <SaveDocumentKind, String>{};
    for (final kind in SaveDocumentKind.values) {
      final folder = await _folderRepository.folderFor(kind);
      if (folder != null) {
        saveFolders[kind] = folder;
      }
    }
    emit(
      state.copyWith(
        companies: await _settingsRepository.listCompanies(),
        autoSync: await _settingsRepository.autoSyncEnabled(),
        storeName: await _settingsRepository.storeName(),
        storeNameIsVendor: _settingsRepository.storeNameIsVendor,
        saveFolders: saveFolders,
      ),
    );
  }

  /// Opens a native folder picker for [kind] and remembers the choice, so the
  /// next export of that kind opens its Save As dialog there instead of
  /// wherever it last landed. macOS only -- see [SaveFolderRepository].
  ///
  /// Does nothing if the user backs out of the picker without choosing.
  Future<void> pickSaveFolder(SaveDocumentKind kind) async {
    final path = await _folderPicker.pickDirectory(
      initialDirectory: state.saveFolders[kind],
    );
    if (path == null) {
      return;
    }
    await _folderRepository.setFolderFor(kind, path);
    emit(state.copyWith(saveFolders: {...state.saveFolders, kind: path}));
  }

  /// Forgets the remembered folder for [kind], so the next export's Save As
  /// dialog opens wherever the OS leaves it rather than there.
  Future<void> clearSaveFolder(SaveDocumentKind kind) async {
    await _folderRepository.setFolderFor(kind, null);
    final saveFolders = {...state.saveFolders}..remove(kind);
    emit(state.copyWith(saveFolders: saveFolders));
  }

  /// Saves an existing venue's name, address, contact and rates.
  ///
  /// Payment methods are not a venue's to have any more -- see
  /// `PaymentMethodsCubit` -- so this only ever writes the fields a `Company`
  /// still carries.
  Future<void> saveLocation({required Company company}) async {
    await _settingsRepository.upsertCompany(company);
    await load();
  }

  Future<void> createLocation({
    required String name,
    String address = '',
    String contact = '',
    double incentivePercent = 0,
    double bufferPercent = 0,
  }) async {
    await _settingsRepository.createCompany(
      name: name,
      address: address,
      contact: contact,
      incentivePercent: incentivePercent,
      bufferPercent: bufferPercent,
    );
    await load();
  }

  Future<void> updateAutoSync(bool enabled) async {
    await _settingsRepository.setAutoSync(enabled);
    emit(state.copyWith(autoSync: enabled));
  }

  Future<void> updateStoreName(String name) async {
    try {
      await _settingsRepository.setStoreName(name);
    } on ApiException catch (error) {
      // Re-read too, so the field snaps back to the name that is actually
      // stored rather than sitting on one the server rejected.
      emit(
        state.copyWith(
          storeName: await _settingsRepository.storeName(),
          storeNameError: error.message,
        ),
      );
      return;
    }
    // Re-read rather than echoing the input: the repository substitutes a
    // default for an empty name, and the receipt must print what was stored.
    emit(
      state.copyWith(
        storeName: await _settingsRepository.storeName(),
        clearStoreNameError: true,
      ),
    );
  }
}
