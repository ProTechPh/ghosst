import 'package:flutter/material.dart';

import 'theme.dart';

enum SocialTab { home, shop, create, inbox, profile }

extension SocialTabPage on SocialTab {
  int get pageIndex => switch (this) {
    SocialTab.home => 0,
    SocialTab.shop => 1,
    SocialTab.inbox => 2,
    SocialTab.profile => 3,
    SocialTab.create => -1,
  };
}

class FiveTabBar extends StatelessWidget {
  const FiveTabBar({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onCreate,
    this.unread = const {},
  });

  final SocialTab selected;
  final ValueChanged<SocialTab> onSelected;
  final VoidCallback onCreate;
  final Map<SocialTab, int> unread;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 64,
        decoration: const BoxDecoration(
          color: Colors.black,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            for (final tab in SocialTab.values)
              Expanded(
                child: _TabItem(tab: tab, bar: this),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.tab, required this.bar});

  final SocialTab tab;
  final FiveTabBar bar;

  @override
  Widget build(BuildContext context) {
    final selected = tab == bar.selected;
    final label = switch (tab) {
      SocialTab.home => 'Home',
      SocialTab.shop => 'Shop',
      SocialTab.create => 'Create',
      SocialTab.inbox => 'Inbox',
      SocialTab.profile => 'Profile',
    };
    final icon = switch (tab) {
      SocialTab.home => selected ? Icons.home : Icons.home_outlined,
      SocialTab.shop => selected ? Icons.storefront : Icons.storefront_outlined,
      SocialTab.create => Icons.add,
      SocialTab.inbox =>
        selected ? Icons.chat_bubble : Icons.chat_bubble_outline,
      SocialTab.profile => selected ? Icons.person : Icons.person_outline,
    };
    final unread = bar.unread[tab] ?? 0;

    return Semantics(
      key: ValueKey('social-tab-semantics-${tab.name}'),
      button: true,
      selected: selected,
      label: tab == SocialTab.create ? 'Create reel' : label,
      child: SizedBox(
        key: ValueKey('social-tab-${tab.name}'),
        width: kTouchMin,
        height: kTouchMin,
        child: InkResponse(
          onTap: tab == SocialTab.create
              ? bar.onCreate
              : () => bar.onSelected(tab),
          radius: 24,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (tab == SocialTab.create)
                Container(
                  width: 36,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.primary,
                        offset: Offset(-5, 0),
                      ),
                      BoxShadow(color: AppColors.cyan, offset: Offset(5, 0)),
                    ],
                  ),
                  child: const Icon(Icons.add, size: 16, color: Colors.black),
                )
              else
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      size: 23,
                      color: selected ? AppColors.primary : AppColors.textDim,
                    ),
                    if (unread > 0)
                      Positioned(
                        top: -5,
                        right: -8,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 16),
                          height: 16,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.black, width: 1.5),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              height: 1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textDim,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SocialAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SocialAppBar({
    super.key,
    required this.title,
    this.titleContent,
    this.actions = const [],
  });

  final String title;
  final Widget? titleContent;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: false,
      title: titleContent ?? Text(title),
      actions: actions,
    );
  }
}
