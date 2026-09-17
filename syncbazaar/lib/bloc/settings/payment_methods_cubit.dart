import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/remote/api_client.dart';
import '../../data/remote/vendor_payment_method_api_mapper.dart';
import '../../data/repositories/vendor_payment_method_repository.dart';

class PaymentMethodsState {
  const PaymentMethodsState({
    this.methods = const [],
    this.catalog = const [],
    this.isRemote = false,
    this.loaded = false,
    this.error,
  });

  final List<VendorPaymentMethod> methods;

  /// The shared catalog, for the add-method suggestion field.
  final List<ModeOfPaymentCatalogEntry> catalog;

  /// Whether there is a server for this list to live on. False only in the
  /// demo build — a real vendor with nothing added yet is still [isRemote].
  final bool isRemote;

  /// Whether the first load has completed, so the screen can tell "loading"
  /// from "loaded, and genuinely empty."
  final bool loaded;

  /// The last action's failure, shown once and cleared on the next attempt.
  final String? error;

  PaymentMethodsState copyWith({
    List<VendorPaymentMethod>? methods,
    List<ModeOfPaymentCatalogEntry>? catalog,
    bool? isRemote,
    bool? loaded,
    String? error,
    bool clearError = false,
  }) {
    return PaymentMethodsState(
      methods: methods ?? this.methods,
      catalog: catalog ?? this.catalog,
      isRemote: isRemote ?? this.isRemote,
      loaded: loaded ?? this.loaded,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives the Payment Methods screen.
///
/// One vendor-wide list now, where there used to be one per venue. Every
/// write reloads both the list and the catalog afterward rather than
/// patching state by hand, the same rule the quick-edit dialog follows: the
/// server is the only thing allowed to say what is actually there.
class PaymentMethodsCubit extends Cubit<PaymentMethodsState> {
  PaymentMethodsCubit(this._repository) : super(const PaymentMethodsState());

  final VendorPaymentMethodRepository _repository;

  Future<void> load() async {
    final methods = await _repository.listMethods();
    final catalog = await _repository.catalog();
    emit(
      state.copyWith(
        methods: methods,
        catalog: catalog,
        isRemote: _repository.isRemote,
        loaded: true,
        clearError: true,
      ),
    );
  }

  /// Adds [name] to the vendor's list. [label] is only used if this turns out
  /// to be a genuinely new catalog entry rather than an existing one being
  /// picked.
  ///
  /// Returns true on success, so the add-method sheet knows to close itself;
  /// a caught failure stays in [PaymentMethodsState.error] instead and the
  /// sheet stays open with what was typed.
  Future<bool> addMethod({required String name, String? label}) async {
    try {
      await _repository.addMethod(name: name, label: label);
      await load();
      return true;
    } on ApiException catch (error) {
      emit(
        state.copyWith(
          error: error.isOffline
              ? 'Cannot reach the server, so $name was not added.'
              : '$name could not be added. ${error.message}',
        ),
      );
      return false;
    }
  }

  Future<void> removeMethod(VendorPaymentMethod method) async {
    try {
      await _repository.removeMethod(method);
      await load();
    } on ApiException catch (error) {
      emit(
        state.copyWith(
          error: error.isOffline
              ? 'Cannot reach the server, so ${method.name} was not removed.'
              : '${method.name} could not be removed. ${error.message}',
        ),
      );
    }
  }

  Future<void> uploadQr({
    required VendorPaymentMethod method,
    required Uint8List bytes,
  }) async {
    try {
      await _repository.uploadQr(method: method, bytes: bytes);
      await load();
    } on ApiException catch (error) {
      emit(
        state.copyWith(
          error: error.isOffline
              ? 'Cannot reach the server, so the QR was not saved.'
              : 'The QR could not be saved. ${error.message}',
        ),
      );
    }
  }
}
