import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/approvals_repository.dart';
import '../../data/repositories/event_repository.dart';
import '../../models/stock_proposal.dart';
import '../../models/approval_request.dart';
import '../../models/user.dart';

class PreBazaarState {
  const PreBazaarState({
    this.selectedDates = const [],
    this.eventName = '',
    this.companyId,
  });

  final List<DateTime> selectedDates;
  final String eventName;
  final int? companyId;

  PreBazaarState copyWith({
    List<DateTime>? selectedDates,
    String? eventName,
    int? companyId,
  }) {
    return PreBazaarState(
      selectedDates: selectedDates ?? this.selectedDates,
      eventName: eventName ?? this.eventName,
      companyId: companyId ?? this.companyId,
    );
  }
}

class PreBazaarCubit extends Cubit<PreBazaarState> {
  PreBazaarCubit(this._approvalsRepository, this._eventRepository)
    : super(const PreBazaarState());

  final ApprovalsRepository _approvalsRepository;
  final EventRepository _eventRepository;

  /// Raises a stock request for the bazaar described by [detailsJson].
  ///
  /// The bazaar is created first, unapproved. An approval request belongs to
  /// an event on the server, and the event this one proposes does not exist
  /// yet — so it is created as a placeholder that no listing shows and no
  /// stock is committed to, and becomes real only if an owner agrees.
  Future<void> submitAllocation({
    required AppUser user,
    required String detailsJson,
  }) async {
    if (user.isAdminOrOwner) {
      return;
    }

    final proposal = StockProposal.parse(detailsJson);
    final placeholder = await _eventRepository.createEvent(
      name: proposal.eventName,
      companyId: proposal.companyId,
      startDate: proposal.startDate,
      endDate: proposal.endDate,
      acceptedPaymentMethods: proposal.acceptedPaymentMethods,
      customOtherMethods: proposal.customOtherMethods,
      // Deliberately none. The allocations ride in the request instead, and
      // are written as stock only on approval, so a request left unanswered
      // holds no inventory.
      isApproved: false,
    );

    await _approvalsRepository.add(
      ApprovalRequest(
        // Replaced by the server's id where there is one. Only the no-session
        // build keeps this, and only to tell one local request from another.
        id: DateTime.now().millisecondsSinceEpoch,
        type: ApprovalType.stock,
        eventId: placeholder.id,
        requesterId: user.id,
        status: ApprovalStatus.pending,
        detailsJson: detailsJson,
        synced: false,
      ),
    );
  }
}
