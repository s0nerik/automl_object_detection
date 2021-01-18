import 'dart:async';

import 'package:automl_object_detection/automl_object_detection.dart';
import 'package:camera2/camera2.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({Key key}) : super(key: key);

  static const path = '/analysis_screen';

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: _Body(),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({
    Key key,
  }) : super(key: key);

  @override
  __BodyState createState() => __BodyState();
}

class __BodyState extends State<_Body> {
  CameraPreviewController _ctrl;

  var _hasPermission = false;

  var _fps = 0.0;
  var _requestImageDurationMs = 0.0;
  var _processImageDurationMs = 0.0;

  var _detectedObjects = const <AutoMLObject>[];

  static const _bitmapWidth = 192.0;
  static const _bitmapHeight = 192.0;
  static const _centerCropAspectRatio = 3.0 / 2.0;
  static const _centerCropWidthPercent = 0.9;

  final _detector = AutoMLObjectDetector(
    bitmapSize: const Size(_bitmapWidth, _bitmapHeight),
    enableMultipleObjects: true,
  );

  @override
  void initState() {
    super.initState();
    _detector.init();
    _runDetection();
  }

  @override
  void dispose() {
    _detector.dispose();
    super.dispose();
  }

  Future<void> _runDetection() async {
    final permissionStatus = await Permission.camera.request();
    if (permissionStatus == PermissionStatus.granted) {
      _hasPermission = true;
      if (mounted) {
        setState(() {});
      }
    }

    final stopwatch = Stopwatch();
    var totalPasses = 0;

    final reqImageStopwatch = Stopwatch();
    var totalRequests = 0;

    final processImageStopwatch = Stopwatch();
    var totalProcesses = 0;

    while (mounted) {
      if (_ctrl == null) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      stopwatch.start();

      reqImageStopwatch.start();
      final imageBytes = await _ctrl.requestImageForAnalysis();
      reqImageStopwatch.stop();
      totalRequests++;
      _requestImageDurationMs =
          reqImageStopwatch.elapsedMilliseconds / totalRequests;

      if (imageBytes != null) {
        try {
          processImageStopwatch.start();
          final results = await _detector.process(imageBytes);
          processImageStopwatch.stop();
          _detectedObjects = results;
          totalProcesses++;
          _processImageDurationMs =
              processImageStopwatch.elapsedMilliseconds / totalProcesses;
        } catch (e) {
          debugPrint(e.toString());
        }
      } else {
        totalPasses = 0;
        stopwatch.stop();
        stopwatch.reset();
      }

      stopwatch.stop();
      totalPasses += 1;
      _fps = totalPasses / stopwatch.elapsedMilliseconds * 1000;

      if (mounted) {
        setState(() {});
      }
    }
    stopwatch.stop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 240,
            alignment: Alignment.topCenter,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  children: [
                    Text(
                      'FPS: ${_fps.toStringAsFixed(1)}, '
                      'REQUEST: ${_requestImageDurationMs.toStringAsFixed(1)}, '
                      'PROCESS: ${_processImageDurationMs.toStringAsFixed(1)}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _hasPermission ? _buildPreview() : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildObjectBoxes() {
    final previewWidth =
        MediaQuery.of(context).size.width * _centerCropWidthPercent;
    final widthRatio = _bitmapWidth / previewWidth;
    final previewHeight = previewWidth / _centerCropAspectRatio;
    final heightRatio = _bitmapHeight / previewHeight;
    return SizedBox(
      width: previewWidth,
      child: AspectRatio(
        aspectRatio: _centerCropAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (final obj in _detectedObjects)
              Positioned(
                left: obj.boundingBox.left / widthRatio,
                top: obj.boundingBox.top / heightRatio,
                width: obj.boundingBox.width / widthRatio,
                height: obj.boundingBox.height / heightRatio,
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border.fromBorderSide(
                      BorderSide(
                        color: Colors.green,
                        width: 2,
                      ),
                    ),
                  ),
                  alignment: Alignment.topLeft,
                  child: Text(
                    obj.trackingId.toString(),
                    style: TextStyle(
                      color: Colors.white,
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Stack(
      children: [
        Positioned.fill(
          child: Camera2Preview(
            analysisOptions: const Camera2AnalysisOptions(
              imageSize: const Size(_bitmapWidth, _bitmapHeight),
              colorOrder: ColorOrder.rgb,
              normalization: Normalization.ubyte,
              centerCropWidthPercent: _centerCropWidthPercent,
              centerCropAspectRatio: _centerCropAspectRatio,
            ),
            onPlatformViewCreated: (ctrl) => _ctrl = ctrl,
          ),
        ),
        Center(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * _centerCropWidthPercent,
            child: AspectRatio(
              aspectRatio: _centerCropAspectRatio,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red),
                ),
              ),
            ),
          ),
        ),
        Center(
          child: _buildObjectBoxes(),
        ),
      ],
    );
  }
}
