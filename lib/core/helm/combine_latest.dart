import 'dart:async';

/// Combines several streams into one that emits the latest value of each
/// as a list, every time any of them emits, once all have emitted at
/// least once. Small and local so the planning rail can fold six
/// register streams into one horizon without a reactive-extensions
/// dependency. Cancels all sources when the listener goes away.
Stream<List<T>> combineLatest<T>(List<Stream<T>> sources) {
  if (sources.isEmpty) return Stream.value(const []);
  late StreamController<List<T>> controller;
  final subs = <StreamSubscription<T>>[];
  final latest = List<T?>.filled(sources.length, null);
  final seen = List<bool>.filled(sources.length, false);

  void emitIfReady() {
    if (seen.every((s) => s)) {
      controller.add(List<T>.from(latest.cast<T>()));
    }
  }

  controller = StreamController<List<T>>(
    onListen: () {
      for (var i = 0; i < sources.length; i++) {
        subs.add(sources[i].listen((v) {
          latest[i] = v;
          seen[i] = true;
          emitIfReady();
        }, onError: controller.addError));
      }
    },
    onCancel: () {
      // Fire-and-forget: awaiting a Drift query stream's cancel here made
      // the listener's dispose hang inside the widget-test zone.
      for (final s in subs) {
        s.cancel();
      }
      subs.clear();
    },
  );
  return controller.stream;
}
