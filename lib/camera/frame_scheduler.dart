class FrameScheduler {
  bool _isBusy = false;
  final Duration minFrameInterval;
  DateTime? _lastCompletion;

  FrameScheduler({
    this.minFrameInterval = const Duration(milliseconds: 100), // ~10 FPS max AI
  });

  /// Evaluates whether the incoming camera frame should be processed or dropped
  bool shouldProcessFrame() {
    if (_isBusy) return false;
    final completion = _lastCompletion;
    if (completion != null && DateTime.now().difference(completion) < minFrameInterval) {
      return false;
    }
    return true;
  }

  void markBusy() {
    _isBusy = true;
  }

  /// Marks the cycle as finished. [minFrameInterval] is measured from *this*
  /// point (not from [markBusy]) — a heavy cycle (e.g. ~3.6s of YOLO
  /// inference) shouldn't itself count as the cooldown; the cooldown is idle
  /// time deliberately left afterward for other concurrent work (MediaPipe's
  /// hand tracking) to get uninterrupted CPU access.
  void markFree() {
    _isBusy = false;
    _lastCompletion = DateTime.now();
  }

  void reset() {
    _isBusy = false;
    _lastCompletion = null;
  }
}
