import 'package:flutter/material.dart';
import 'draft_theme.dart';

/// Shared widgets recreating the approved Replier UI draft look.

/// Pill search-style header bar with title + round icon buttons.
class DraftHeader extends StatelessWidget {
  final String title;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenSettings;

  const DraftHeader({
    super.key,
    required this.title,
    required this.isDark,
    required this.onToggleTheme,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final c = DraftColors.of(context);
    Widget roundBtn(IconData icon, String tooltip, VoidCallback onTap) =>
        Tooltip(
          message: tooltip,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.s1, shape: BoxShape.circle),
              child: Icon(icon, size: 21, color: c.tx),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: c.s1,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 20, color: c.mut),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: DraftText.display(17, c.tx),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          roundBtn(
            isDark ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded,
            isDark ? 'Switch to light mode' : 'Switch to dark mode',
            onToggleTheme,
          ),
          const SizedBox(width: 8),
          roundBtn(Icons.settings_outlined, 'Settings', onOpenSettings),
        ],
      ),
    );
  }
}

/// The big master switch card ("hero") - primary background, huge state
/// text, oversized toggle, status line and chips.
class MasterSwitchCard extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  final String statusText;
  final List<String> chips;

  const MasterSwitchCard({
    super.key,
    required this.on,
    required this.onChanged,
    required this.statusText,
    this.chips = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = DraftColors.of(context);
    final bg = on ? c.pri : c.s2;
    final fg = on ? c.onpri : c.tx;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(36),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MASTER REPLY SWITCH', style: DraftText.eyebrow(fg.withValues(alpha: .85))),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(on ? 'On' : 'Off', style: DraftText.display(37, fg)),
              GestureDetector(
                onTap: () => onChanged(!on),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 88,
                  height: 52,
                  decoration: BoxDecoration(
                    color: on ? c.onpri : c.out,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutBack,
                    alignment:
                        on ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: 39,
                      height: 39,
                      margin: const EdgeInsets.symmetric(horizontal: 6.5),
                      decoration: BoxDecoration(
                        color: on ? c.pri : c.bg,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(statusText,
              style: DraftText.body(14.5, fg, weight: FontWeight.w500)),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: on
                              ? Colors.white.withValues(alpha: .12)
                              : c.s1.withValues(alpha: .6),
                          border: Border.all(
                              color: on
                                  ? Colors.white.withValues(alpha: .45)
                                  : c.out.withValues(alpha: .5),
                              width: 1.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(t, style: DraftText.body(13, fg)),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Draft-styled small switch (52x32, outlined when off).
class DraftSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const DraftSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = DraftColors.of(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 32,
        decoration: BoxDecoration(
          color: value ? c.pri : c.s2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: value ? c.pri : c.out, width: 2),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: value ? 22 : 18,
            height: value ? 22 : 18,
            margin: const EdgeInsets.symmetric(horizontal: 3.5),
            decoration: BoxDecoration(
              color: value ? c.onpri : c.out,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Card container (28px radius, s1 background).
class DraftCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;

  const DraftCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    final c = DraftColors.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.s1,
        borderRadius: BorderRadius.circular(28),
      ),
      child: child,
    );
  }
}

/// Circular progress ring with a number inside (Analysis countdown).
class DraftRing extends StatelessWidget {
  final double progress; // 0..1
  final String label;
  final bool error;

  const DraftRing({
    super.key,
    required this.progress,
    required this.label,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = DraftColors.of(context);
    final fg = error ? c.err : c.pri;
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            strokeWidth: 9,
            strokeCap: StrokeCap.round,
            backgroundColor: c.bg,
            valueColor: AlwaysStoppedAnimation(fg),
          ),
          Center(child: Text(label, style: DraftText.display(22, c.tx))),
        ],
      ),
    );
  }
}

/// Pill progress bar (daily limits, AI budget).
class DraftProg extends StatelessWidget {
  final double progress;
  final Color? background;

  const DraftProg({super.key, required this.progress, this.background});

  @override
  Widget build(BuildContext context) {
    final c = DraftColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 14,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: background ?? c.bg),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: ColoredBox(color: c.pri),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small stat cell used in the 3-column Today grid.
class DraftStat extends StatelessWidget {
  final String value;
  final String label;

  const DraftStat({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = DraftColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(value,
              style: DraftText.display(26, c.tx)
                  .copyWith(fontFeatures: const [])),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: DraftText.body(12, c.mut)),
        ],
      ),
    );
  }
}

/// Warning banner (tc/otc, or red variant).
class DraftWarn extends StatelessWidget {
  final String text;
  final bool red;

  const DraftWarn(this.text, {super.key, this.red = false});

  @override
  Widget build(BuildContext context) {
    final c = DraftColors.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: red ? c.errc : c.tc,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: DraftText.body(14, red ? c.oerr : c.otc,
            weight: FontWeight.w500),
      ),
    );
  }
}

/// Primary/secondary/tertiary/danger pill buttons.
class DraftButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final _BtnKind _kind;

  const DraftButton(this.label,
      {super.key, this.onPressed, this.icon})
      : _kind = _BtnKind.primary;
  const DraftButton.secondary(this.label,
      {super.key, this.onPressed, this.icon})
      : _kind = _BtnKind.secondary;
  const DraftButton.tertiary(this.label,
      {super.key, this.onPressed, this.icon})
      : _kind = _BtnKind.tertiary;
  const DraftButton.danger(this.label,
      {super.key, this.onPressed, this.icon})
      : _kind = _BtnKind.danger;

  @override
  Widget build(BuildContext context) {
    final c = DraftColors.of(context);
    late final Color bg, fg;
    switch (_kind) {
      case _BtnKind.primary:
        bg = c.pri; fg = c.onpri;
      case _BtnKind.secondary:
        bg = c.pc; fg = c.onpc;
      case _BtnKind.tertiary:
        bg = Colors.transparent; fg = c.pri;
      case _BtnKind.danger:
        bg = c.errc; fg = c.oerr;
    }
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg.withValues(alpha: .4),
        padding: EdgeInsets.symmetric(
            horizontal: _kind == _BtnKind.tertiary ? 14 : 22, vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999)),
        textStyle: DraftText.display(16, fg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Text(label),
        ],
      ),
    );
  }
}

enum _BtnKind { primary, secondary, tertiary, danger }

/// Floating pill bottom navigation (dock) with 5 tabs.
class DraftNav extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  final List<({IconData icon, String label})> items;

  const DraftNav({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final c = DraftColors.of(context);
    final scaler =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        height: 70,
        decoration: BoxDecoration(
          color: c.s2,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
                color: Color(0x40000000),
                blurRadius: 24,
                offset: Offset(0, 8)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
                    decoration: BoxDecoration(
                      color: i == selected ? c.pc : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(items[i].icon,
                            size: 22,
                            color: i == selected ? c.onpc : c.mut),
                        Text(
                          items[i].label,
                          overflow: TextOverflow.ellipsis,
                          style: DraftText.body(
                              10.5, i == selected ? c.onpc : c.mut,
                              weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
