import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/sync_service.dart';

class SyncState {
  const SyncState({this.isSyncing = false, this.lastMessage = 'Offline-ready'});

  final bool isSyncing;
  final String lastMessage;

  SyncState copyWith({bool? isSyncing, String? lastMessage}) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}

class SyncCubit extends Cubit<SyncState> {
  SyncCubit(this._syncService) : super(const SyncState());

  final SyncService _syncService;

  Future<void> syncNow() async {
    emit(state.copyWith(isSyncing: true, lastMessage: 'Syncing...'));
    await _syncService.syncNow();
    emit(state.copyWith(isSyncing: false, lastMessage: 'Synced just now'));
  }
}
