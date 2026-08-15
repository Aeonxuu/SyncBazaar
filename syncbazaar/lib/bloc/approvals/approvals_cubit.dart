import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/approvals_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../models/approval_request.dart';
import '../../models/stock_proposal.dart';

class ApprovalsCubit extends Cubit<List<ApprovalRequest>> {
  ApprovalsCubit(
    this._approvalsRepository,
    this._eventRepository,
    this._productRepository,
    this._authRepository,
  ) : super(const []);

  final ApprovalsRepository _approvalsRepository;
  final EventRepository _eventRepository;
  final ProductRepository _productRepository;
  final AuthRepository _authRepository;
  final Set<int> _processingRequestIds = <int>{};

  Future<void> loadPending() async {
    emit(await _approvalsRepository.listPending());
  }

  Future<bool> approve(ApprovalRequest request) async {
    if (_processingRequestIds.contains(request.id)) {
      return false;
    }
    _processingRequestIds.add(request.id);

    try {
      if (request.type == ApprovalType.stock) {
        final created = await _createEventFromStockRequest(request);
        if (!created) {
          return false;
        }
      }
      // Recorded only once the bazaar exists. Marking it approved first would
      // take it off the list whether or not the stock was there, leaving
      // nobody to ask again.
      await _approvalsRepository.decide(
        request: request,
        status: ApprovalStatus.approved,
      );
      await loadPending();
      return true;
    } finally {
      _processingRequestIds.remove(request.id);
    }
  }

  Future<void> reject(ApprovalRequest request) async {
    await _approvalsRepository.decide(
      request: request,
      status: ApprovalStatus.rejected,
    );
    // The bazaar the proposal created goes with it. It was only ever a
    // placeholder to hang the request on, and leaving it behind would collect
    // an unapproved event per refusal, each one asked about on every load.
    await _eventRepository.deleteEvent(request.eventId);
    await loadPending();
  }

  Future<bool> _createEventFromStockRequest(ApprovalRequest request) async {
    final proposal = StockProposal.parse(request.detailsJson);

    if (proposal.allocationsByAllocationKey.isNotEmpty) {
      final reserved = await _productRepository.reserveStocksByAllocationKey(
        proposal.allocationsByAllocationKey,
      );
      if (!reserved) {
        return false;
      }
    }

    // The bazaar already exists, created unapproved when the request was
    // raised so the request had something to belong to. Approving promotes
    // that one rather than making a second: creating a new event here would
    // leave the proposal behind as a permanent orphan.
    final createdEvent = await _eventRepository.approveProposal(
      eventId: request.eventId,
      name: proposal.eventName,
      companyId: proposal.companyId,
      startDate: proposal.startDate,
      endDate: proposal.endDate,
      acceptedPaymentMethods: proposal.acceptedPaymentMethods,
      customOtherMethods: proposal.customOtherMethods,
      allocationsByAllocationKey: proposal.allocationsByAllocationKey,
    );

    // The requester plus whoever they rostered. Assigning only the requester
    // threw away the staffing they had already worked out, and left the
    // bazaar looking unstaffed to everyone but them.
    await _authRepository.assignEmployeesToBazaar(
      eventId: createdEvent.id,
      employeeIds: {
        request.requesterId,
        ...proposal.assignedEmployeeIds,
      }.toList(),
    );

    return true;
  }
}
