import 'package:flutter/material.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../notifications_screen.dart';
import '../../../widgets/wallet_coin_pill.dart';
import '../more/edit_salon_profile_screen.dart';
import 'more/more_menu_catalog.dart';
import 'more/more_search_engine.dart';
import 'more/widgets/more_search_bar.dart';
import 'more/widgets/more_search_results_view.dart';

class MoreTab extends StatefulWidget {
  final Map<String, dynamic> salonData;
  final Function(Map<String, dynamic>)? onSalonUpdated;
  final String? planName;
  final int? daysRemaining;

  const MoreTab({
    super.key,
    required this.salonData,
    this.onSalonUpdated,
    this.planName,
    this.daysRemaining,
  });

  @override
  State<MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends State<MoreTab> {
  late Map<String, dynamic> salonData;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<MoreSearchResult> _searchResults = [];
  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    salonData = Map.from(widget.salonData);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchQueryChanged(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _searchResults = [];
      } else {
        final allItems = MoreMenuCatalog.getAllSearchableItems(context);
        _searchResults = MoreSearchEngine.search(query: query, items: allItems);
      }
    });
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchResults = [];
      _searchFocusNode.unfocus();
    });
  }

  Widget _buildPlanBadge() {
    final name = widget.planName ?? 'Starter';
    final isGrowth = name.toLowerCase() == 'growth';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isGrowth
            ? Colors.purple.withValues(alpha: 0.1)
            : Colors.blue.withValues(alpha: 0.1),
        border: Border.all(
          color: isGrowth
              ? Colors.purple.withValues(alpha: 0.5)
              : Colors.blue.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        name.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: isGrowth ? Colors.purple : Colors.blue,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: !_isSearching,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSearching) {
          _clearSearch();
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text(
            'More',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28),
          ),
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          centerTitle: false,
          actions: [
            WalletCoinPill(salonId: salonData['id'].toString(), compact: true),
            const SizedBox(width: 16),
          ],
        ),
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(
            top: 4,
            bottom: 100, // padding for bottom nav
          ),
          children: [
            // 1. Search Bar (Sticky at the top of More tab)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: MoreSearchBar(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchQueryChanged,
                onClear: _clearSearch,
              ),
            ),

            // 2. Either search results or normal More screen
            if (_isSearching)
              MoreSearchResultsView(
                results: _searchResults,
                query: _searchController.text.trim(),
                salonData: salonData,
                onSalonUpdated: (updatedData) {
                  setState(() => salonData.addAll(updatedData));
                  widget.onSalonUpdated?.call(updatedData);
                },
                onQuerySelected: (suggestedQuery) {
                  _searchController.text = suggestedQuery;
                  _searchController.selection = TextSelection.fromPosition(
                    TextPosition(offset: suggestedQuery.length),
                  );
                  _onSearchQueryChanged(suggestedQuery);
                },
                onClear: _clearSearch,
              )
            else ...[
              // Top Card (Salon Profile)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: isDark ? 0.2 : 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        child: Container(
                          height: 120,
                          color: theme.dividerColor,
                          child: salonData['cover_photo_url'] != null
                              ? Image.network(
                                  salonData['cover_photo_url'],
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(
                                        Icons.image,
                                        size: 50,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.5),
                                      ),
                                )
                              : Icon(
                                  Icons.image,
                                  size: 50,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          salonData['name']?.toString() ??
                                              'Salon Name',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildPlanBadge(),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    salonData['city']?['name']?.toString() ??
                                        'City not specified',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        EditSalonProfileScreen(
                                          salonData: salonData,
                                        ),
                                  ),
                                ).then((updatedData) {
                                  if (updatedData != null &&
                                      updatedData is Map<String, dynamic>) {
                                    setState(() {
                                      salonData.addAll(updatedData);
                                    });
                                    if (widget.onSalonUpdated != null) {
                                      widget.onSalonUpdated!(updatedData);
                                    }
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppTheme.darkAccentSoft
                                      : AppTheme.lightAccentSoft,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Edit',
                                  style: TextStyle(
                                    color: AppTheme.accentColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Categorized Menu Sections from Single Source of Truth
              ..._buildSections(context),

              const SizedBox(height: 16),

              // Logout Button
              InkWell(
                onTap: () => MoreMenuCatalog.logout(
                  context,
                  action: 'Logging out',
                  salonData: salonData,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: Text(
                    'Log out',
                    style: TextStyle(
                      color: isDark
                          ? AppTheme.darkDanger
                          : AppTheme.lightDanger,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSections(BuildContext context) {
    final sections = MoreMenuCatalog.getMenuSections(context);
    final widgets = <Widget>[];

    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      widgets.add(_buildSectionHeading(section.title));

      for (var j = 0; j < section.items.length; j++) {
        final item = section.items[j];
        if (item.type == MenuItemType.inlineToggle &&
            item.inlineWidgetBuilder != null) {
          widgets.add(
            ListTile(
              leading: Icon(item.icon, color: item.iconColor, size: 26),
              title: Text(
                item.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                ),
              ),
              trailing: item.inlineWidgetBuilder!(context, salonData),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 2,
              ),
            ),
          );
        } else {
          widgets.add(
            _buildOptionTile(
              icon: item.icon,
              iconColor: item.iconColor,
              title: item.title,
              onTap: () => item.onSelect?.call(
                context,
                salonData,
                widget.onSalonUpdated,
              ),
            ),
          );
        }

        if (j < section.items.length - 1) {
          widgets.add(_buildDivider());
        }
      }
    }

    return widgets;
  }

  Widget _buildSectionHeading(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 66,
      color: isDark ? Colors.white24 : Colors.black12,
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 26),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 14,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
    );
  }
}
