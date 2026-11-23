/// The shared widget library.
///
/// Screens import this one file rather than reaching into individual widgets,
/// which keeps the design system discoverable and makes a rename a one line
/// change here.
library;

import 'app_card.dart';
import 'app_text_field.dart';
import 'state_views.dart';
import 'status_badge.dart';

export 'app_bottom_nav.dart';
export 'app_button.dart';
export 'brand_mark.dart';
export 'app_card.dart';
export 'app_scaffold.dart';
export 'app_text_field.dart';
export 'auth_layout.dart';
export 'request_components.dart';
export 'section_header.dart';
export 'skeleton.dart';
export 'state_views.dart';
export 'secure_document_image.dart';
export 'status_badge.dart';

class EmptyState extends EmptyStateView {
  const EmptyState({
    super.key,
    required super.title,
    String? message,
    String? subtitle,
    super.icon,
    super.actionLabel,
    super.onAction,
    super.compact,
  }) : super(message: message ?? subtitle ?? '');
}

class AppLoading extends LoadingView {
  const AppLoading({super.key, super.label, super.message});
}

class StatusChip extends StatusBadge {
  const StatusChip({
    super.key,
    required super.label,
    super.color,
    super.background,
    super.icon,
    super.dense,
  });
}

class DashboardCard extends AppSectionCard {
  const DashboardCard({
    super.key,
    required super.title,
    super.subtitle,
    super.icon,
    super.iconColor,
    super.iconBackground,
    super.trailing,
    super.onTap,
    super.padding,
    super.children,
  });
}

class AppInputField extends AppTextField {
  const AppInputField({
    super.key,
    super.controller,
    super.label,
    super.hint,
    super.helper,
    super.errorText,
    super.prefixIcon,
    super.suffixIcon,
    super.obscureText,
    super.enabled,
    super.readOnly,
    super.keyboardType,
    super.textInputAction,
    super.textCapitalization,
    super.maxLength,
    super.maxLines,
    super.minLines,
    super.onChanged,
    super.onSubmitted,
    super.focusNode,
    super.autofocus,
    super.autofillHints,
    super.inputFormatters,
    super.validator,
    super.isRequired,
    super.textAlign,
    super.contentPadding,
    super.filledBackground,
  });
}
