import 'dart:typed_data';

enum BatchItemStatus {
  pending,
  processing,
  completed,
  failed,
}

class BatchItem {
  final String id;
  final Uint8List inputBytes;
  Uint8List? outputBytes;
  int? inputWidth;
  int? inputHeight;
  Duration? duration;
  BatchItemStatus status;
  double progress;
  String? error;

  BatchItem({
    required this.id,
    required this.inputBytes,
    this.outputBytes,
    this.inputWidth,
    this.inputHeight,
    this.duration,
    this.status = BatchItemStatus.pending,
    this.progress = 0.0,
    this.error,
  });
}
