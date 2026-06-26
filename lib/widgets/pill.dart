import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/theme.dart';

class PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const PillButton({super.key, required this.label, required this.icon, required this.background, required this.foreground, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashFactory: NoSplash.splashFactory,
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999), border: Border.all(color: foreground.withValues(alpha: 0.22))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
