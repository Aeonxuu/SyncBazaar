import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/approvals_repository.dart';
import '../../models/approval_request.dart';

class ApprovalsCubit extends Cubit<List<ApprovalRequest>> {
  ApprovalsCubit(this._approvalsRepository) : super(const []);

  final ApprovalsRepository _approvalsRepository;

  Future<void> loadPending() async {
    emit(await _approvalsRepository.listPending());
  }
}
