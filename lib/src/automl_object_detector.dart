import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('dev.sonerik.automl_object_detection');

@immutable
class AutoMLObject {
  const AutoMLObject._({
    @required this.boundingBox,
    @required this.trackingId,
    @required this.labels,
  });

  final Rect boundingBox;
  final int trackingId;
  final List<AutoMLLabel> labels;

  @override
  String toString() {
    return '$trackingId:$boundingBox:$labels';
  }
}

@immutable
class AutoMLLabel {
  const AutoMLLabel._({
    @required this.index,
    @required this.text,
    @required this.confidence,
  });

  final int index;
  final String text;
  final double confidence;

  @override
  String toString() {
    return '($text:${confidence.toStringAsFixed(2)})';
  }
}

class AutoMLObjectDetector {
  AutoMLObjectDetector({
    @required this.bitmapSize,
    this.enableClassification = false,
    this.enableMultipleObjects = false,
  })  : assert(bitmapSize != null),
        assert(enableClassification != null),
        assert(enableMultipleObjects != null);

  /// Usually is 192x192
  final Size bitmapSize;
  final bool enableClassification;
  final bool enableMultipleObjects;

  final _idCompleter = Completer<int>();

  Future<void> init() async {
    try {
      final id = await _channel.invokeMethod('prepareDetector', {
        'bitmapWidth': bitmapSize.width.toInt(),
        'bitmapHeight': bitmapSize.height.toInt(),
        'enableClassification': enableClassification,
        'enableMultipleObjects': enableMultipleObjects,
      });
      _idCompleter.complete(id);
    } catch (e, stackTrace) {
      _idCompleter.completeError(e, stackTrace);
      rethrow;
    }
  }

  Future<List<AutoMLObject>> process(Uint8List rgbBytes) async {
    final id = await _idCompleter.future;
    final results = await _channel.invokeMethod<List<dynamic>>('processImage', {
      'detectorId': id,
      'rgbBytes': rgbBytes,
    });

    if (results.isNotEmpty) {
      debugPrint('results.isNotEmpty');
    }

    final ret = results
        .cast<Map<dynamic, dynamic>>()
        .map((r) => AutoMLObject._(
              trackingId: r['trackingId'] as int,
              boundingBox: Rect.fromLTRB(
                r['boundingBox']['left'] as double,
                r['boundingBox']['top'] as double,
                r['boundingBox']['right'] as double,
                r['boundingBox']['bottom'] as double,
              ),
              labels: (r['labels'] as List<dynamic>)
                  .cast<Map<dynamic, dynamic>>()
                  .map(
                    (label) => AutoMLLabel._(
                      index: label['index'] as int,
                      text: label['text'] as String,
                      confidence: label['confidence'] as double,
                    ),
                  )
                  .toList(),
            ))
        .toList();

    if (results.isNotEmpty) {
      debugPrint('ret: ${ret.length}');
    }

    return ret;
  }

  Future<void> dispose() async {
    final id = await _idCompleter.future;
    await _channel.invokeMethod('disposeDetector', {
      'id': id,
    });
  }
}
