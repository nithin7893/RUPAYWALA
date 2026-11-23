import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import 'app_scaffold.dart';

/// Scrollable body for the sign-in, OTP and password forms.
///
/// Auth screens used to be fixed-height columns with a `Spacer`. That overflows
/// as soon as the keyboard opens or the user has large accessibility text. This
/// keeps the primary action at the bottom of a full-height viewport but lets the
/// whole form scroll when content no longer fits.
class AuthScrollBody extends StatelessWidget {
  const AuthScrollBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBody(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Padding(padding: padding, child: child),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
