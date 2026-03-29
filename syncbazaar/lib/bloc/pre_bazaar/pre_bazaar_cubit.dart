import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/approvals_repository.dart';
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
  PreBazaarCubit(this._approvalsRepository) : super(const PreBazaarState());

  final ApprovalsRepository _approvalsRepository;

  Future<void> submitAllocation({
    required AppUser user,
    required int eventId,
    required Map<int, int> allocations,
  }) async {
    if (user.isAdminOrOwner) {
      return;
    }
    await _approvalsRepository.add(
      ApprovalRequest(
        id: DateTime.now().millisecondsSinceEpoch,
        type: ApprovalType.stock,
        eventId: eventId,
        requesterId: user.id,
        status: ApprovalStatus.pending,
        detailsJson: jsonEncode({'allocations': allocations}),
        synced: false,
      ),
    );
  }
}
