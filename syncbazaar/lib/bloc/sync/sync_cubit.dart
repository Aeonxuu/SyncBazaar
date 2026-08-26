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
    try {
      final outcome = await _syncService.syncNow();
      // The service's own words. "Synced just now" was printed whatever
      // happened, including when nothing had been sent and the server was
      // never reached.
      emit(state.copyWith(isSyncing: false, lastMessage: outcome.message));
    } catch (_) {
      emit(
        state.copyWith(
          isSyncing: false,
          lastMessage: 'Sync failed. Tap to try again.',
        ),
      );
    }
  }
}
