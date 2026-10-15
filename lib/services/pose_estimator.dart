
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart' as mlkit;

import '../domain/landmarks.dart';

/// Pose detection behind an interface so ML Kit, MediaPipe or MoveNet can
/// be swapped without touching the exercise engine (FR-PE-04).
abstract class PoseEstimator {
  Future<BodyPose?> estimate(CameraImage image, CameraDescription camera, DeviceOrientation orientation);
  Future<void> close();
}

/// Google ML Kit Pose Detection: 33 BlazePose landmarks, bundled model,
/// fully offline (FR-PE-03). Only the light "base" model is bundled; the
/// "accurate" model file is stripped from the APK by tool/patch_android.py.
class MlKitPoseEstimator implements PoseEstimator {
  final mlkit.PoseDetector _detector;

  MlKitPoseEstimator({bool accurate = false})
      : _detector = mlkit.PoseDetector(
          options: mlkit.PoseDetectorOptions(
            mode: mlkit.PoseDetectionMode.stream,
            model: accurate ? mlkit.PoseDetectionModel.accurate : mlkit.PoseDetectionModel.base,
          ),
        );

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Rotation from sensor and device orientation (PRD 8.4).
  static int rotationDegrees(CameraDescription camera, DeviceOrientation orientation) {
    final sensor = camera.sensorOrientation;
    if (defaultTargetPlatform == TargetPlatform.iOS) return sensor;
    final comp = _orientations[orientation] ?? 0;
    return camera.lensDirection == CameraLensDirection.front ? (sensor + comp) % 360 : (sensor - comp + 360) % 360;
  }

  @override
  Future<BodyPose?> estimate(CameraImage image, CameraDescription camera, DeviceOrientation orientation) async {
    final rotDeg = rotationDegrees(camera, orientation);
    final rotation = mlkit.InputImageRotationValue.fromRawValue(rotDeg) ?? mlkit.InputImageRotation.rotation0deg;
    final format = mlkit.InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final input = mlkit.InputImage.fromBytes(
      bytes: image.planes.length == 1 ? plane.bytes : _concat(image),
      metadata: mlkit.InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
    final poses = await _detector.processImage(input);
    if (poses.isEmpty) return null;

    // Several people: track the largest (FR-PE-11).
    mlkit.Pose best = poses.first;
    double bestArea = -1;
    for (final p in poses) {
      double minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
      for (final l in p.landmarks.values) {
        if (l.x < minX) minX = l.x;
        if (l.x > maxX) maxX = l.x;
        if (l.y < minY) minY = l.y;
        if (l.y > maxY) maxY = l.y;
      }
      final a = (maxX - minX) * (maxY - minY);
      if (a > bestArea) {
        bestArea = a;
        best = p;
      }
    }

    final rotated = rotDeg == 90 || rotDeg == 270;
    final w = rotated ? image.height.toDouble() : image.width.toDouble();
    final h = rotated ? image.width.toDouble() : image.height.toDouble();
    final aspect = w / h;
    final out = List<Landmark>.filled(LandmarkId.values.length, const Landmark(0, 0, confidence: 0));
    best.landmarks.forEach((type, l) {
      final i = type.index;
      if (i < out.length) {
        // x scaled by height so angles stay true: x in [0, aspect], y in [0, 1]
        out[i] = Landmark(l.x / h, l.y / h, z: l.z, confidence: l.likelihood);
      }
    });
    return BodyPose(out, aspect: aspect);
  }

  static Uint8List _concat(CameraImage image) {
    final b = WriteBuffer();
    for (final p in image.planes) {
      b.putUint8List(p.bytes);
    }
    return b.done().buffer.asUint8List();
  }

  @override
  Future<void> close() => _detector.close();

  /// Average luma of the Y plane, 0..1, for the lighting check.
  static double brightness(CameraImage image) {
    final bytes = image.planes.first.bytes;
    if (bytes.isEmpty) return 1;
    var sum = 0;
    var n = 0;
    final limit = image.width * image.height;
    for (var i = 0; i < limit && i < bytes.length; i += 97) {
      sum += bytes[i];
      n++;
    }
    return n == 0 ? 1 : sum / n / 255;
  }
}
