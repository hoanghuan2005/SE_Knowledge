import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../utils/app_colors.dart';
import '../utils/app_constants.dart';
import 'chat/ai_chat_page.dart';
import 'graph/graph_page.dart';
import 'settings/settings_page.dart';
import 'subjects/subjects_page.dart';
import 'vault/vault_page.dart';

/// Khung ứng dụng desktop: thanh điều hướng dọc bên trái + nội dung bên phải.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const List<_NavItem> _items = [
    _NavItem(Icons.hub_outlined, Icons.hub, 'Đồ thị'),
    _NavItem(Icons.list_alt_outlined, Icons.list_alt, 'Môn học'),
    _NavItem(Icons.folder_open_outlined, Icons.folder, 'Vault'),
    _NavItem(Icons.chat_bubble_outline, Icons.chat_bubble, 'Trợ lý AI'),
    _NavItem(Icons.settings_outlined, Icons.settings, 'Cài đặt'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            index: _index,
            items: _items,
            onChanged: (i) => setState(() => _index = i),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                GraphPage(),
                SubjectsPage(),
                VaultPage(),
                AiChatPage(),
                SettingsPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.icon, this.selectedIcon, this.label);
}

class _Sidebar extends StatelessWidget {
  final int index;
  final List<_NavItem> items;
  final ValueChanged<int> onChanged;

  const _Sidebar({
    required this.index,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_tree, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            AppConstants.appName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: NavigationRail(
              selectedIndex: index,
              onDestinationSelected: onChanged,
              labelType: NavigationRailLabelType.all,
              minWidth: 96,
              groupAlignment: -1,
              destinations: [
                for (final item in items)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: Text(item.label),
                  ),
              ],
            ),
          ),
          const _StatsFooter(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _StatsFooter extends StatelessWidget {
  const _StatsFooter();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final stats = AppState.instance.stats;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              const Divider(),
              const SizedBox(height: 8),
              Text(
                '${stats['subjects'] ?? 0} môn',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${stats['edges'] ?? 0} liên kết',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
