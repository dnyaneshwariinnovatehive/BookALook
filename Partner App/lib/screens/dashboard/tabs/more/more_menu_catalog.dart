import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/main.dart';
import 'package:partner_app/screens/phone_screen.dart';
import 'package:partner_app/screens/dashboard/salon_selection_screen.dart';
import 'package:partner_app/services/api_service.dart';
import 'package:partner_app/screens/notifications_screen.dart';
import 'package:partner_app/screens/help_support_screen.dart';
import 'package:partner_app/screens/dashboard/more/subscription_billing_screen.dart';
import 'package:partner_app/screens/dashboard/more/wallet_screen.dart';
import 'package:partner_app/screens/dashboard/more/salon_location_screen.dart';
import 'package:partner_app/screens/dashboard/more/salon_qr_screen.dart';
import 'package:partner_app/screens/dashboard/more/salon_reviews_screen.dart';
import 'package:partner_app/screens/dashboard/more/insights_screen.dart';
import 'package:partner_app/screens/dashboard/more/payroll_screen.dart';
import 'package:partner_app/screens/dashboard/more/salon_payouts_screen.dart';
import 'package:partner_app/screens/dashboard/more/edit_salon_profile_screen.dart';
import 'package:partner_app/screens/dashboard/more/automated_messaging_screen.dart';
import 'package:partner_app/screens/dashboard/more/salon_offers_screen.dart';
import 'package:partner_app/screens/dashboard/more/upgrade_plan_screen.dart';
import 'package:partner_app/screens/dashboard/more/marketing_screen.dart';
import 'package:partner_app/screens/dashboard/more/create_edit_salon_offer_screen.dart';
import 'package:partner_app/screens/dashboard/tabs/settings/salon_timings_screen.dart';
import 'package:partner_app/screens/walk_in_history_screen.dart';
import 'package:partner_app/legal/legal_document_screen.dart';
import 'package:partner_app/services/wallet_balance.dart';
import 'package:partner_app/services/push_notification_service.dart';
import 'package:partner_app/widgets/logout_confirmation_dialog.dart';
import 'package:partner_app/widgets/push_notification_toggle.dart';

enum MenuItemType { screen, action, inlineToggle }

/// A structured, immutable definition for any item or feature accessible
/// in the More tab or its nested settings.
class MoreMenuItem {
  final String id;
  final String title;
  final String category;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final List<String> keywords;
  final MenuItemType type;
  final Future<void> Function(
    BuildContext context,
    Map<String, dynamic> salonData,
    Function(Map<String, dynamic>)? onSalonUpdated,
  )?
  onSelect;
  final Widget Function(BuildContext context, Map<String, dynamic> salonData)?
  inlineWidgetBuilder;

  const MoreMenuItem({
    required this.id,
    required this.title,
    required this.category,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.keywords,
    this.type = MenuItemType.screen,
    this.onSelect,
    this.inlineWidgetBuilder,
  });
}

/// A grouped section of More tab menu items.
class MoreMenuSection {
  final String title;
  final List<MoreMenuItem> items;

  const MoreMenuSection({required this.title, required this.items});
}

/// Single Source of Truth for BookALook Partner App More Tab.
///
/// Both normal menu rendering and advanced search derive from this shared
/// catalog to prevent drift between what is shown and what is searchable.
class MoreMenuCatalog {
  /// Handles the logout and account/salon switch confirmations.
  static Future<void> logout(
    BuildContext context, {
    required String action,
    required Map<String, dynamic> salonData,
  }) async {
    String? adminName;
    String? adminPhone;
    if (salonData['admin'] is Map) {
      adminName = salonData['admin']['name']?.toString();
      adminPhone = salonData['admin']['phone']?.toString();
    }

    final confirmed = await LogoutConfirmationDialog.show(
      context,
      name: adminName,
      phone: adminPhone,
      secondaryNote: 'Your bookings and salon data stay saved to your account.',
    );

    if (confirmed != true) return;

    await PushNotificationService().unregisterDevice();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const PhoneScreen()),
        (route) => false,
      );
    }
  }

  // -------------------------------------------------------------
  // Standard Categorized Sections (For Normal More Tab Rendering)
  // -------------------------------------------------------------

  static List<MoreMenuSection> getMenuSections(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return [
      MoreMenuSection(
        title: 'Salon management',
        items: [
          MoreMenuItem(
            id: 'switch_salon',
            title: 'Switch Salon',
            category: 'Salon management',
            subtitle: 'Switch to another salon branch or location',
            icon: Icons.storefront,
            iconColor: Colors.purple,
            type: MenuItemType.action,
            keywords: const [
              'switch salon',
              'change salon',
              'other branch',
              'select salon',
              'multi salon',
              'branch',
              'switch',
            ],
            onSelect: (ctx, salonData, _) async {
              final prefs = await SharedPreferences.getInstance();
              final authStateStr = prefs.getString('auth_state');
              List<dynamic> salons = [];
              if (authStateStr != null) {
                try {
                  final authState = jsonDecode(authStateStr);
                  if (authState['salons'] is List) {
                    salons = List<dynamic>.from(authState['salons']);
                  }
                } catch (_) {}
              }

              // Also try refreshing in background if salons list is empty
              if (salons.isEmpty) {
                final fetched = await ApiService.getMySalons();
                if (fetched != null && fetched.isNotEmpty) {
                  salons = fetched;
                }
              }

              if (ctx.mounted) {
                Navigator.of(ctx, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => SalonSelectionScreen(salons: salons),
                  ),
                  (route) => false,
                );
              }
            },
          ),
          MoreMenuItem(
            id: 'salon_location',
            title: 'Salon Location',
            category: 'Salon management',
            subtitle: 'Pin map coordinates, address & Google Maps link',
            icon: Icons.place_outlined,
            iconColor: AppTheme.accentColor,
            keywords: const [
              'location',
              'salon location',
              'map',
              'gps',
              'address',
              'pin',
              'directions',
              'coordinates',
              'google maps',
              'where is salon',
              'find salon',
              'nearby search',
            ],
            onSelect: (ctx, salonData, _) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) =>
                      SalonLocationScreen(salonId: salonData['id'].toString()),
                ),
              );
            },
          ),
          MoreMenuItem(
            id: 'salon_timings',
            title: 'Change Salon Timings',
            category: 'Salon management',
            subtitle: 'Working hours, opening & closing shifts, weekly off',
            icon: Icons.access_time,
            iconColor: isDark ? AppTheme.darkWarning : AppTheme.lightWarning,
            keywords: const [
              'timings',
              'change salon timings',
              'working hours',
              'opening hours',
              'closing hours',
              'schedule',
              'open',
              'close',
              'days',
              'holiday',
              'shifts',
              'slots',
              'operational hours',
              'business hours',
              'weekly off',
              'time',
              'availability',
            ],
            onSelect: (ctx, salonData, _) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) =>
                      SalonTimingsScreen(salonId: salonData['id'].toString()),
                ),
              );
            },
          ),
          MoreMenuItem(
            id: 'salon_qr',
            title: 'Your QR Code',
            category: 'Salon management',
            subtitle: 'Download & print salon booking QR standee poster',
            icon: Icons.qr_code_2,
            iconColor: AppTheme.accentColor,
            keywords: const [
              'qr code',
              'your qr code',
              'qr',
              'barcode',
              'standee',
              'poster',
              'scan',
              'print qr',
              'share qr',
              'customer booking qr',
              'self booking',
              'check-in qr',
            ],
            onSelect: (ctx, salonData, _) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) =>
                      SalonQrScreen(salonId: salonData['id'].toString()),
                ),
              );
            },
          ),
          MoreMenuItem(
            id: 'salon_offers',
            title: 'Offers & Discounts',
            category: 'Salon management',
            subtitle: 'Promo codes, first-time customer & percentage discounts',
            icon: Icons.local_offer_outlined,
            iconColor: const Color(0xFF9850F1),
            keywords: const [
              'offers',
              'discounts',
              'offers & discounts',
              'promotions',
              'deals',
              'coupons',
              'promo code',
              'first time offer',
              'festival discount',
              'sale',
              'percentage off',
              'flat discount',
              'voucher',
              'savings',
            ],
            onSelect: (ctx, salonData, _) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) =>
                      SalonOffersScreen(salonId: salonData['id'].toString()),
                ),
              );
            },
          ),
          MoreMenuItem(
            id: 'walk_in_history',
            title: 'Walk-in History',
            category: 'Salon management',
            subtitle: 'Offline bookings, walk-in customer records & revenue receipts',
            icon: Icons.history_edu_outlined,
            iconColor: const Color(0xFF0284C7),
            keywords: const [
              'walk in',
              'walk-in',
              'walk in history',
              'offline customers',
              'counter booking',
              'walk-in clients',
              'offline history',
              'receipts',
              'walk in report',
            ],
            onSelect: (ctx, salonData, _) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => WalkInHistoryScreen(
                    salonId: salonData['id'].toString(),
                    salonName: salonData['name']?.toString(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      MoreMenuSection(
        title: 'Insights & communication',
        items: [
          MoreMenuItem(
            id: 'business_insights',
            title: 'Business Insights',
            category: 'Insights & communication',
            subtitle: 'Revenue charts, sales analytics & repeat clients',
            icon: Icons.insights_outlined,
            iconColor: Colors.deepPurple,
            keywords: const [
              'insights',
              'business insights',
              'analytics',
              'reports',
              'revenue',
              'statistics',
              'sales',
              'metrics',
              'growth',
              'performance',
              'repeat customers',
              'busy hours',
              'earnings graph',
              'income',
            ],
            onSelect: (ctx, salonData, _) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) =>
                      InsightsScreen(salonId: salonData['id'].toString()),
                ),
              );
            },
          ),
          MoreMenuItem(
            id: 'customer_reviews',
            title: 'Customer Reviews',
            category: 'Insights & communication',
            subtitle: 'Star ratings, customer comments & client feedback',
            icon: Icons.star_outline_rounded,
            iconColor: const Color(0xFFF5A623),
            keywords: const [
              'reviews',
              'customer reviews',
              'ratings',
              'feedback',
              'stars',
              'testimonials',
              'customer complaints',
              'comments',
              'customer score',
              'rating',
            ],
            onSelect: (ctx, salonData, _) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) =>
                      SalonReviewsScreen(salonId: salonData['id'].toString()),
                ),
              );
            },
          ),
          MoreMenuItem(
            id: 'notifications',
            title: 'Notifications',
            category: 'Insights & communication',
            subtitle: 'Booking alerts, admin warnings & platform updates',
            icon: Icons.notifications_outlined,
            iconColor: isDark ? AppTheme.darkWarning : AppTheme.lightWarning,
            keywords: const [
              'notifications',
              'alerts',
              'inbox',
              'messages',
              'updates',
              'warnings',
              'activity',
              'notice',
            ],
            onSelect: (ctx, _, __) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
          MoreMenuItem(
            id: 'automated_messaging',
            title: 'Automated Messaging',
            category: 'Insights & communication',
            subtitle: 'WhatsApp 25-day reminders & birthday greetings',
            icon: Icons.mark_chat_read,
            iconColor: Colors.green,
            keywords: const [
              'automated messaging',
              'whatsapp',
              'messaging',
              'reminder',
              'birthday reminder',
              '25 day reminder',
              'auto message',
              'retention',
              'chat',
              'sms',
              'customer outreach',
              'client follow up',
            ],
            onSelect: (ctx, salonData, _) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => AutomatedMessagingScreen(
                    salonId: salonData['id'].toString(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      MoreMenuSection(
        title: 'Payments & payroll',
        items: [
          MoreMenuItem(
            id: 'my_wallet',
            title: 'My Wallet',
            category: 'Payments & payroll',
            subtitle: 'Reward coins, points balance & plan redemptions',
            icon: Icons.account_balance_wallet,
            iconColor: Colors.amber,
            keywords: const [
              'wallet',
              'my wallet',
              'coins',
              'reward coins',
              'rewards',
              'cashback',
              'balance',
              'redeem',
              'points',
              'money',
              'funds',
              'loyalty',
            ],
            onSelect: (ctx, salonData, _) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) =>
                      WalletScreen(salonId: salonData['id'].toString()),
                ),
              );
              await WalletBalance.refresh(salonData['id'].toString());
            },
          ),
          MoreMenuItem(
            id: 'salon_payouts',
            title: 'Payouts from BookALook',
            category: 'Payments & payroll',
            subtitle: 'Weekly bank transfers, settlement UTR & commissions',
            icon: Icons.account_balance,
            iconColor: Colors.blueGrey,
            keywords: const [
              'payouts',
              'payouts from bookalook',
              'settlement',
              'bank transfer',
              'bank account',
              'direct deposit',
              'commission deducted',
              'weekly payout',
              'money',
              'finance',
              'payment from bookalook',
              'earnings withdrawal',
              'net earnings',
            ],
            onSelect: (ctx, salonData, _) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) =>
                      SalonPayoutsScreen(salonId: salonData['id'].toString()),
                ),
              );
            },
          ),
          MoreMenuItem(
            id: 'staff_payroll',
            title: 'Staff Payroll',
            category: 'Payments & payroll',
            subtitle: 'Base salaries, commissions, leave deductions & payslips',
            icon: Icons.groups,
            iconColor: Colors.indigo,
            keywords: const [
              'staff payroll',
              'payroll',
              'salary',
              'staff salary',
              'payslip',
              'wages',
              'commissions',
              'staff pay',
              'team compensation',
              'deductions',
              'attendance deduction',
              'monthly pay',
              'staff',
              'employee salary',
            ],
            onSelect: (ctx, salonData, _) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) =>
                      PayrollScreen(salonId: salonData['id'].toString()),
                ),
              );
            },
          ),
          MoreMenuItem(
            id: 'subscription_billing',
            title: 'Subscription & Billing',
            category: 'Payments & payroll',
            subtitle: 'Current plan validity, payment requests & invoices',
            icon: Icons.receipt_long,
            iconColor: Colors.teal,
            keywords: const [
              'subscription',
              'billing',
              'subscription & billing',
              'plan',
              'starter plan',
              'growth plan',
              'membership',
              'invoice',
              'renew',
              'upgrade',
              'payment proof',
              'pricing',
              'charge',
              'validity',
              'expiry',
            ],
            onSelect: (ctx, salonData, _) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => SubscriptionBillingScreen(
                    salonId: salonData['id'].toString(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      MoreMenuSection(
        title: 'Account & app settings',
        items: [
          MoreMenuItem(
            id: 'switch_account',
            title: 'Switch Account',
            category: 'Account & app settings',
            subtitle: 'Sign in with a different partner phone number',
            icon: Icons.manage_accounts,
            iconColor: isDark ? AppTheme.darkInfo : AppTheme.lightInfo,
            type: MenuItemType.action,
            keywords: const [
              'switch account',
              'change account',
              'different user',
              'sign in with other number',
              'relogin',
              'account',
            ],
            onSelect: (ctx, salonData, _) =>
                logout(ctx, action: 'Switch Account', salonData: salonData),
          ),
          MoreMenuItem(
            id: 'push_notifications',
            title: 'Push Notifications',
            category: 'Account & app settings',
            subtitle: 'Device push alerts for appointments & reminders',
            icon: Icons.notifications_active_outlined,
            iconColor: isDark ? AppTheme.darkWarning : AppTheme.lightWarning,
            type: MenuItemType.inlineToggle,
            keywords: const [
              'push notifications',
              'push alert',
              'fcm',
              'notification sound',
              'toggle notifications',
              'device notification',
            ],
            inlineWidgetBuilder: (ctx, _) =>
                const PushNotificationToggle(compact: true),
          ),
          MoreMenuItem(
            id: 'dark_mode',
            title: 'Dark Mode',
            category: 'Account & app settings',
            subtitle: 'Toggle dark or light visual appearance',
            icon: Icons.dark_mode_outlined,
            iconColor: Colors.amber,
            type: MenuItemType.inlineToggle,
            keywords: const [
              'dark mode',
              'light mode',
              'theme',
              'night mode',
              'appearance',
              'colors',
              'display',
            ],
            inlineWidgetBuilder: (ctx, _) {
              return ValueListenableBuilder<ThemeMode>(
                valueListenable: themeNotifier,
                builder: (context, currentMode, _) {
                  final dark = currentMode == ThemeMode.dark;
                  return Switch.adaptive(
                    value: dark,
                    activeTrackColor: AppTheme.accentColor,
                    onChanged: (val) async {
                      themeNotifier.value = val
                          ? ThemeMode.dark
                          : ThemeMode.light;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('isDarkMode', val);
                    },
                  );
                },
              );
            },
          ),
          MoreMenuItem(
            id: 'help_support',
            title: 'Help & Support',
            category: 'Account & app settings',
            subtitle: 'Contact BookALook support, FAQs & legal documentation',
            icon: Icons.help_outline,
            iconColor: isDark ? AppTheme.darkSuccess : AppTheme.lightSuccess,
            keywords: const [
              'help',
              'support',
              'help & support',
              'contact',
              'call',
              'email',
              'whatsapp support',
              'terms',
              'privacy',
              'legal',
              'faq',
              'cancellation policy',
              'refund policy',
              'about',
            ],
            onSelect: (ctx, _, __) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
              );
            },
          ),
        ],
      ),
    ];
  }

  // -------------------------------------------------------------
  // Complete Searchable Catalog (Primary Items + Verified Nested Destinations)
  // -------------------------------------------------------------

  static List<MoreMenuItem> getAllSearchableItems(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sections = getMenuSections(context);
    final results = <MoreMenuItem>[];

    // 1. Top Salon Profile Card
    results.add(
      MoreMenuItem(
        id: 'edit_salon_profile',
        title: 'Edit Salon Profile',
        category: 'Salon management',
        subtitle:
            'Name, address, contact numbers, cover photo & advance booking fees',
        icon: Icons.storefront_outlined,
        iconColor: AppTheme.accentColor,
        keywords: const [
          'edit profile',
          'profile',
          'salon profile',
          'salon name',
          'cover photo',
          'address',
          'phone',
          'advance payment',
          'advance percentage',
          'gender',
          'about salon',
          'deactivate salon',
          'contact details',
          'salon details',
        ],
        onSelect: (ctx, salonData, onSalonUpdated) async {
          final updatedData = await Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => EditSalonProfileScreen(salonData: salonData),
            ),
          );
          if (updatedData != null && updatedData is Map<String, dynamic>) {
            onSalonUpdated?.call(updatedData);
          }
        },
      ),
    );

    // 2. Add all items from standard sections
    for (final section in sections) {
      results.addAll(section.items);
    }

    // 3. Log out action
    results.add(
      MoreMenuItem(
        id: 'logout',
        title: 'Log out',
        category: 'Account & app settings',
        subtitle: 'Sign out from this device',
        icon: Icons.logout,
        iconColor: isDark ? AppTheme.darkDanger : AppTheme.lightDanger,
        type: MenuItemType.action,
        keywords: const [
          'log out',
          'logout',
          'sign out',
          'exit',
          'leave account',
        ],
        onSelect: (ctx, salonData, _) =>
            logout(ctx, action: 'Logging out', salonData: salonData),
      ),
    );

    // 4. Verified Nested Destinations (Instagram Settings Deep-Search)

    // A. Upgrade / Renew Plan
    results.add(
      MoreMenuItem(
        id: 'upgrade_plan',
        title: 'Upgrade / Renew Plan',
        category: 'Payments & payroll',
        subtitle:
            'Starter & Growth tiers, plan features & payment proof upload',
        icon: Icons.upgrade_rounded,
        iconColor: Colors.deepPurpleAccent,
        keywords: const [
          'upgrade plan',
          'renew subscription',
          'buy plan',
          'change plan',
          'pay subscription',
          'pricing table',
          'plans',
          'pricing',
          'growth plan',
          'starter plan',
          'renew plan',
        ],
        onSelect: (ctx, salonData, _) async {
          await Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) =>
                  UpgradePlanScreen(salonId: salonData['id'].toString()),
            ),
          );
        },
      ),
    );

    // B. Marketing & Promotional Campaigns
    results.add(
      MoreMenuItem(
        id: 'marketing_campaigns',
        title: 'Marketing & Campaigns',
        category: 'Insights & communication',
        subtitle: 'Create promotional SMS & WhatsApp campaigns for clients',
        icon: Icons.campaign_outlined,
        iconColor: Colors.pinkAccent,
        keywords: const [
          'marketing',
          'campaigns',
          'marketing & campaigns',
          'sms campaign',
          'whatsapp campaign',
          'broadcast',
          'client blast',
          'promotions',
          'send message',
        ],
        onSelect: (ctx, salonData, _) async {
          await Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) =>
                  MarketingScreen(salonId: salonData['id'].toString()),
            ),
          );
        },
      ),
    );

    // C. Create New Offer / Coupon
    results.add(
      MoreMenuItem(
        id: 'create_offer',
        title: 'Create New Offer',
        category: 'Salon management',
        subtitle: 'Create flat or percentage discount coupon for services',
        icon: Icons.add_circle_outline,
        iconColor: const Color(0xFF9850F1),
        keywords: const [
          'create offer',
          'create new offer',
          'add offer',
          'new discount',
          'new coupon',
          'add discount',
          'create coupon',
          'discount code',
        ],
        onSelect: (ctx, salonData, _) async {
          await Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => CreateEditSalonOfferScreen(
                salonId: salonData['id'].toString(),
              ),
            ),
          );
        },
      ),
    );

    // D. Legal Documents
    results.add(
      MoreMenuItem(
        id: 'legal_privacy',
        title: 'Privacy Policy',
        category: 'Account & app settings',
        subtitle: 'BookALook data privacy, confidentiality & security terms',
        icon: Icons.lock_outline,
        iconColor: isDark ? AppTheme.darkInfo : AppTheme.lightInfo,
        keywords: const [
          'privacy policy',
          'privacy',
          'data privacy',
          'security',
          'data policy',
        ],
        onSelect: (ctx, _, __) async {
          await Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => const LegalDocumentScreen(slug: 'privacy'),
            ),
          );
        },
      ),
    );

    results.add(
      MoreMenuItem(
        id: 'legal_terms',
        title: 'Terms of Service',
        category: 'Account & app settings',
        subtitle: 'User agreement, platform rules & liability terms',
        icon: Icons.gavel_outlined,
        iconColor: isDark ? AppTheme.darkInfo : AppTheme.lightInfo,
        keywords: const [
          'terms of service',
          'terms',
          'user agreement',
          'terms and conditions',
          'conditions',
        ],
        onSelect: (ctx, _, __) async {
          await Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => const LegalDocumentScreen(slug: 'terms'),
            ),
          );
        },
      ),
    );

    results.add(
      MoreMenuItem(
        id: 'legal_partner_terms',
        title: 'Partner Terms',
        category: 'Account & app settings',
        subtitle: 'Salon partner agreement & commercial terms',
        icon: Icons.handshake_outlined,
        iconColor: isDark ? AppTheme.darkInfo : AppTheme.lightInfo,
        keywords: const [
          'partner terms',
          'salon terms',
          'partner agreement',
          'merchant terms',
        ],
        onSelect: (ctx, _, __) async {
          await Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => const LegalDocumentScreen(slug: 'partner-terms'),
            ),
          );
        },
      ),
    );

    results.add(
      MoreMenuItem(
        id: 'legal_cancellation',
        title: 'Cancellation & Refund Policy',
        category: 'Account & app settings',
        subtitle: 'Advance payment refund rules & cancellation windows',
        icon: Icons.event_busy_outlined,
        iconColor: isDark ? AppTheme.darkInfo : AppTheme.lightInfo,
        keywords: const [
          'cancellation policy',
          'refund policy',
          'cancellation & refund policy',
          'refunds',
          'cancel appointment',
          'advance refund',
        ],
        onSelect: (ctx, _, __) async {
          await Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) =>
                  const LegalDocumentScreen(slug: 'cancellation-refund'),
            ),
          );
        },
      ),
    );

    return results;
  }
}
