import 'dart:math';
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

part 'body.dart';
part 'indicators.dart';
part 'pane.dart';
part 'style.dart';

/// The default size used by the app top bar.
///
/// Value eyeballed from Windows 10 v10.0.19041.928
const double _kDefaultAppBarHeight = 31.0;

const ShapeBorder kDefaultContentClipper = RoundedRectangleBorder(
  side: BorderSide(width: 0.8, color: Colors.black),
  borderRadius: BorderRadius.only(
    topLeft: Radius.circular(8.0),
  ),
);

/// The NavigationView control provides top-level navigation
/// for your app. It adapts to a variety of screen sizes and
/// supports both top and left navigation styles.
///
/// ![](https://docs.microsoft.com/en-us/windows/uwp/design/controls-and-patterns/images/nav-view-header.png)
///
/// See also:
///   * [NavigationBody], a widget that implement fluent
///     transitions into [NavigationView]
///   * [NavigationPane], the pane used by [NavigationView],
///     that can be displayed either at the left and top
///   * [TabView], a widget similar to [NavigationView], useful
///     to display several pages of content while giving a user
///     the capability to rearrange, open, or close new tabs.
class NavigationView extends StatefulWidget {
  /// Creates a navigation view.
  const NavigationView({
    Key? key,
    this.appBar,
    this.pane,
    this.content = const SizedBox.shrink(),
    this.clipBehavior = Clip.antiAlias,
    this.contentShape = kDefaultContentClipper,
    // If more properties are added here, make sure to
    // add them to the automatic mode as well.
  }) : super(key: key);

  /// The app bar of the app.
  final NavigationAppBar? appBar;

  /// The navigation pane, that can be displayed either on the
  /// left, on the top, or above [content].
  final NavigationPane? pane;

  /// The content of the pane.
  ///
  /// Usually an [NavigationBody].
  final Widget content;

  /// {@macro flutter.rendering.ClipRectLayer.clipBehavior}
  ///
  /// Defaults to [Clip.hardEdge].
  final Clip clipBehavior;

  /// How the content should be clipped
  ///
  /// The content is not clipped on when [PaneDisplayMode.displayMode]
  /// is [PaneDisplayMode.minimal]
  final ShapeBorder contentShape;

  static NavigationViewState of(BuildContext context) {
    return context.findAncestorStateOfType<NavigationViewState>()!;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty('appBar', appBar));
    properties.add(DiagnosticsProperty('pane', pane));
  }

  @override
  NavigationViewState createState() => NavigationViewState();
}

class NavigationViewState extends State<NavigationView> {
  /// The scroll controller used to keep the scrolling state of
  /// the list view when the display mode is switched between open
  /// and compact, and even keep it for the minimal state.
  ///
  /// It's also used to display and control the [Scrollbar] introduced
  /// by the panes.
  late ScrollController scrollController;

  /// The key used to animate between open and compact display mode
  final _panelKey = GlobalKey();
  final _listKey = GlobalKey();

  /// The overlay entry used for minimal pane
  OverlayEntry? minimalOverlayEntry;
  final minimalPaneKey = GlobalKey<__MinimalNavigationPaneState>();

  bool get isMinimalPaneOpen =>
      minimalOverlayEntry != null || (minimalOverlayEntry?.mounted ?? false);
  bool isMinimalPaneClosing = false;

  bool _compactOverlayOpen = false;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      debugLabel: '${widget.runtimeType} scroll controller',
      keepScrollOffset: true,
    );
  }

  @override
  void didUpdateWidget(NavigationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pane?.scrollController != scrollController) {
      scrollController = widget.pane?.scrollController ?? scrollController;
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasFluentTheme(context));
    assert(debugCheckHasFluentLocalizations(context));

    final localizations = FluentLocalizations.of(context);
    Widget appBar = () {
      if (widget.appBar != null) {
        final additionalLeading = PaneItem(
          title: Text(!isMinimalPaneOpen
              ? localizations.openNavigationTooltip
              : localizations.closeNavigationTooltip),
          icon: const Icon(FluentIcons.global_nav_button),
        ).build(
          context,
          false,
          () async {
            if (isMinimalPaneOpen) {
              setState(() => isMinimalPaneClosing = true);
              await minimalPaneKey.currentState?.removeEntry();
            } else {
              _openMinimalOverlay(context);
            }
            setState(() {});
          },
          displayMode: PaneDisplayMode.compact,
        );
        return _NavigationAppBar(
          appBar: widget.appBar!,
          additionalLeading: widget.pane?.displayMode == PaneDisplayMode.minimal
              ? additionalLeading
              : null,
        );
      }
      return SizedBox.shrink();
    }();

    Widget paneResult = LayoutBuilder(
      builder: (context, consts) {
        late Widget paneResult;
        if (widget.pane != null) {
          final pane = widget.pane!;
          if (pane.displayMode == PaneDisplayMode.auto) {
            /// For more info on the adaptive behavior, see
            /// https://docs.microsoft.com/en-us/windows/uwp/design/controls-and-patterns/navigationview#adaptive-behavior
            ///
            ///  DD/MM/YYYY
            /// (23/05/2021)
            ///
            /// When PaneDisplayMode is set to its default value of Auto, the adaptive behavior is to show:
            /// - An expanded left pane on large window widths (1008px or greater).
            /// - A left, icon-only, nav pane (compact) on medium window widths (641px to 1007px).
            /// - Only a menu button (minimal) on small window widths (640px or less).
            double width = consts.biggest.width;
            if (width.isInfinite) width = MediaQuery.of(context).size.width;

            late PaneDisplayMode autoDisplayMode;
            if (width <= 640) {
              autoDisplayMode = PaneDisplayMode.minimal;
            } else if (width >= 1008) {
              autoDisplayMode = PaneDisplayMode.open;
            } else if (width > 640) {
              autoDisplayMode = PaneDisplayMode.compact;
            }

            assert(autoDisplayMode != PaneDisplayMode.auto);

            /// We display a new navigation view with the current display mode.
            /// We can do this because [autoDisplayMode] can never be `auto`,
            /// so it won't stack overflow (error).
            return NavigationView(
              appBar: widget.appBar,
              content: widget.content,
              clipBehavior: widget.clipBehavior,
              contentShape: widget.contentShape,
              pane: NavigationPane(
                displayMode: autoDisplayMode,
                autoSuggestBox: pane.autoSuggestBox,
                autoSuggestBoxReplacement: pane.autoSuggestBoxReplacement,
                footerItems: pane.footerItems,
                header: pane.header,
                items: pane.items,
                key: pane.key,
                onChanged: pane.onChanged,
                selected: pane.selected,
                menuButton: pane.menuButton,
                scrollController: pane.scrollController,
                indicatorBuilder: pane.indicatorBuilder,
              ),
            );
          } else {
            Widget content = pane.displayMode == PaneDisplayMode.minimal
                ? widget.content
                : DecoratedBox(
                    decoration: ShapeDecoration(shape: widget.contentShape),
                    child: ClipPath(
                      clipBehavior: widget.clipBehavior,
                      clipper: ShapeBorderClipper(shape: widget.contentShape),
                      child: widget.content,
                    ),
                  );
            if (pane.displayMode != PaneDisplayMode.compact)
              _compactOverlayOpen = false;
            switch (pane.displayMode) {
              case PaneDisplayMode.top:
                paneResult = Column(children: [
                  appBar,
                  PrimaryScrollController(
                    controller: scrollController,
                    child: _TopNavigationPane(
                      pane: pane,
                      listKey: _listKey,
                    ),
                  ),
                  Expanded(child: content),
                ]);
                break;
              case PaneDisplayMode.compact:
                paneResult = Stack(children: [
                  Positioned(
                    top: widget.appBar?.height ?? 0.0,
                    left: _kCompactNavigationPanelWidth,
                    right: 0,
                    bottom: 0,
                    child: ClipRect(child: content),
                  ),
                  if (_compactOverlayOpen)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _compactOverlayOpen = false);
                        },
                        child: AbsorbPointer(
                          child: Semantics(
                            label: localizations.modalBarrierDismissLabel,
                            child: SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  appBar,
                  Padding(
                    padding: EdgeInsets.only(top: widget.appBar?.height ?? 0.0),
                    child: PrimaryScrollController(
                      controller: scrollController,
                      child: _compactOverlayOpen
                          ? Mica(
                              child: _OpenNavigationPane(
                                pane: pane,
                                paneKey: _panelKey,
                                listKey: _listKey,
                                onToggle: () {
                                  setState(() => _compactOverlayOpen = false);
                                },
                              ),
                            )
                          : Mica(
                              child: _CompactNavigationPane(
                                pane: pane,
                                paneKey: _panelKey,
                                listKey: _listKey,
                                onToggle: () {
                                  setState(() => _compactOverlayOpen = true);
                                },
                              ),
                            ),
                    ),
                  ),
                ]);
                break;
              case PaneDisplayMode.open:
                paneResult = Column(children: [
                  appBar,
                  Expanded(
                    child: Row(children: [
                      PrimaryScrollController(
                        controller: scrollController,
                        child: _OpenNavigationPane(
                          pane: pane,
                          paneKey: _panelKey,
                          listKey: _listKey,
                        ),
                      ),
                      Expanded(child: ClipRect(child: content)),
                    ]),
                  ),
                ]);
                break;
              case PaneDisplayMode.minimal:
                paneResult = Column(children: [
                  appBar,
                  Expanded(child: content),
                ]);
                break;
              default:
                paneResult = content;
            }
          }
        } else {
          paneResult = widget.content;
        }
        return paneResult;
      },
    );
    return Mica(
      child: _NavigationBody(
        displayMode: _compactOverlayOpen
            ? PaneDisplayMode.open
            : widget.pane?.displayMode,
        minimalPaneOpen: isMinimalPaneOpen && !isMinimalPaneClosing,
        child: paneResult,
      ),
    );
  }

  void _openMinimalOverlay(BuildContext context) {
    assert(debugCheckHasFluentTheme(context));
    assert(debugCheckHasOverlay(context));
    setState(() => isMinimalPaneClosing = false);
    final theme = NavigationPaneTheme.of(context);
    minimalOverlayEntry = OverlayEntry(builder: (_) {
      return FocusScope(
        autofocus: true,
        child: PrimaryScrollController(
          controller: scrollController,
          child: Padding(
            padding: EdgeInsets.only(top: widget.appBar?.height ?? 0),
            child: _MinimalNavigationPane(
              key: minimalPaneKey,
              pane: widget.pane!,
              animationDuration: theme.animationDuration ?? Duration.zero,
              entry: minimalOverlayEntry!,
              onStartBack: () {
                setState(() => isMinimalPaneClosing = true);
              },
              onBack: () {
                setState(() => minimalOverlayEntry = null);
              },
              y: widget.appBar?.height ?? 0,
            ),
          ),
        ),
      );
    });
    Overlay.of(context, debugRequiredFor: widget)!.insert(minimalOverlayEntry!);
  }
}

/// The bar displayed at the top of the app. It can adapt itself to
/// all the display modes.
///
/// See also:
///   - [NavigationView]
///   - [NavigationPane]
///   - [PaneDisplayMode]
class NavigationAppBar with Diagnosticable {
  final Key? key;

  /// The widget at the beggining of the app bar, before [title].
  ///
  /// Typically the [leading] widget is an [Icon] or an [IconButton].
  ///
  /// If this is null and [automaticallyImplyLeading] is set to true, the
  /// view will imply an appropriate widget. If  the parent [Navigator] can
  /// go back, the app bar will use an [IconButton] that calls [Navigator.maybePop].
  ///
  /// See also:
  ///   * [automaticallyImplyLeading], that controls whether we should try to
  ///     imply the leading widget, if [leading] is null
  final Widget? leading;

  /// {@macro flutter.material.appbar.automaticallyImplyLeading}
  final bool automaticallyImplyLeading;

  /// Typically a [Text] widget that contains the app name.
  final Widget? title;

  /// A list of Widgets to display in a row after the [title] widget.
  ///
  /// Typically these widgets are [IconButton]s representing common
  /// operations.
  final Widget? actions;

  /// The height of the app bar. [_kDefaultAppBarHeight] is used by default
  final double height;

  /// The background color. If null, [ThemeData.scaffoldBackgroundColor] is
  /// used.
  final Color? backgroundColor;

  /// Creates an app bar
  const NavigationAppBar({
    this.key,
    this.leading,
    this.title,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.height = _kDefaultAppBarHeight,
    this.backgroundColor,
  });

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(FlagProperty(
      'automatically imply leading',
      value: automaticallyImplyLeading,
      ifFalse: 'do not imply leading',
      defaultValue: true,
    ));
    properties.add(ColorProperty('backgroundColor', backgroundColor));
    properties.add(DoubleProperty(
      'height',
      height,
      defaultValue: _kDefaultAppBarHeight,
    ));
  }

  static Widget buildLeading(
    BuildContext context,
    NavigationAppBar appBar, [
    bool imply = true,
  ]) {
    final ModalRoute<dynamic>? parentRoute = ModalRoute.of(context);
    final bool canPop = parentRoute?.canPop ?? false;
    late Widget widget;
    if (appBar.leading != null) {
      widget = Padding(
        padding: EdgeInsets.only(left: 12.0),
        child: appBar.leading,
      );
    } else if (appBar.automaticallyImplyLeading && imply) {
      final onPressed = canPop ? () => Navigator.maybePop(context) : null;
      widget = Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: _kCompactNavigationPanelWidth,
          child: IconButton(
            icon: Icon(FluentIcons.back, size: 18.0),
            onPressed: onPressed,
            style: ButtonStyle(
              backgroundColor: ButtonState.resolveWith((states) {
                if (states.isNone || states.isDisabled)
                  return Colors.transparent;
                return ButtonThemeData.uncheckedInputColor(
                  FluentTheme.of(context),
                  states,
                );
              }),
              foregroundColor: ButtonState.resolveWith((states) {
                if (states.isDisabled)
                  return ButtonThemeData.buttonColor(
                    FluentTheme.of(context).brightness,
                    states,
                  );
                return ButtonThemeData.uncheckedInputColor(
                  FluentTheme.of(context),
                  states,
                ).basedOnLuminance();
              }),
            ),
          ),
        ),
      );
      if (canPop)
        widget = Tooltip(
          message: FluentLocalizations.of(context).backButtonTooltip,
          child: widget,
        );
    } else {
      return SizedBox.shrink();
    }
    widget = SizedBox(width: _kCompactNavigationPanelWidth, child: widget);
    return widget;
  }
}

class _NavigationAppBar extends StatefulWidget {
  const _NavigationAppBar({
    Key? key,
    required this.appBar,
    this.displayMode,
    this.additionalLeading,
  }) : super(key: key);

  final NavigationAppBar appBar;
  final PaneDisplayMode? displayMode;
  final Widget? additionalLeading;

  @override
  __NavigationAppBarState createState() => __NavigationAppBarState();
}

class __NavigationAppBarState extends State<_NavigationAppBar> {
  final GlobalKey _openCompactKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasFluentTheme(context));
    final PaneDisplayMode displayMode = widget.displayMode ??
        _NavigationBody.maybeOf(context)?.displayMode ??
        PaneDisplayMode.top;
    final theme = NavigationPaneTheme.of(context);
    final leading = NavigationAppBar.buildLeading(
      context,
      widget.appBar,
      displayMode != PaneDisplayMode.top,
    );
    final title = () {
      if (widget.appBar.title != null) {
        return Padding(
          padding: const EdgeInsets.only(left: 24.0),
          child: DefaultTextStyle(
            style: FluentTheme.of(context).typography.caption!,
            overflow: TextOverflow.clip,
            maxLines: 1,
            softWrap: false,
            child: widget.appBar.title!,
          ),
        );
      } else
        return SizedBox.shrink();
    }();
    late Widget result;
    switch (displayMode) {
      case PaneDisplayMode.top:
        result = Row(children: [
          leading,
          if (widget.additionalLeading != null) widget.additionalLeading!,
          title,
          if (widget.appBar.actions != null)
            Expanded(child: widget.appBar.actions!),
        ]);
        break;
      case PaneDisplayMode.minimal:
      case PaneDisplayMode.open:
      case PaneDisplayMode.compact:
        final isMinimalPaneOpen =
            _NavigationBody.maybeOf(context)?.minimalPaneOpen ?? false;
        final double width =
            displayMode == PaneDisplayMode.minimal && !isMinimalPaneOpen
                ? 0.0
                : displayMode == PaneDisplayMode.compact
                    ? _kCompactNavigationPanelWidth
                    : _kOpenNavigationPanelWidth;
        result = Stack(children: [
          AnimatedContainer(
            duration: theme.animationDuration ?? Duration.zero,
            curve: theme.animationCurve ?? Curves.linear,
            key: _openCompactKey,
            width: width,
            height: widget.appBar.height,
          ),
          AnimatedPadding(
            duration: theme.animationDuration ?? Duration.zero,
            curve: theme.animationCurve ?? Curves.linear,
            padding: EdgeInsets.only(left: width),
            child: widget.appBar.actions ?? SizedBox(),
          ),
          Row(children: [
            leading,
            if (widget.additionalLeading != null) widget.additionalLeading!,
            Expanded(child: title),
          ]),
        ]);
        break;
      default:
        return SizedBox.shrink();
    }
    return SizedBox(height: widget.appBar.height, child: result);
  }
}
