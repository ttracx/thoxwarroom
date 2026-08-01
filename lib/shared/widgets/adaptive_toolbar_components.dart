import 'dart:io' show Platform;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme_extensions.dart';
import '../utils/adaptive_glass.dart';
import 'thoxwarroom_components.dart';
import 'thoxwarroom_loading.dart';
import 'middle_ellipsis_text.dart';
import 'themed_sheets.dart';

const double kThoxWarRoomAdaptiveToolbarLeadingGap = Spacing.sm;
const double kThoxWarRoomAdaptiveToolbarMaxPillWidth = 220;
const double kThoxWarRoomMaximumSystemControlScale = 1.5;

/// Converts Dynamic Type into bounded control geometry.
///
/// Text remains free to use the full system scale. Chrome grows more slowly,
/// matching the way sidebar rows expand around their scaled text without ever
/// shrinking below the normal 44-point touch target.
double resolveThoxWarRoomSystemControlScale(TextScaler textScaler) {
  final scaledBodySize = textScaler.scale(AppTypography.bodyLarge);
  final scale = scaledBodySize / AppTypography.bodyLarge;
  if (!scale.isFinite) return 1;
  return scale.clamp(1, kThoxWarRoomMaximumSystemControlScale).toDouble();
}

double conduitSystemControlScaleOf(BuildContext context) {
  return resolveThoxWarRoomSystemControlScale(MediaQuery.textScalerOf(context));
}

double thoxScaledControlExtent(
  BuildContext context, {
  double baseExtent = TouchTarget.minimum,
}) {
  return baseExtent * conduitSystemControlScaleOf(context);
}

double thoxScaledIconExtent(BuildContext context, double baseExtent) {
  return baseExtent * conduitSystemControlScaleOf(context);
}

double thoxAdaptiveToolbarHeightOf(BuildContext context) {
  return kTextTabBarHeight * conduitSystemControlScaleOf(context);
}

/// Icon glyph that follows the platform Bold Text accessibility setting.
///
/// Flutter applies [MediaQueryData.boldText] to [Text] and [EditableText]
/// automatically, but fixed icon fonts do not gain the heavier strokes that
/// native SF Symbols do. A small, hard-edged outline closes that gap without
/// changing the glyph's measured size or touch target.
class ThoxWarRoomSystemAdaptiveIcon extends StatelessWidget {
  const ThoxWarRoomSystemAdaptiveIcon(
    this.icon, {
    super.key,
    required this.size,
    required this.color,
  });

  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const offset = 0.45;
    final shadows = MediaQuery.boldTextOf(context)
        ? <Shadow>[
            Shadow(color: color, offset: const Offset(-offset, 0)),
            Shadow(color: color, offset: const Offset(offset, 0)),
            Shadow(color: color, offset: const Offset(0, -offset)),
            Shadow(color: color, offset: const Offset(0, offset)),
          ]
        : null;

    return Icon(icon, size: size, color: color, shadows: shadows);
  }
}

/// Restores the route's system text scaler inside framework chrome that clamps
/// or disables scaling, including Cupertino navigation bars.
class ThoxWarRoomSystemTextScaling extends StatelessWidget {
  const ThoxWarRoomSystemTextScaling({
    super.key,
    required this.textScaler,
    required this.child,
  });

  final TextScaler textScaler;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child,
    );
  }
}

/// Transparent Cupertino toolbar that expands with Dynamic Type.
///
/// [CupertinoPageScaffold] deliberately disables text scaling for navigation
/// bars. This shell restores the route scaler and advertises the matching
/// preferred height so scaled controls are neither clipped nor overlaid on the
/// page body.
class ThoxWarRoomAdaptiveCupertinoNavigationBar extends StatelessWidget
    implements ObstructingPreferredSizeWidget {
  const ThoxWarRoomAdaptiveCupertinoNavigationBar({
    super.key,
    required this.textScaler,
    required this.leading,
    this.middle,
    this.trailing,
    this.systemOverlayStyle,
  });

  final TextScaler textScaler;
  final Widget leading;
  final Widget? middle;
  final Widget? trailing;
  final SystemUiOverlayStyle? systemOverlayStyle;

  double get _controlScale => resolveThoxWarRoomSystemControlScale(textScaler);

  @override
  Size get preferredSize => Size.fromHeight(kTextTabBarHeight * _controlScale);

  @override
  bool shouldFullyObstruct(BuildContext context) => false;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    Widget bar = SizedBox(
      height: topPadding + preferredSize.height,
      child: Padding(
        padding: EdgeInsets.only(
          top: topPadding,
          left: Spacing.inputPadding,
          right: Spacing.inputPadding,
        ),
        child: ThoxWarRoomSystemTextScaling(
          textScaler: textScaler,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: leading,
              ),
              if (middle != null)
                PositionedDirectional(
                  start: (TouchTarget.minimum * _controlScale) + Spacing.sm,
                  end: (TouchTarget.minimum * _controlScale) + Spacing.sm,
                  top: 0,
                  bottom: 0,
                  child: Center(child: middle),
                ),
              if (trailing != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: trailing,
                ),
            ],
          ),
        ),
      ),
    );

    if (systemOverlayStyle != null) {
      bar = AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemOverlayStyle!,
        child: bar,
      );
    }
    return bar;
  }
}

Widget _hideNativeToolbarChromeWhileSheetCovered({
  required Size size,
  required Widget child,
}) {
  return ThemedSheets.hideNativeChromeWhileCovered(
    replacement: SizedBox.fromSize(size: size),
    child: child,
  );
}

/// Builds the shared adaptive toolbar shell used by chat-style pages.
AdaptiveAppBar buildThoxWarRoomAdaptiveToolbarAppBar({
  required Color tintColor,
  required Widget Function() buildLeading,
  required List<AdaptiveAppBarAction> Function() buildActions,
  double? leadingWidth,
}) {
  final leading = buildLeading();
  final actions = buildActions();
  final materialActions = _buildMaterialToolbarActions(
    actions,
    defaultTint: tintColor,
  );

  return AdaptiveAppBar(
    useNativeToolbar: Platform.isIOS || leadingWidth == null,
    leading: leading,
    tintColor: tintColor,
    actions: actions,
    appBar: leadingWidth == null
        ? null
        : _buildMaterialToolbarAppBar(
            leading: leading,
            leadingWidth: leadingWidth,
            actions: materialActions,
          ),
  );
}

PreferredSizeWidget _buildMaterialToolbarAppBar({
  required Widget leading,
  required double leadingWidth,
  required List<Widget> actions,
}) {
  return AppBar(
    automaticallyImplyLeading: false,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: Elevation.none,
    scrolledUnderElevation: Elevation.none,
    toolbarHeight: kTextTabBarHeight,
    centerTitle: false,
    titleSpacing: Spacing.sm,
    leadingWidth: leadingWidth,
    leading: leading,
    actions: actions,
  );
}

List<Widget> _buildMaterialToolbarActions(
  List<AdaptiveAppBarAction> actions, {
  required Color defaultTint,
}) {
  return buildThoxWarRoomAdaptiveToolbarActionWidgets([
    for (final action in actions)
      _buildMaterialToolbarAction(action, defaultTint: defaultTint),
  ]);
}

Widget _buildMaterialToolbarAction(
  AdaptiveAppBarAction action, {
  required Color defaultTint,
}) {
  final tintColor = action.tintColor ?? defaultTint;
  if (action.title != null) {
    return TextButton(
      onPressed: action.onPressed,
      style: TextButton.styleFrom(foregroundColor: tintColor),
      child: Text(action.title!),
    );
  }

  return ThoxWarRoomAdaptiveAppBarIconButton(
    icon: action.icon ?? Icons.circle,
    onPressed: action.onPressed,
    iconColor: tintColor,
  );
}

Widget buildThoxWarRoomAdaptiveToolbarLeadingRow({required List<Widget> children}) {
  if (Platform.isIOS) {
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  return Padding(
    padding: const EdgeInsets.only(left: Spacing.inputPadding),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}

List<Widget> buildThoxWarRoomAdaptiveToolbarActionWidgets(List<Widget> actions) {
  final widgets = <Widget>[];
  for (var i = 0; i < actions.length; i++) {
    if (i > 0) {
      widgets.add(const SizedBox(width: Spacing.sm));
    }
    widgets.add(
      i == actions.length - 1
          ? Platform.isIOS
                ? actions[i]
                : Padding(
                    padding: const EdgeInsets.only(right: Spacing.inputPadding),
                    child: actions[i],
                  )
          : actions[i],
    );
  }

  return widgets;
}

TextStyle thoxAdaptiveToolbarPillTextStyle(BuildContext context) {
  return AppTypography.standard.copyWith(
    color: context.thoxTheme.textPrimary,
    fontWeight: FontWeight.w600,
  );
}

Widget buildThoxWarRoomAdaptiveToolbarPillSurface({
  required double width,
  required Widget child,
  VoidCallback? onPressed,
  String? semanticLabel,
  double height = TouchTarget.minimum,
}) {
  final sizedChild = SizedBox(width: width, height: height, child: child);

  if (thoxUsesOpaqueGlassFallback()) {
    if (onPressed == null) {
      return SizedBox(
        width: width,
        child: FloatingAppBarPill(child: child),
      );
    }

    return FloatingAppBarButton(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      child: sizedChild,
    );
  }

  return _hideNativeToolbarChromeWhileSheetCovered(
    size: Size(width, height),
    child: AdaptiveButton.child(
      onPressed: onPressed ?? () {},
      style: AdaptiveButtonStyle.glass,
      size: AdaptiveButtonSize.large,
      padding: EdgeInsets.zero,
      minSize: Size(width, height),
      useSmoothRectangleBorder: false,
      child: sizedChild,
    ),
  );
}

double resolveThoxWarRoomAdaptiveToolbarLeadingWidth({
  required double pillWidth,
  double leadingGap = kThoxWarRoomAdaptiveToolbarLeadingGap,
  double controlExtent = TouchTarget.minimum,
}) {
  return Spacing.inputPadding +
      controlExtent +
      leadingGap +
      pillWidth +
      Spacing.md;
}

/// Resolves a stable pill width inside a constrained toolbar slot.
///
/// The result never exceeds the available space. When the preferred padding
/// would make the pill too small, the helper still keeps a small minimum gap so
/// the title does not visually collide with neighboring controls.
double resolveThoxWarRoomAdaptiveToolbarPillWidth({
  required double availableWidth,
  required double maxWidth,
  double preferredPadding = 0,
  double minimumPadding = Spacing.sm,
}) {
  final preferredReservedPadding = preferredPadding > minimumPadding
      ? preferredPadding
      : minimumPadding;
  final effectivePadding = availableWidth > minimumPadding
      ? preferredReservedPadding
            .clamp(minimumPadding, availableWidth)
            .toDouble()
      : 0.0;
  final effectiveWidth = availableWidth - effectivePadding;

  return effectiveWidth.clamp(0.0, maxWidth).toDouble();
}

/// Estimates a safe leading-pill width for native adaptive toolbars.
///
/// Native toolbars do not automatically rebalance the leading area against
/// trailing actions, so callers provide the trailing action count and let this
/// helper reserve the remaining space before sizing the pill.
double resolveThoxWarRoomAdaptiveLeadingPillWidth(
  BuildContext context, {
  required int trailingActionCount,
  required double maxWidth,
  double leadingGap = kThoxWarRoomAdaptiveToolbarLeadingGap,
  double trailingActionSpacing = Spacing.sm,
}) {
  final controlExtent = thoxScaledControlExtent(context);
  final trailingSpacing = trailingActionCount > 1
      ? (trailingActionCount - 1) * trailingActionSpacing
      : 0.0;
  final trailingWidth = trailingActionCount > 0
      ? (trailingActionCount * controlExtent) +
            trailingSpacing +
            Spacing.inputPadding
      : Spacing.inputPadding;
  final availableWidth =
      MediaQuery.sizeOf(context).width -
      controlExtent -
      leadingGap -
      trailingWidth -
      (Spacing.inputPadding * 2);

  return resolveThoxWarRoomAdaptiveToolbarPillWidth(
    availableWidth: availableWidth,
    maxWidth: maxWidth,
  );
}

/// Measures a text pill and clamps it to the safe toolbar width budget.
double resolveThoxWarRoomAdaptiveTextPillWidth({
  required BuildContext context,
  required String label,
  required TextStyle textStyle,
  required double maxWidth,
  double minWidth = 0,
  double horizontalPadding = 0,
  double leadingWidth = 0,
  double trailingWidth = 0,
}) {
  final safeMaxWidth = maxWidth.clamp(0.0, double.infinity).toDouble();
  if (safeMaxWidth == 0) {
    return 0;
  }
  final safeMinWidth = minWidth.clamp(0.0, safeMaxWidth).toDouble();
  final textPainter = TextPainter(
    text: TextSpan(text: label, style: textStyle),
    maxLines: 1,
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
  )..layout(minWidth: 0, maxWidth: double.infinity);

  final measuredWidth =
      textPainter.width + horizontalPadding + leadingWidth + trailingWidth;

  return measuredWidth.clamp(safeMinWidth, safeMaxWidth).toDouble();
}

Object thoxAdaptivePopupMenuIcon({
  required String iosSymbol,
  required IconData materialIcon,
}) {
  return Platform.isIOS ? iosSymbol : materialIcon;
}

/// Adaptive floating app-bar icon button for route-level toolbar actions.
class ThoxWarRoomAdaptiveAppBarIconButton extends StatelessWidget {
  /// Creates an adaptive toolbar icon button.
  const ThoxWarRoomAdaptiveAppBarIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.iconColor,
  });

  /// Icon shown inside the control.
  final IconData icon;

  /// Invoked when the control is tapped.
  final VoidCallback? onPressed;

  /// Optional icon tint.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? context.thoxTheme.textPrimary;
    final controlExtent = thoxScaledControlExtent(context);
    final iconExtent = thoxScaledIconExtent(context, IconSize.appBar);

    if (thoxUsesOpaqueGlassFallback()) {
      return SizedBox.square(
        dimension: controlExtent,
        child: FloatingAppBarButton(
          onTap: onPressed,
          isCircular: true,
          child: ThoxWarRoomSystemAdaptiveIcon(
            icon,
            size: iconExtent,
            color: effectiveIconColor,
          ),
        ),
      );
    }

    return _hideNativeToolbarChromeWhileSheetCovered(
      size: Size.square(controlExtent),
      child: AdaptiveButton.child(
        onPressed: onPressed,
        style: AdaptiveButtonStyle.glass,
        size: AdaptiveButtonSize.large,
        padding: EdgeInsets.zero,
        minSize: Size.square(controlExtent),
        useSmoothRectangleBorder: false,
        child: ThoxWarRoomSystemAdaptiveIcon(
          icon,
          size: iconExtent,
          color: effectiveIconColor,
        ),
      ),
    );
  }
}

/// Adaptive model-selector control used by floating route toolbars.
class ThoxWarRoomAdaptiveAppBarModelSelector extends StatelessWidget {
  /// Creates an adaptive toolbar model selector.
  const ThoxWarRoomAdaptiveAppBarModelSelector({
    super.key,
    required this.label,
    required this.maxWidth,
    required this.onPressed,
    this.isLoading = false,
    this.textStyle,
    this.showChevron = true,
  });

  /// Text shown inside the selector.
  final String label;

  /// Maximum width available for the selector.
  ///
  /// Short labels shrink to fit their content while longer labels ellipsize
  /// inside this cap so toolbar layout still respects neighboring actions.
  final double maxWidth;

  /// Invoked when the selector is tapped.
  final VoidCallback onPressed;

  /// Whether to render a loading placeholder instead of the current label.
  final bool isLoading;

  /// Optional text style override for the selector label.
  final TextStyle? textStyle;

  /// Whether to show the dropdown chevron and allow tapping to change models.
  /// Hidden for single-agent backends (e.g. the Hermes agent) where there is
  /// nothing to pick.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final effectiveTextStyle =
        textStyle ?? thoxAdaptiveToolbarPillTextStyle(context);
    final safeMaxWidth = maxWidth.clamp(0.0, double.infinity).toDouble();
    if (safeMaxWidth == 0) {
      return const SizedBox.shrink();
    }
    final controlExtent = thoxScaledControlExtent(context);
    final chevronSize = thoxScaledIconExtent(
      context,
      Platform.isIOS ? IconSize.small : IconSize.medium,
    );
    const leadingPadding = 10.0;
    final targetWidth = isLoading
        ? safeMaxWidth.clamp(0.0, 104.0).toDouble()
        : resolveThoxWarRoomAdaptiveTextPillWidth(
            context: context,
            label: label,
            textStyle: effectiveTextStyle,
            maxWidth: safeMaxWidth,
            minWidth: 96,
            horizontalPadding: leadingPadding + Spacing.xs + 12,
            // Only reserve chevron space when a chevron is actually rendered.
            trailingWidth: showChevron ? chevronSize + Spacing.xs : 0,
          );
    final child = SizedBox(
      width: targetWidth,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: controlExtent),
        child: Padding(
          padding: EdgeInsets.only(left: leadingPadding, right: Spacing.xs),
          child: Center(
            widthFactor: 1,
            child: isLoading
                ? ThoxWarRoomLoading.skeleton(
                    width: 80,
                    height: 14,
                    borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: MiddleEllipsisText(
                          label,
                          style: effectiveTextStyle,
                          textAlign: TextAlign.center,
                          semanticsLabel: label,
                          textHeightBehavior: const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                            applyHeightToLastDescent: false,
                          ),
                        ),
                      ),
                      if (showChevron) ...[
                        const SizedBox(width: Spacing.xs),
                        ThoxWarRoomSystemAdaptiveIcon(
                          Platform.isIOS
                              ? CupertinoIcons.chevron_down
                              : Icons.keyboard_arrow_down,
                          color: context.thoxTheme.iconSecondary,
                          size: chevronSize,
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );

    if (thoxUsesOpaqueGlassFallback()) {
      return FloatingAppBarButton(
        onTap: (isLoading || !showChevron) ? null : onPressed,
        semanticLabel: label,
        child: child,
      );
    }

    return _hideNativeToolbarChromeWhileSheetCovered(
      size: Size(targetWidth, controlExtent),
      child: AdaptiveButton.child(
        onPressed: (isLoading || !showChevron) ? null : onPressed,
        style: AdaptiveButtonStyle.glass,
        size: AdaptiveButtonSize.large,
        padding: EdgeInsets.zero,
        minSize: Size(targetWidth, controlExtent),
        useSmoothRectangleBorder: false,
        child: child,
      ),
    );
  }
}

class ThoxWarRoomAdaptiveToolbarOverflowButton<T> extends StatelessWidget {
  const ThoxWarRoomAdaptiveToolbarOverflowButton({
    super.key,
    required this.tintColor,
    required this.items,
    required this.onSelected,
    this.iosIcon = 'ellipsis',
    this.materialIcon = Icons.more_vert_rounded,
  });

  final Color tintColor;
  final List<AdaptivePopupMenuEntry> items;
  final ValueChanged<T> onSelected;
  final String iosIcon;
  final IconData materialIcon;

  void _handleSelected(int index, AdaptivePopupMenuItem<T> entry) {
    final value = entry.value;
    if (value != null) {
      onSelected(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controlExtent = thoxScaledControlExtent(context);
    final iconExtent = thoxScaledIconExtent(context, IconSize.appBar);
    if (thoxUsesOpaqueGlassFallback()) {
      return AdaptivePopupMenuButton.widget<T>(
        items: items,
        onSelected: _handleSelected,
        child: SizedBox.square(
          dimension: controlExtent,
          child: FloatingAppBarButton(
            isCircular: true,
            child: ThoxWarRoomSystemAdaptiveIcon(
              Platform.isIOS ? CupertinoIcons.ellipsis : materialIcon,
              size: iconExtent,
              color: tintColor,
            ),
          ),
        ),
      );
    }

    return _hideNativeToolbarChromeWhileSheetCovered(
      size: Size.square(controlExtent),
      child: AdaptivePopupMenuButton.icon<T>(
        icon: Platform.isIOS ? iosIcon : materialIcon,
        tint: tintColor,
        size: controlExtent,
        buttonStyle: PopupButtonStyle.glass,
        items: items,
        onSelected: _handleSelected,
      ),
    );
  }
}
