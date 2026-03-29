import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/settings_repository.dart';
import '../../models/company.dart';

class SettingsState {
  const SettingsState({this.companies = const [], this.autoSync = true});

  final List<Company> companies;
  final bool autoSync;

  SettingsState copyWith({List<Company>? companies, bool? autoSync}) {
    return SettingsState(
      companies: companies ?? this.companies,
      autoSync: autoSync ?? this.autoSync,
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
        autoSync: await _settingsRepository.autoSyncEnabled(),
      ),
    );
  }

  Future<void> updateAutoSync(bool enabled) async {
    await _settingsRepository.setAutoSync(enabled);
    emit(state.copyWith(autoSync: enabled));
  }
}
