library extendableappbar;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:extendableappbar/src/extendableappbar_will_pop_scope.dart';
import 'package:extendableappbar/src/utils.dart';

export 'package:extendableappbar/src/extendableappbar_will_pop_scope.dart';

///Type definition for the builder function
typedef Widget ExtendableAppBarBuilder(double height, double percentage);

///Type definition for onDismiss. Will be used in a future version.
typedef void DismissCallback(double percentage);

///ExtandableAppBar class
class ExtendableAppBar extends StatefulWidget {
  ///Required option to set the minimum and maximum height
  final double minHeight, maxHeight;

  ///Option to enable and set elevation for the extendableappbar
  final double elevation;

  ///Central API-Element
  ///Provides a builder with useful information
  final ExtendableAppBarBuilder builder;

  ///Option to set the animation curve
  final Curve curve;

  ///Sets the background-color of the extendableappbar
  final Color? backgroundColor;

  ///Option to set the animation duration
  final Duration duration;

  ///Allows you to use a global ValueNotifier with the current progress.
  ///This can be used to hide the BottomNavigationBar.
  final ValueNotifier<double>? valueNotifier;

  ///Deprecated
  @Deprecated(
      "Migrate onDismiss to onDismissed as onDismiss will be used differently in a future version.")
  final Function? onDismiss;

  ///If onDismissed is set, the extendableappbar can be dismissed
  final Function? onDismissed;

  //Allows you to manually control the extendableappbar in code
  final ExtendableAppBarController? controller;

  ///Used to set the color of the background box shadow
  final Color backgroundBoxShadow;
  final Alignment alignment;

  const ExtendableAppBar({
    Key? key,
    required this.minHeight,
    required this.maxHeight,
    required this.builder,
    this.curve = Curves.easeOut,
    this.elevation = 0,
    this.backgroundColor,
    this.valueNotifier,
    this.duration = const Duration(milliseconds: 300),
    this.onDismiss,
    this.onDismissed,
    this.controller,
    this.backgroundBoxShadow = Colors.black45,
    this.alignment = Alignment.bottomCenter,
  }) : super(key: key);

  @override
  _ExtendableAppBarState createState() => _ExtendableAppBarState();
}

class _ExtendableAppBarState extends State<ExtendableAppBar> with TickerProviderStateMixin {
  late ValueNotifier<double> heightNotifier;
  ValueNotifier<double> dragUpPercentage = ValueNotifier(0);

  ///Temporary variable as long as onDismiss is deprecated. Will be removed in a future version.
  Function? onDismissed;

  ///Current y position of drag gesture
  late double _dragHeight;

  ///Used to determine SnapPosition
  late double _startHeight;

  bool dismissed = false;

  bool animating = false;

  ///Counts how many updates were required for a distance (onPanUpdate) -> necessary to calculate the drag speed
  int updateCount = 0;

  StreamController<double> _heightController =
      StreamController<double>.broadcast();
  AnimationController? _animationController;

  void _statusListener(AnimationStatus status) {
    if (status == AnimationStatus.completed) _resetAnimationController();
  }

  void _resetAnimationController({Duration? duration}) {
    if (_animationController != null) {
      _animationController!.dispose();
    }
    _animationController = AnimationController(
      vsync: this,
      duration: duration ?? widget.duration,
    );
    _animationController!.addStatusListener(_statusListener);
    animating = false;
  }

  @override
  void initState() {
    if (widget.valueNotifier == null) {
      heightNotifier = ValueNotifier(widget.minHeight);
    } else {
      heightNotifier = widget.valueNotifier!;
    }

    _resetAnimationController();

    _dragHeight = heightNotifier.value;

    if (widget.controller != null) {
      widget.controller!.addListener(controllerListener);
    }

    if (widget.onDismissed != null) {
      onDismissed = widget.onDismissed;
    } else {
      // ignore: deprecated_member_use_from_same_package
      onDismissed = widget.onDismiss;
    }

    super.initState();
  }

  @override
  void dispose() {
    _heightController.close();

    if (_animationController != null) {
      _animationController!.dispose();
    }

    if (widget.controller != null) {
      widget.controller!.removeListener(controllerListener);
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (dismissed) {
      return Container();
    }

    return ExtendableAppBarWillPopScope(
      onWillPop: () async {
        if (heightNotifier.value > widget.minHeight) {
          _snapToPosition(PanelState.MIN);
          return false;
        }
        return true;
      },
      child: ValueListenableBuilder(
        valueListenable: heightNotifier,
        builder: (BuildContext context, double height, Widget? _) {
          var _percentage = ((height - widget.minHeight)) /
              (widget.maxHeight - widget.minHeight);

          return Stack(
            alignment: widget.alignment,
            children: [
              if (_percentage > 0)
                GestureDetector(
                  onTap: () => _animateToHeight(widget.minHeight),
                  child: Opacity(
                    opacity: borderDouble(
                        minRange: 0.0, maxRange: 1.0, value: _percentage),
                    child: Container(color: widget.backgroundColor),
                  ),
                ),
              Align(
                alignment: widget.alignment,
                child: SizedBox(
                  height: height,
                  child: GestureDetector(
                    child: ValueListenableBuilder(
                      valueListenable: dragUpPercentage,
                      builder:
                          (BuildContext context, double value, Widget? child) {
                        return Opacity(
                          opacity: borderDouble(
                              minRange: 0.0,
                              maxRange: 1.0,
                              value: 1 - value * 0.8),
                          child: Transform.translate(
                            offset: Offset(0.0, widget.minHeight * value * 0.5),
                            child: child,
                          ),
                        );
                      },
                      child: Material(
                        child: Container(
                          constraints: BoxConstraints.expand(),
                          child: widget.builder(height, _percentage),
                          decoration: BoxDecoration(
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                  color: widget.backgroundBoxShadow,
                                  blurRadius: widget.elevation,
                                  offset: Offset(0.0, 4))
                            ],
                            color: widget.backgroundColor ??
                                Theme.of(context).scaffoldBackgroundColor,
                          ),
                        ),
                      ),
                    ),
                    onTap: () => _snapToPosition(_dragHeight != widget.maxHeight
                        ? PanelState.MAX
                        : PanelState.MIN),
                    onPanStart: (details) {
                      _startHeight = _dragHeight;
                      updateCount = 0;

                      if (animating) {
                        _resetAnimationController();
                      }
                    },
                    onPanEnd: (details) async {
                      ///Calculates drag speed
                      double speed = (_dragHeight - _startHeight * _dragHeight <
                                  _startHeight
                              ? 1
                              : -1) /
                          updateCount *
                          100;

                      ///Define the percentage distance depending on the speed with which the widget should snap
                      double snapPercentage = 0.005;
                      if (speed <= 4) {
                        snapPercentage = 0.2;
                      } else if (speed <= 9) {
                        snapPercentage = 0.08;
                      } else if (speed <= 50) {
                        snapPercentage = 0.01;
                      }

                      ///Determine to which SnapPosition the widget should snap
                      PanelState snap = PanelState.MIN;

                      final _percentageMax = percentageFromValueInRange(
                          min: widget.minHeight,
                          max: widget.maxHeight,
                          value: _dragHeight);

                      ///Started from expanded state
                      if (_startHeight > widget.minHeight) {
                        if (_percentageMax > 1 - snapPercentage) {
                          snap = PanelState.MAX;
                        }
                      }

                      ///Started from minified state
                      else {
                        if (_percentageMax > snapPercentage) {
                          snap = PanelState.MAX;
                        }

                        ///DismissedPercentage > 0.2 -> dismiss
                        else if (onDismissed != null &&
                            percentageFromValueInRange(
                                  min: widget.minHeight,
                                  max: 0,
                                  value: _dragHeight,
                                ) >
                                snapPercentage) {
                          snap = PanelState.DISMISS;
                        }
                      }

                      ///Snap to position
                      _snapToPosition(snap);
                    },
                    onPanUpdate: (details) {
                      if (dismissed) return;

                      _dragHeight -= details.delta.dy;
                      updateCount++;

                      _handleHeightChange();
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  ///Determines whether the panel should be updated in height or discarded
  void _handleHeightChange({bool animation = false}) {
    ///Drag above minHeight
    if (_dragHeight >= widget.minHeight) {
      if (dragUpPercentage.value != 0) {
        dragUpPercentage.value = 0;
      }
      print("Troubling: hit");

      if (_dragHeight > widget.maxHeight) return;

      heightNotifier.value = _dragHeight;
    }

    ///Drag below minHeight
    else if (onDismissed != null) {
      final percentageDown = borderDouble(
          minRange: 0.0,
          maxRange: 1.0,
          value: percentageFromValueInRange(
              min: widget.minHeight, max: 0, value: _dragHeight));

      if (dragUpPercentage.value != percentageDown) {
        dragUpPercentage.value = percentageDown;
      }

      if (percentageDown >= 1 && animation && !dismissed) {
        if (onDismissed != null) {
          onDismissed!();
        }
        setState(() => dismissed = true);
      }
    }
  }

  ///Animates the panel height according to a SnapPoint
  void _snapToPosition(PanelState snapPosition) {
    switch (snapPosition) {
      case PanelState.MAX:
        _animateToHeight(widget.maxHeight);
        return;
      case PanelState.MIN:
        _animateToHeight(widget.minHeight);
        return;
      case PanelState.DISMISS:
        _animateToHeight(0);
        return;
    }
  }

  ///Animates the panel height to a specific value
  void _animateToHeight(final double h, {Duration? duration}) {
    if (_animationController == null) return;
    final startHeight = _dragHeight;

    if (duration != null) {
      _resetAnimationController(duration: duration);
    }

    Animation<double> _sizeAnimation = Tween(
      begin: startHeight,
      end: h,
    ).animate(
        CurvedAnimation(parent: _animationController!, curve: widget.curve));

    _sizeAnimation.addListener(() {
      if (_sizeAnimation.value == startHeight) return;

      _dragHeight = _sizeAnimation.value;

      _handleHeightChange(animation: true);
    });

    animating = true;
    _animationController!.forward(from: 0);
  }

  //Listener function for the controller
  void controllerListener() {
    if (widget.controller == null) return;
    if (widget.controller!.value == null) return;

    switch (widget.controller!.value!.height) {
      case -1:
        _animateToHeight(
          widget.minHeight,
          duration: widget.controller!.value!.duration,
        );
        break;
      case -2:
        _animateToHeight(
          widget.maxHeight,
          duration: widget.controller!.value!.duration,
        );
        break;
      case -3:
        _animateToHeight(
          0,
          duration: widget.controller!.value!.duration,
        );
        break;
      default:
        _animateToHeight(
          widget.controller!.value!.height.toDouble(),
          duration: widget.controller!.value!.duration,
        );
        break;
    }
  }
}

///-1 Min, -2 Max, -3 Dismiss
enum PanelState { MAX, MIN, DISMISS }

//ControllerData class. Used for the controller
class ControllerData {
  final int height;
  final Duration? duration;

  const ControllerData(this.height, this.duration);
}

//ExtendableAppBarController class
class ExtendableAppBarController extends ValueNotifier<ControllerData?> {
  ExtendableAppBarController() : super(null);

  //Animates to a given height or state(expanded, dismissed, ...)
  void animateToHeight(
      {double? height, PanelState? state, Duration? duration}) {
    if (height == null && state == null) {
      throw ("ExtendableAppBar: One of the two parameters, height or status, is required.");
    }

    if (height != null && state != null) {
      throw ("ExtendableAppBar: Only one of the two parameters, height or status, can be specified.");
    }

    ControllerData? valBefore = value;

    if (state != null) {
      value = ControllerData(state.heightCode, duration);
    } else {
      if (height! < 0) return;

      value = ControllerData(height.round(), duration);
    }

    if (valBefore == value) {
      notifyListeners();
    }
  }
}
