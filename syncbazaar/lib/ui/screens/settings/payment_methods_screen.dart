import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../bloc/settings/payment_methods_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../data/remote/vendor_payment_method_api_mapper.dart';
import '../../../models/user.dart';
import '../../../services/qr_crop_service.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/custom_card.dart';

/// The vendor's own payment methods: what the POS offers, and the QR each
/// one shows at checkout.
///
/// Used to be chosen per venue, with the same wallet re-added on every one.
/// One vendor has one list now, shared by every venue and every bazaar it
/// holds — this screen is that list's only home.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = widget.user.isAdminOrOwner;

    if (!canManage) {
      return const Center(child: Text('Access denied'));
    }

    return BlocConsumer<PaymentMethodsCubit, PaymentMethodsState>(
      listener: (context, state) {
        final error = state.error;
        if (error == null) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 3400),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            content: Text(error),
          ),
        );
      },
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payment Methods',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'What the till offers, and the QR each one shows '
                          'at checkout',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (state.isRemote)
                    ElevatedButton.icon(
                      onPressed: () => _openAddMethod(context),
                      icon: const Icon(Icons.add, size: 18),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      label: const Text('Add method'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(child: _body(context, state)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, PaymentMethodsState state) {
    if (!state.isRemote) {
      // The demo build has no vendor to hold a list for — there is nothing
      // wrong here, just nothing to manage until there is a server.
      return const Center(
        child: Text(
          'Payment methods are managed on the server, once you are signed '
          'in.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black45),
        ),
      );
    }
    if (!state.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.methods.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 38,
              color: Colors.black26,
            ),
            const SizedBox(height: 10),
            const Text(
              'No methods yet, add one',
              style: TextStyle(color: Colors.black45),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _openAddMethod(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add method'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: state.methods.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _MethodRow(method: state.methods[index]),
    );
  }

  Future<void> _openAddMethod(BuildContext context) async {
    final cubit = context.read<PaymentMethodsCubit>();
    await showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: _AddMethodDialog(existing: cubit.state.methods),
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({required this.method});

  final VendorPaymentMethod method;

  bool get _locked => method.name == 'CASH';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomCard(
      child: Row(
        children: [
          _QrThumbnail(method: method),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  method.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (method.extraFieldLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Asks for: ${method.extraFieldLabel}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!_locked)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.black45,
              tooltip: 'Remove $method.name',
              onPressed: () => _confirmRemove(context),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final cubit = context.read<PaymentMethodsCubit>();
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Remove ${method.name}?',
      message:
          'The till will no longer offer ${method.name}. This does not '
          'affect any sale already rung up against it.',
      confirmLabel: 'Remove',
      tone: ConfirmationTone.destructive,
    );
    if (!confirmed) {
      return;
    }
    await cubit.removeMethod(method);
  }
}

/// The QR itself, tap to upload or replace. A network image, never bytes —
/// the server is this QR's only copy, so there is nothing to show until it
/// has confirmed one.
class _QrThumbnail extends StatefulWidget {
  const _QrThumbnail({required this.method});

  final VendorPaymentMethod method;

  @override
  State<_QrThumbnail> createState() => _QrThumbnailState();
}

class _QrThumbnailState extends State<_QrThumbnail> {
  bool _busy = false;

  Future<void> _pick(BuildContext context) async {
    if (_busy) {
      return;
    }
    // Captured before the first await, and used only through these from here
    // on — the established rule in this codebase for a BuildContext that has
    // to survive an await, rather than calling back through `context` itself
    // once it might already be gone.
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<PaymentMethodsCubit>();
    final picker = ImagePicker();
    // Capped in pixels but not re-encoded: `imageQuality` is a lossy JPEG
    // pass, harmless on a product photo and a real risk on something that
    // has to stay machine-readable.
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
    );
    if (file == null) {
      return;
    }
    setState(() => _busy = true);
    // Bytes, never the path: on web `XFile.path` is a blob URL no decoder can
    // open, and dart:io does not exist there at all.
    final source = await file.readAsBytes();
    final result = await const QrCropService().cropToQr(source);
    if (!mounted) {
      return;
    }
    if (!result.found) {
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(result.failureReason ?? 'No QR code found.')),
      );
      return;
    }
    await cubit.uploadQr(method: widget.method, bytes: result.bytes!);
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.method.qrImageUrl;
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: _busy
            ? const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : url == null
            ? const Icon(
                Icons.qr_code_2_outlined,
                size: 22,
                color: Colors.black38,
              )
            : Padding(
                padding: const EdgeInsets.all(4),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.qr_code_2_outlined,
                    size: 22,
                    color: Colors.black38,
                  ),
                ),
              ),
      ),
    );
  }
}

/// Add a method. Typing filters the shared catalog for a name already there
/// — reusing an existing entry rather than minting a duplicate is the whole
/// point, so a matched suggestion always wins over creating new.
class _AddMethodDialog extends StatefulWidget {
  const _AddMethodDialog({required this.existing});

  /// The vendor's own current list, so a name already accepted here is
  /// refused before a request goes out rather than by a server error.
  final List<VendorPaymentMethod> existing;

  @override
  State<_AddMethodDialog> createState() => _AddMethodDialogState();
}

class _AddMethodDialogState extends State<_AddMethodDialog> {
  final _name = TextEditingController();
  final _label = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    super.dispose();
  }

  static String _squash(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  List<ModeOfPaymentCatalogEntry> _suggestions(PaymentMethodsState state) {
    final typed = _squash(_name.text);
    if (typed.isEmpty) {
      return const [];
    }
    final already = widget.existing.map((m) => _squash(m.name)).toSet();
    return state.catalog
        .where(
          (entry) =>
              _squash(entry.name).contains(typed) &&
              !already.contains(_squash(entry.name)),
        )
        .toList();
  }

  /// The catalog entry the typed text names exactly, if any — this is what
  /// decides whether Save reuses a row or creates one.
  ModeOfPaymentCatalogEntry? _exactMatch(PaymentMethodsState state) {
    final typed = _squash(_name.text);
    if (typed.isEmpty) {
      return null;
    }
    for (final entry in state.catalog) {
      if (_squash(entry.name) == typed) {
        return entry;
      }
    }
    return null;
  }

  void _pick(ModeOfPaymentCatalogEntry entry) {
    setState(() {
      _name.text = entry.name;
      _name.selection = TextSelection.collapsed(offset: _name.text.length);
      _error = null;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the method a name.');
      return;
    }
    final squashed = _squash(name);
    if (widget.existing.any((m) => _squash(m.name) == squashed)) {
      setState(() => _error = '$name is already accepted.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final cubit = context.read<PaymentMethodsCubit>();
    final ok = await cubit.addMethod(
      name: name,
      label: _label.text.trim().isEmpty ? null : _label.text.trim(),
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = false;
      _error = cubit.state.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PaymentMethodsCubit, PaymentMethodsState>(
      builder: (context, state) {
        final suggestions = _suggestions(state);
        final matched = _exactMatch(state);
        return AlertDialog(
          title: const Text('Add a payment method'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: const InputDecoration(
                    labelText: 'Method name',
                    hintText: 'e.g. GCash',
                  ),
                ),
                if (suggestions.isNotEmpty && matched == null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in suggestions.take(5))
                        ActionChip(
                          label: Text(entry.name),
                          onPressed: () => _pick(entry),
                        ),
                    ],
                  ),
                ],
                if (matched != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    matched.extraFieldLabel == null
                        ? 'Reusing the existing "${matched.name}" method.'
                        : 'Reusing the existing "${matched.name}" method. '
                              'Asks for: ${matched.extraFieldLabel}.',
                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _label,
                    decoration: const InputDecoration(
                      labelText: 'Reference field (optional)',
                      hintText: 'e.g. Reference Number',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Shown at checkout if the customer needs to give a '
                    'reference for this method. Leave blank if not.',
                    style: TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}
