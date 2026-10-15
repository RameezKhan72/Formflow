import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/body_scan.dart';
import '../../domain/demo_motion.dart';
import '../../domain/exercise.dart';
import '../../domain/insights.dart' show BodyProfileResult;
import '../../domain/landmarks.dart';
import '../../services/pose_estimator.dart';
import '../../services/voice_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton_painter.dart';

/// Body Profile scan (FR-CB-01..05): front, left, right, back and T-pose,
/// each held about 3 s, with pre-checks and a quality score.
class BodyScanScreen extends ConsumerStatefulWidget {
  final bool demo;
  const BodyScanScreen({super.key, this.demo = false});

  @override
  ConsumerState<BodyScanScreen> createState() => _BodyScanScreenState();
}

class _BodyScanScreenState extends ConsumerState<BodyScanScreen> {
  static const holdSeconds = 3.0;
  final Map<ScanStep, List<BodyPose>> _captures = {};
  int _step = -1; // -1 intro, 5 = result
  double _held = 0;
  String? _instruction;
  BodyPose? _pose;
  BodyProfileResult? _result;
  late bool _demo = widget.demo;
  Timer? _demoTimer;
  CameraController? _cam;
  MlKitPoseEstimator? _est;
  bool _busy = false;
  double _brightness = 1;
  DateTime _last = DateTime.now();
  final _voice = VoiceService.system();

  @override
  void dispose() {
    _demoTimer?.cancel();
    _stopCamera();
    _est?.close();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _step = 0;
      _held = 0;
      _captures.clear();
    });
    _voice.speak(ScanStep.values[0].prompt);
    if (_demo) {
      _demoTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _onPose(_demoPose(), 0.1));
      return;
    }
    try {
      final cams = await availableCameras();
      final cam = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      final ctrl = CameraController(cam, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await ctrl.initialize();
      _est = MlKitPoseEstimator();
      await ctrl.startImageStream((img) async {
        if (_busy) return;
        _busy = true;
        try {
          _brightness = MlKitPoseEstimator.brightness(img);
          final p = await _est!.estimate(img, cam, ctrl.value.deviceOrientation);
          final now = DateTime.now();
          final dt = now.difference(_last).inMilliseconds / 1000;
          _last = now;
          if (mounted) _onPose(p, dt.clamp(0, 0.5).toDouble());
        } catch (_) {
        } finally {
          _busy = false;
        }
      });
      if (mounted) setState(() => _cam = ctrl);
    } catch (_) {
      if (mounted) {
        setState(() => _demo = true);
        _demoTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _onPose(_demoPose(), 0.1));
      }
    }
  }

  BodyPose _demoPose() {
    final step = ScanStep.values[_step.clamp(0, 4)];
    final t = step == ScanStep.tPose ? 92.0 : 172.0;
    final kf = Keyframes(view: 'front', anchorX: 0.5, start: {'upperArm': t, 'forearm': t}, end: {'upperArm': t, 'forearm': t});
    return SyntheticPose.fromMannequin(MannequinRig.solve(kf, 0));
  }

  Future<void> _stopCamera() async {
    final c = _cam;
    _cam = null;
    try {
      if (c != null && c.value.isStreamingImages) await c.stopImageStream();
      await c?.dispose();
    } catch (_) {}
  }

  void _onPose(BodyPose? p, double dt) {
    if (_step < 0 || _step > 4) return;
    final instr = BodyScan.precheck(p, brightness: _brightness);
    setState(() {
      _pose = p;
      _instruction = instr;
      if (instr == null && p != null) {
        _held += dt;
        _captures.putIfAbsent(ScanStep.values[_step], () => []).add(p);
      } else {
        _held = 0;
      }
    });
    if (_held >= holdSeconds) {
      _held = 0;
      if (_step < 4) {
        setState(() => _step++);
        _voice.speak(ScanStep.values[_step].prompt);
      } else {
        _finish();
      }
    }
  }

  void _finish() {
    _demoTimer?.cancel();
    _stopCamera();
    final r = BodyScan.compute(_captures);
    setState(() {
      _step = 5;
      _result = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final existing = app.data.bodyProfile;
    return Scaffold(
      appBar: AppBar(title: const Text('Body Profile scan')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _step < 0
            ? ListView(children: [
                const Text(
                  'A 15-second calibration: hold five poses so FormFlow can measure your limb proportions. '
                  'It does not retrain the model and the result stays on this phone.',
                  style: TextStyle(color: FF.muted),
                ),
                const SizedBox(height: 16),
                ...ScanStep.values.map((s) => ListTile(leading: const Icon(Icons.radio_button_unchecked), title: Text(s.prompt))),
                if (existing != null)
                  Card(
                    child: ListTile(
                      title: Text('Current profile: quality ${existing.quality}/100'),
                      subtitle: Text('Symmetry ${existing.symmetry.round()}%'),
                      trailing: TextButton(onPressed: () => app.deleteBodyProfile(), child: const Text('Delete')),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _start, child: Text(existing == null ? 'Start scan' : 'Recalibrate')),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _demo = true);
                    _start();
                  },
                  child: const Text('Try in Demo mode'),
                ),
              ])
            : _step <= 4
                ? Column(children: [
                    Expanded(
                      child: Stack(children: [
                        if (_cam != null && !_demo)
                          Positioned.fill(child: CameraPreview(_cam!))
                        else
                          Positioned.fill(child: Container(color: const Color(0xFF10142C))),
                        Positioned.fill(child: CustomPaint(painter: SkeletonPainter(pose: _pose, mirror: !_demo, labels: true))),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    ProgressRing(
                      value: (_step + _held / holdSeconds) / 5,
                      size: 80,
                      child: Text('${_step + 1}/5', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 8),
                    Text(ScanStep.values[_step].prompt, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    if (_instruction != null) Text(_instruction!, style: const TextStyle(color: FF.warn)),
                  ])
                : _resultView(app),
      ),
    );
  }

  Widget _resultView(AppController app) {
    final r = _result!;
    final good = r.quality >= 60;
    return ListView(children: [
      Center(
        child: ProgressRing(
          value: r.quality / 100,
          size: 140,
          stroke: 12,
          color: good ? FF.good : FF.warn,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${r.quality}', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
            const Text('quality', style: TextStyle(color: FF.muted)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Text('Symmetry ${r.symmetry.round()}%', textAlign: TextAlign.center),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Ratios (relative to torso)',
        child: Column(
          children: r.ratios.entries
              .map((e) => Row(children: [Expanded(child: Text(e.key.replaceAll('_', ' '))), Text(e.value.toStringAsFixed(2))]))
              .toList(),
        ),
      ),
      if (!good) ...[
        const SizedBox(height: 12),
        ...r.problems.map((p) => ListTile(leading: const Icon(Icons.info_outline, color: FF.warn), title: Text(p))),
      ],
      const SizedBox(height: 16),
      if (good)
        FilledButton(
          onPressed: () {
            app.saveBodyProfile(r);
            Navigator.pop(context);
          },
          child: const Text('Save profile'),
        )
      else
        FilledButton(onPressed: _start, child: const Text('Retry')),
      const SizedBox(height: 8),
      const Text('Tolerance adjustments from this profile stay off until validated in the Lab.',
          textAlign: TextAlign.center, style: TextStyle(color: FF.muted, fontSize: 12)),
    ]);
  }
}

