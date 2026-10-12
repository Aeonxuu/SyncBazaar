import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/remote/api_client.dart';
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

  /// Approves [request]. Returns null on success, or the reason it could not
  /// be approved, worded for the owner to read under a
  /// "cannot approve" heading.
  ///
  /// Checked before anything is written: an approval that fails halfway leaves
  /// stock reserved for a bazaar that never went live. Before these checks a
  /// failure surfaced as an uncaught exception and the button appeared to do
  /// nothing.
  Future<String?> approve(ApprovalRequest request) async {
    if (_processingRequestIds.contains(request.id)) {
      return 'This request is already being processed.';
    }
    _processingRequestIds.add(request.id);

    try {
      if (request.type == ApprovalType.stock) {
        final problem = await _blockingProblem(request);
        if (problem != null) {
          return problem;
        }
        if (_authRepository.vendorId != null) {
          // With a server, deciding the request is what allocates the stock
          // and takes it out of master stock, so it goes first: the bazaar is
          // read back only once its stock exists, and the server's own check
          // is the one that counts. A refusal throws before anything is
          // promoted, leaving the proposal to be decided again.
          await _approvalsRepository.decide(
            request: request,
            status: ApprovalStatus.approved,
          );
          await _createEventFromStockRequest(request, reserveLocally: false);
          await _productRepository.refresh();
          await loadPending();
          return null;
        }
        final created = await _createEventFromStockRequest(request);
        if (!created) {
          return 'Stock changed while approving. Reject the proposal and ask for a '
              'revision.';
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
      return null;
    } on ApiException catch (e) {
      return e.isOffline
          ? 'Cannot reach the server. Check the connection and try again.'
          : e.message;
    } finally {
      _processingRequestIds.remove(request.id);
    }
  }

  /// Why this proposal cannot go ahead, or null if nothing stands in its way.
  Future<String?> _blockingProblem(ApprovalRequest request) async {
    final proposal = StockProposal.parse(request.detailsJson);

    final staffProblem = await _unavailableStaff(request, proposal);
    if (staffProblem != null) {
      return staffProblem;
    }

    // Master stock is only known for combinations the catalogue has loaded;
    // an unknown one is left to the reservation step to judge.
    final products = await _productRepository.listProducts();
    final short = <String>{};
    for (final entry in proposal.allocationsByAllocationKey.entries) {
      final have = _productRepository.stockFor(entry.key);
      if (entry.value > 0 && have != null && have < entry.value) {
        final productId = _productRepository.productIdFromKey(entry.key);
        short.addAll(
          products.where((p) => p.id == productId).map((p) => p.name),
        );
      }
    }
    if (short.isNotEmpty) {
      return '${short.join(', ')} '
          '${short.length == 1 ? 'has' : 'have'} not enough stock yet. '
          'Reject the proposal and ask for a revision.';
    }
    return null;
  }

  /// Names anyone on the proposal who already works another bazaar on the same
  /// days.
  Future<String?> _unavailableStaff(
    ApprovalRequest request,
    StockProposal proposal,
  ) async {
    final ids = {request.requesterId, ...proposal.assignedEmployeeIds};
    final users = await _authRepository.listUsers();
    final events = await _eventRepository.listAll();
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final start = day(proposal.startDate);
    final end = day(proposal.endDate);

    final busy = <String>[];
    for (final user in users.where((u) => ids.contains(u.id))) {
      final clash = events.any(
        (e) =>
            e.id != request.eventId &&
            user.assignedEventIdsEffective.contains(e.id) &&
            !day(e.startDate).isAfter(end) &&
            !day(e.endDate).isBefore(start),
      );
      if (clash) {
        busy.add(user.name);
      }
    }
    if (busy.isEmpty) {
      return null;
    }
    return 'Employee: ${busy.join(', ')} '
        '${busy.length == 1 ? 'is' : 'are'} not available on these dates. '
        'Reject the proposal and ask for a revision.';
  }

  /// Names for staff ids, for showing who a proposal assigns.
  ///
  /// Empty when the roster cannot be read; callers fall back to the id rather
  /// than failing to open the request.
  Future<Map<int, String>> employeeNames(Iterable<int> ids) async {
    final wanted = ids.toSet();
    if (wanted.isEmpty) {
      return const {};
    }
    try {
      final users = await _authRepository.listUsers();
      return {
        for (final user in users)
          if (wanted.contains(user.id)) user.id: user.name,
      };
    } on Object {
      return const {};
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

  Future<bool> _createEventFromStockRequest(
    ApprovalRequest request, {
    bool reserveLocally = true,
  }) async {
    final proposal = StockProposal.parse(request.detailsJson);

    if (reserveLocally && proposal.allocationsByAllocationKey.isNotEmpty) {
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
