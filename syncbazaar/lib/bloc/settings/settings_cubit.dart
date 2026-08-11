import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/settings_repository.dart';
import '../../models/company.dart';

class SettingsState {
  const SettingsState({
    this.companies = const [],
    this.locationPaymentMethodsByCompanyId = const {},
    this.autoSync = true,
    this.storeName = '',
  });

  final List<Company> companies;
  final Map<int, List<PaymentMethodMeta>> locationPaymentMethodsByCompanyId;
  final bool autoSync;

  /// The seller's name, printed as the receipt header.
  final String storeName;

  SettingsState copyWith({
    List<Company>? companies,
    Map<int, List<PaymentMethodMeta>>? locationPaymentMethodsByCompanyId,
    bool? autoSync,
    String? storeName,
  }) {
    return SettingsState(
      companies: companies ?? this.companies,
      locationPaymentMethodsByCompanyId:
          locationPaymentMethodsByCompanyId ??
          this.locationPaymentMethodsByCompanyId,
      autoSync: autoSync ?? this.autoSync,
      storeName: storeName ?? this.storeName,
    );
  }
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._settingsRepository) : super(const SettingsState());

  final SettingsRepository _settingsRepository;

  Future<void> load() async {
    emit(
      state.copyWith(
        companies: await _settingsRepository.listCompanies(),
        locationPaymentMethodsByCompanyId: await _settingsRepository
            .paymentMethodsByCompanyId(),
        autoSync: await _settingsRepository.autoSyncEnabled(),
        storeName: await _settingsRepository.storeName(),
      ),
    );
  }

  Future<void> saveLocationConfiguration({
    required Company company,
    required List<PaymentMethodMeta> paymentMethods,
  }) async {
    await _settingsRepository.upsertCompanyConfiguration(
      company: company,
      paymentMethods: paymentMethods,
    );
    await load();
  }

  Future<void> createLocation({
    required String name,
    String address = '',
    String contact = '',
    double incentivePercent = 0,
    double bufferPercent = 0,
    String? qrImagePath,
    List<PaymentMethodMeta>? paymentMethods,
  }) async {
    final created = await _settingsRepository.createCompany(
      name: name,
      address: address,
      contact: contact,
      incentivePercent: incentivePercent,
      bufferPercent: bufferPercent,
      qrImagePath: qrImagePath,
    );
    await _settingsRepository.upsertCompanyConfiguration(
      company: created,
      paymentMethods: paymentMethods ?? const [PaymentMethodMeta(name: 'CASH')],
    );
    await load();
  }

  Future<void> updateAutoSync(bool enabled) async {
    await _settingsRepository.setAutoSync(enabled);
    emit(state.copyWith(autoSync: enabled));
  }

  Future<void> updateStoreName(String name) async {
    await _settingsRepository.setStoreName(name);
    // Re-read rather than echoing the input: the repository substitutes a
    // default for an empty name, and the receipt must print what was stored.
    emit(state.copyWith(storeName: await _settingsRepository.storeName()));
  }
}
