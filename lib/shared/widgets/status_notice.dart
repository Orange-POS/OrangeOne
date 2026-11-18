import 'package:flutter/material.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// A message box on the product screens: info (pale orange, info icon) or
/// [success] (pale green, check icon), with an optional bold [title]. It is
/// as tall as its text, also in a bounded slot such as the success toast.
class StatusNotice extends StatelessWidget {
  const new({
    required this.message,
    this.success = false,
    this.title,
    super.key,
  });
  final String message;
  final bool success;
  final String? title;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFE8F7EF) : const Color(0xFFFFF3E8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.info_outline,
            color: success ? const Color(0xFF078362) : OrangeTheme.dark,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              // As tall as its text: in a bounded slot (the success toast in
              // Product Details' floating slot) a max-size column would
              // stretch the notice to the full screen height.
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF078362),
                      ),
                    ),
                  ),
                Text(
                  message,
                  style: TextStyle(
                    color: success ? const Color(0xFF078362) : OrangeTheme.dark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
