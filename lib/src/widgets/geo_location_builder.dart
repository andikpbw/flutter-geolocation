import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/geo_exception.dart';
import '../core/geo_position.dart';
import '../core/geo_settings.dart';
import '../engine/geo_controller.dart';
import '../flutter_geolocation_client.dart';

/// Builder callback invoked with a live [GeoPosition].
typedef GeoPositionWidgetBuilder =
    Widget Function(BuildContext context, GeoPosition position);

/// Builder callback invoked when a [GeoException] occurs.
typedef GeoErrorWidgetBuilder =
    Widget Function(BuildContext context, GeoException error);

/// Reactive widget that subscribes to either a [GeoController] or
/// [FlutterGeolocation.positionStream] and rebuilds automatically on each fix.
///
/// Built purely on `package:flutter/widgets.dart`.
class GeoLocationBuilder extends StatefulWidget {
  /// Creates a [GeoLocationBuilder].
  ///
  /// Supply [controller] to share state across multiple widgets, or omit it to
  /// automatically open a managed position stream using [settings].
  const GeoLocationBuilder({
    required this.builder,
    super.key,
    this.controller,
    this.settings = const GeoSettings(),
    this.loadingBuilder,
    this.errorBuilder,
  });

  /// Optional external [GeoController] to observe.
  final GeoController? controller;

  /// Stream settings used when [controller] is `null`.
  final GeoSettings settings;

  /// Builds UI once a valid [GeoPosition] is available.
  final GeoPositionWidgetBuilder builder;

  /// Optional widget shown while waiting for the first position fix.
  final WidgetBuilder? loadingBuilder;

  /// Optional widget shown when a [GeoException] occurs.
  final GeoErrorWidgetBuilder? errorBuilder;

  @override
  State<GeoLocationBuilder> createState() => _GeoLocationBuilderState();
}

class _GeoLocationBuilderState extends State<GeoLocationBuilder> {
  StreamSubscription<GeoPosition>? _subscription;
  GeoPosition? _streamPosition;
  GeoException? _streamError;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _subscribe();
    }
  }

  @override
  void didUpdateWidget(covariant GeoLocationBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        (widget.controller == null && oldWidget.settings != widget.settings)) {
      unawaited(_subscription?.cancel());
      _subscription = null;
      if (widget.controller == null) {
        _subscribe();
      }
    }
  }

  void _subscribe() {
    _streamError = null;
    _subscription = FlutterGeolocation.positionStream(settings: widget.settings)
        .listen(
          (GeoPosition pos) {
            if (!mounted) return;
            setState(() {
              _streamPosition = pos;
              _streamError = null;
            });
          },
          onError: (Object err) {
            if (!mounted) return;
            setState(() {
              _streamError = err is GeoException
                  ? err
                  : GeoUnknownException(err.toString(), cause: err);
            });
          },
        );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Widget _buildContent(
    BuildContext context,
    GeoPosition? position,
    GeoException? error,
  ) {
    if (error != null && position == null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, error);
      }
      return Text(error.message);
    }
    if (position == null) {
      if (widget.loadingBuilder != null) {
        return widget.loadingBuilder!(context);
      }
      return const SizedBox.shrink();
    }
    return widget.builder(context, position);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller != null) {
      return ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? _) {
          return _buildContent(context, controller.position, controller.error);
        },
      );
    }
    return _buildContent(context, _streamPosition, _streamError);
  }
}
