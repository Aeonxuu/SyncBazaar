import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/approvals_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../models/approval_request.dart';
import '../../models/bazaar_event.dart';

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
      await _approvalsRepository.removePendingRequest(request.id);
      await loadPending();
      return true;
    } finally {
      _processingRequestIds.remove(request.id);
    }
  }

  Future<void> reject(ApprovalRequest request) async {
    await _approvalsRepository.removePendingRequest(request.id);
    await loadPending();
  }

  Future<bool> _createEventFromStockRequest(ApprovalRequest request) async {
    final decoded = _safeDecode(request.detailsJson);
    final rawName = decoded?['eventName'];
    final rawCompanyId = decoded?['companyId'];
    final eventName = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : 'Approved Bazaar';
    final companyId = rawCompanyId is int ? rawCompanyId : 1;
    final startDate = _tryParseDate(decoded?['dateStart']) ?? DateTime.now();
    final endDate = _tryParseDate(decoded?['dateEnd']) ?? startDate;

    final acceptedPaymentMethods = _parseStringList(
      decoded?['acceptedPaymentMethods'],
    );
    final customOtherMethods = _parseCustomMethods(
      decoded?['customOtherMethods'],
    );
    final allocationsByAllocationKey = _parseAllocations(
      decoded?['allocationsByAllocationKey'],
    );

    if (allocationsByAllocationKey.isNotEmpty) {
      final reserved = await _productRepository.reserveStocksByAllocationKey(
        allocationsByAllocationKey,
      );
      if (!reserved) {
        return false;
      }
    }

    final createdEvent = await _eventRepository.createEvent(
      name: eventName,
      companyId: companyId,
      startDate: startDate,
      endDate: endDate,
      acceptedPaymentMethods: acceptedPaymentMethods.isEmpty
          ? const ['CASH']
          : acceptedPaymentMethods,
      customOtherMethods: customOtherMethods,
      allocationsByAllocationKey: allocationsByAllocationKey,
    );

    await _authRepository.assignEmployeesToBazaar(
      eventId: createdEvent.id,
      employeeIds: [request.requesterId],
    );

    return true;
  }

  DateTime? _tryParseDate(dynamic raw) {
    if (raw is! String) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  List<String> _parseStringList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    return raw.map((value) => value.toString()).toList();
  }

  List<BazaarPaymentMethod> _parseCustomMethods(dynamic raw) {
    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map>()
        .map(
          (item) => BazaarPaymentMethod(
            name: item['name']?.toString() ?? 'OTHER',
            extraFieldLabel: _parseExtraFieldLabel(item),
          ),
        )
        .toList();
  }

  String? _parseExtraFieldLabel(Map<dynamic, dynamic> item) {
    final raw = item['extraFieldLabel'];
    if (raw is String && raw.trim().isNotEmpty) {
      final trimmed = raw.trim();
      return trimmed.length <= 28 ? trimmed : trimmed.substring(0, 28);
    }

    if (item['requiresEmployeeId'] == true) {
      return 'Employee ID';
    }

    return null;
  }

  Map<String, int> _parseAllocations(dynamic raw) {
    if (raw is! Map) {
      return const {};
    }

    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        value is int ? value : int.tryParse(value.toString()) ?? 0,
      ),
    );
  }

  Map<String, dynamic>? _safeDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
