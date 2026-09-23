import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/event_repository.dart';

class ReconciliationState {
  const ReconciliationState({this.pendingCount = 0});

  /// Ended bazaars that still have stock sitting at a stall rather than
  /// sold or returned.
  final int pendingCount;
}

/// Backs both the Documentation nav badge and the Inventory Reconciliation
/// tab's own badge — one cubit for both so the two counts can never
/// disagree, the same reason [NotificationsCubit] backs its bell and its
/// screen together.
class ReconciliationCubit extends Cubit<ReconciliationState> {
  ReconciliationCubit(this._events) : super(const ReconciliationState());

  final EventRepository _events;

  Future<void> load() async {
    emit(
      ReconciliationState(
        pendingCount: await _events.bazaarsPendingReconciliation(),
      ),
    );
  }
}
