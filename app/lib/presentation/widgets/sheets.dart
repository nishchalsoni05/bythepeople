import 'package:flutter/material.dart';

import 'package:by_the_people/core/theme/tokens.dart';

/// Opens a rounded bottom sheet that rises above the keyboard and scrolls when content is tall.
Future<T?> showAppSheet<T>(BuildContext context, {required String title, String? subtitle, required Widget Function(BuildContext ctx) body}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: C.canvas, borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, 12, 22, 22 + MediaQuery.of(ctx).padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 16),
            Text(title, style: ui(20, w: 650)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle, style: ui(13.5, color: C.inkSoft, h: 1.4)),
            ],
            const SizedBox(height: 16),
            body(ctx),
          ]),
        ),
      ),
    ),
  );
}

/// Rounded text input used inside sheets and forms.
class AppField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int lines;
  final int? maxLength;
  final TextInputType? type;
  final ValueChanged<String>? onChanged;
  final IconData? icon;
  const AppField({super.key, required this.controller, required this.hint, this.lines = 1, this.maxLength, this.type, this.onChanged, this.icon});
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        minLines: lines,
        maxLines: lines + 2,
        maxLength: maxLength,
        keyboardType: type,
        onChanged: onChanged,
        textCapitalization: TextCapitalization.sentences,
        style: ui(15, w: 600),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: ui(14.5, color: C.inkSoft),
          filled: true,
          fillColor: C.surface,
          counterText: '',
          prefixIcon: icon == null ? null : Icon(icon, size: 20, color: C.inkSoft),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(lines > 1 ? 24 : 30), borderSide: BorderSide.none),
        ),
      );
}
