import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../bloc/pos/pos_cubit.dart';
import '../../../widgets/confirmation_dialog.dart';

/// Asks before a half-rung sale is thrown away.
///
/// A cart is unsaved work: items counted out, a customer name typed, maybe an
/// amount tendered. Every way out of the POS discards it, and until this
/// existed all of them did so silently — one stray tap on the navigation rail
/// and the cashier started over with a customer standing there.
///
/// One function rather than a check at each exit, because the exits are the
/// problem: the breadcrumb and the rail are in different files, and a guard
/// written twice is a guard that will be added to only one of them the next
/// time an exit appears.
///
/// Returns true when it is safe to proceed — either the cart was empty, so
/// nothing was asked, or the cashier chose to discard.
Future<bool> confirmLeavingSale(BuildContext context) async {
  final state = context.read<PosCubit>().state;
  if (!state.hasSaleInProgress) {
    return true;
  }

  final units = state.cartUnitCount;
  return showConfirmationDialog(
    context: context,
    title: 'Discard this sale?',
    // The count is the point: "you have items" is ignorable, "you have 3
    // items" is checkable against what is on the counter.
    message:
        '$units ${units == 1 ? 'item' : 'items'} in the cart will be cleared. '
        'This cannot be undone.',
    cancelLabel: 'Keep selling',
    confirmLabel: 'Discard',
    // Destructive for the colour -- work is lost and it cannot be recovered --
    // but not the wastebasket glyph, which belongs to deleting a record.
    tone: ConfirmationTone.destructive,
    // Keeping the sale is the emphasised choice. Nobody opened this dialog
    // asking to throw a cart away; they tapped a navigation item and the
    // discard is the side effect. Making the destructive option the filled,
    // focused button would have put the accident one reflex -- or one Enter
    // key -- away, on a screen used at speed with a customer waiting.
    emphasis: ConfirmationEmphasis.cancel,
    icon: Icons.remove_shopping_cart_outlined,
  );
}
