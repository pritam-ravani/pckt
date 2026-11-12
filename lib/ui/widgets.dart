import 'package:flutter/material.dart';

import '../core/theme/icons.dart';

import '../core/format.dart';
import '../core/theme/category_icons.dart';
import '../core/theme/palette.dart';
import '../data/db/database.dart';

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Rounded-square icon tile tinted with the category color.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, this.category, this.size = 44, this.isTransfer = false});

  final Category? category;
  final double size;
  final bool isTransfer;

  @override
  Widget build(BuildContext context) {
    final color = isTransfer ? Palette.neutral : Color(category?.color ?? Palette.neutral.toARGB32());
    final icon = isTransfer ? PhosphorIconsFill.arrowsLeftRight : CategoryIcons.of(category?.icon);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.onTap, this.color});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

String txnTitle(Transaction t) =>
    t.merchant ?? t.counterparty ?? (t.direction == TxnDirection.credit ? 'Money received' : 'Payment');

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.view, this.onTap, this.showDate = false});

  final TxnView view;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final t = view.txn;
    final credit = t.direction == TxnDirection.credit;
    final subtitle = [
      if (t.isTransfer) 'Transfer' else view.category?.name ?? 'Uncategorised',
      showDate ? dayLabel(t.occurredAt) : timeLabel(t.occurredAt),
      if (view.account != null) view.account!.last4 == null ? view.account!.name : '••${view.account!.last4}',
    ].join('  ·  ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            CategoryBadge(category: view.category, isTransfer: t.isTransfer),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          txnTitle(t),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleMedium,
                        ),
                      ),
                      if (t.status == TxnStatus.needsReview) ...[
                        const SizedBox(width: 6),
                        const Icon(PhosphorIconsFill.warningCircle, size: 15, color: Palette.amber),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${credit ? '+' : '−'}${money(t.amountMinor, currency: t.currency)}',
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: t.isTransfer
                        ? context.colors.onSurfaceVariant
                        : credit
                        ? Palette.income
                        : context.colors.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (t.isForeign) ForeignAmountNote(txn: t),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Under a foreign amount: what it came to at home ("≈ ₹1,045.30"), or that
/// it isn't counted in totals yet.
class ForeignAmountNote extends StatelessWidget {
  const ForeignAmountNote({super.key, required this.txn, this.style});

  final Transaction txn;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final home = txn.homeMinor;
    return Text(
      home == null ? 'not in totals' : '≈ ${money(home)}',
      style: (style ?? context.text.labelSmall)?.copyWith(
        color: home == null ? Palette.amber : context.colors.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Palette.violet.withValues(alpha: 0.28), Palette.mint.withValues(alpha: 0.18)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(icon, size: 40, color: Palette.violet),
        ),
        const SizedBox(height: 20),
        Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

/// Small pill used for metadata (mode, account, source).
class InfoPill extends StatelessWidget {
  const InfoPill({super.key, required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: context.colors.surfaceContainerHigh, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

IconData modeIcon(PaymentMode m) => switch (m) {
  PaymentMode.upi => PhosphorIconsBold.lightning,
  PaymentMode.card => PhosphorIconsBold.creditCard,
  PaymentMode.atm => PhosphorIconsBold.money,
  PaymentMode.cash => PhosphorIconsBold.money,
  PaymentMode.wallet => PhosphorIconsBold.wallet,
  _ => PhosphorIconsBold.bank,
};

String modeLabel(PaymentMode m) => switch (m) {
  PaymentMode.upi => 'UPI',
  PaymentMode.card => 'Card',
  PaymentMode.netbanking => 'Net banking',
  PaymentMode.neft => 'NEFT',
  PaymentMode.imps => 'IMPS',
  PaymentMode.rtgs => 'RTGS',
  PaymentMode.atm => 'ATM',
  PaymentMode.wallet => 'Wallet',
  PaymentMode.cash => 'Cash',
  PaymentMode.other => 'Bank',
};

/// A coloured rounded square behind an icon, used to mark what a row or
/// tile is about.
class IconBubble extends StatelessWidget {
  const IconBubble(this.icon, {super.key, required this.color, this.size = 40});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(size * 0.3)),
    child: Icon(icon, color: color, size: size * 0.5),
  );
}

/// One row in a [MenuGroup]: icon, title, optional subtitle and value.
class MenuTile extends StatelessWidget {
  const MenuTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  /// Short text shown before the arrow, e.g. "INR" or "3 active".
  final String? value;

  /// Replaces the arrow, e.g. a switch.
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    leading: IconBubble(icon, color: color, size: 38),
    title: Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
    trailing:
        trailing ??
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null)
              Text(value!, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(PhosphorIconsBold.caretRight, size: 14, color: context.colors.onSurfaceVariant),
            ],
          ],
        ),
    onTap: onTap,
  );
}

/// Rows in one card, separated by thin dividers.
class MenuGroup extends StatelessWidget {
  const MenuGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) Divider(height: 1, indent: 62, color: context.colors.outlineVariant.withValues(alpha: 0.5)),
          c,
        ],
      ],
    ),
  );
}

/// A square shortcut in a hub grid: icon, title and a live value.
class FeatureTile extends StatelessWidget {
  const FeatureTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(14),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            IconBubble(icon, color: color, size: 34),
            const Spacer(),
            Icon(PhosphorIconsBold.caretRight, size: 14, color: context.colors.onSurfaceVariant),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    ),
  );
}

/// The large title at the top of a tab, with optional actions on the right.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.title, {super.key, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 0, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.headlineSmall),
              if (subtitle != null)
                Text(subtitle!, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
            ],
          ),
        ),
        ...actions,
      ],
    ),
  );
}
