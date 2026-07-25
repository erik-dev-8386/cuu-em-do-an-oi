class FrameScheduler {
  bool _isBusy = false;
  final Duration minFrameInterval;
  DateTime _lastExecution = DateTime.now();

  FrameScheduler({
    this.minFrameInterval = const Duration(milliseconds: 100), // ~10 FPS max AI
  });

  /// Evaluates whether the incoming camera frame should be processed or dropped
  bool shouldProcessFrame() {
    if (_isBusy) return false;
    final now = DateTime.now();
    if (now.difference(_lastExecution) < minFrameInterval) {
      return false;
    }
    return true;
  }

  void markBusy() {
    _isBusy = true;
    _lastExecution = DateTime.now();
  }

  void markFree() {
    _isBusy = false;
  }

  void reset() {
    _isBusy = false;
    _lastExecution = DateTime.now();
  }
}
