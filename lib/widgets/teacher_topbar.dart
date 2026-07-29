import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

class TeacherTopbar extends StatelessWidget {
  final String title;
  final IconData? leadingIcon;
  final VoidCallback? onLeading;
  final IconData? trailingIcon;
  final VoidCallback? onBell;

  const TeacherTopbar({super.key, required this.title, this.leadingIcon, this.onLeading, this.trailingIcon = Icons.notifications_none_rounded, this.onBell});

  /// Avatar initial from the teacher's actual name — honorifics are
  /// skipped so "Mr. Lee" shows "L", not "M".
  static String _initialOf(String? name) {
    var n = (name ?? '').trim();
    for (final h in const ['Mr.', 'Ms.', 'Mrs.', 'Mx.', 'Dr.', 'Teacher']) {
      if (n.toLowerCase().startsWith(h.toLowerCase()) && n.length > h.length) {
        n = n.substring(h.length).trim();
        break;
      }
    }
    return n.isEmpty ? 'T' : n.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = context.watch<AuthService>().currentUser;

    return Row(
      children: [
        if (leadingIcon != null)
          IconButton(onPressed: onLeading, icon: Icon(leadingIcon, color: cs.primary))
        else
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.go(AppRoutes.settings),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: cs.primary.withValues(alpha: 0.12),
              child: Text(_initialOf(user?.name), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800)),
            ),
          ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: cs.primary))),
        IconButton(onPressed: onBell, icon: Icon(trailingIcon, color: AiMarkerColors.neutral)),
      ],
    );
  }
}
