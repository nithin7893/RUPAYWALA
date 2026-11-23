import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// The app's single text input.
///
/// Wraps Material's field so validation messages, labels, icons and the
/// brand's focus ring behave identically everywhere.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.autofillHints,
    this.inputFormatters,
    this.validator,
    this.isRequired = false,
    this.textAlign = TextAlign.start,
    this.contentPadding,
    this.filledBackground,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helper;
  final String? errorText;

  final Object? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final int? maxLength;
  final int? maxLines;
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final bool isRequired;
  final TextAlign textAlign;
  final EdgeInsetsGeometry? contentPadding;
  final Color? filledBackground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge!.copyWith(
      color: enabled ? AppColors.textPrimary : AppColors.textHint,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
    );

    final field = TextFormField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      textAlign: textAlign,
      maxLength: maxLength,
      maxLines: obscureText ? 1 : maxLines,
      minLines: obscureText ? null : minLines,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      validator: validator,
      cursorColor: AppColors.primary,
      style: style,
      decoration: InputDecoration(
        labelText: isRequired && label != null ? '$label *' : label,
        hintText: hint,
        helperText: helper,
        errorText: errorText,
        helperMaxLines: 2,
        prefixIcon: switch (prefixIcon) {
          IconData icon => Icon(icon, size: AppIcon.md),
          Widget widget => widget,
          _ => null,
        },
        suffixIcon: suffixIcon,
        contentPadding: contentPadding ?? AppSpacing.field,
        fillColor: filledBackground ??
            (enabled ? AppColors.surface : AppColors.surfaceMuted),
        counterText: '',
      ),
    );

    return Theme(
      data: theme.copyWith(
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: AppColors.primary,
          selectionColor: AppColors.primarySoft,
          selectionHandleColor: AppColors.primary,
        ),
      ),
      child: field,
    );
  }
}

/// Ten digit Indian mobile input with digit-only filtering.
///
/// The backend stores `phone_number` without a country code, so this field
/// deliberately rejects anything that is not a digit and caps the length.
class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    this.errorText,
    this.helperText,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.label = 'Mobile number',
  });

  final TextEditingController controller;
  final String? errorText;
  final String? helperText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CountryPrefix(),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppTextField(
            controller: controller,
            label: label,
            isRequired: true,
            helper: helperText ?? '10-digit number registered with Rupaywala',
            errorText: errorText,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            prefixIcon: Icons.phone_iphone_outlined,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            focusNode: focusNode,
            autofocus: autofocus,
            enabled: enabled,
          ),
        ),
      ],
    );
  }
}

class _CountryPrefix extends StatelessWidget {
  const _CountryPrefix();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🇮🇳', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(width: AppSpacing.xs),
          Text('+91', style: AppText.title),
        ],
      ),
    );
  }
}

/// Six box OTP entry.
///
/// Driven by a hidden [TextField] so paste, autofill and the platform keyboard
/// all work, with the caret suppressed between the boxes.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.controller,
    this.length = 6,
    this.hasError = false,
    this.autofocus = true,
    this.onCompleted,
    this.onChanged,
  });

  final TextEditingController controller;
  final int length;
  final bool hasError;
  final bool autofocus;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {});
    final value = widget.controller.text;
    widget.onChanged?.call(value);
    if (value.length == widget.length) {
      _focusNode.unfocus();
      widget.onCompleted?.call(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    final borderColor = widget.hasError
        ? AppColors.error
        : (value.isNotEmpty ? AppColors.primary : AppColors.border);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: widget.length * 46.0 + (widget.length - 1) * 8.0,
                ),
                child: Row(
                  children: [
                    for (var index = 0; index < widget.length; index++) ...[
                      if (index > 0) const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Container(
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: index < value.length
                                ? AppColors.surface
                                : AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                              color: borderColor,
                              width: index < value.length || widget.hasError
                                  ? 1.6
                                  : 1,
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              index < value.length ? value[index] : '',
                              style: AppText.screenTitle.copyWith(
                                fontSize: 22,
                                color: widget.hasError
                                    ? AppColors.error
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // The real input sits transparently on top of the boxes so taps,
            // paste and the platform OTP autofill all land on it.
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  textCapitalization: TextCapitalization.characters,
                  cursorColor: Colors.transparent,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9]')),
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(
                    color: Colors.transparent,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
