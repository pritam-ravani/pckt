import 'package:flutter/widgets.dart';

import 'icons.dart';

/// Stable string keys → icons. Keys are persisted in the DB.
abstract final class CategoryIcons {
  static const Map<String, IconData> all = {
    'food': PhosphorIconsFill.forkKnife,
    'coffee': PhosphorIconsFill.coffee,
    'groceries': PhosphorIconsFill.shoppingCart,
    'shopping': PhosphorIconsFill.shoppingBag,
    'transport': PhosphorIconsFill.taxi,
    'fuel': PhosphorIconsFill.gasPump,
    'travel': PhosphorIconsFill.airplane,
    'bills': PhosphorIconsFill.lightning,
    'recharge': PhosphorIconsFill.deviceMobile,
    'internet': PhosphorIconsFill.wifiHigh,
    'rent': PhosphorIconsFill.house,
    'entertainment': PhosphorIconsFill.popcorn,
    'subscriptions': PhosphorIconsFill.repeat,
    'health': PhosphorIconsFill.heartbeat,
    'pharmacy': PhosphorIconsFill.pill,
    'fitness': PhosphorIconsFill.barbell,
    'education': PhosphorIconsFill.graduationCap,
    'gifts': PhosphorIconsFill.gift,
    'personal': PhosphorIconsFill.tShirt,
    'pets': PhosphorIconsFill.pawPrint,
    'investments': PhosphorIconsFill.trendUp,
    'emi': PhosphorIconsFill.bank,
    'insurance': PhosphorIconsFill.shieldCheck,
    'transfer': PhosphorIconsFill.arrowsLeftRight,
    'people': PhosphorIconsFill.user,
    'salary': PhosphorIconsFill.briefcase,
    'refund': PhosphorIconsFill.arrowClockwise,
    'income': PhosphorIconsFill.handCoins,
    'cash': PhosphorIconsFill.money,
    'gaming': PhosphorIconsFill.gameController,
    'books': PhosphorIconsFill.bookOpen,
    'other': PhosphorIconsFill.dotsThreeCircle,
  };

  static IconData of(String? key) => all[key] ?? PhosphorIconsFill.dotsThreeCircle;
}
