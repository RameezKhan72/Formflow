import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme.dart';
import '../../domain/demo_motion.dart';
import '../../domain/exercise.dart';
import '../../domain/guided_workout.dart';
import '../../domain/insights.dart';
import '../../domain/landmarks.dart';
import '../../domain/measurements.dart';
import '../../domain/routine.dart';
import '../../domain/rules.dart';
import '../../domain/tracking_session.dart';
import '../../services/pose_estimator.dart';
import '../../services/voice_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/mannequin.dart';
import '../../widgets/skeleton_painter.dart';
import 'summary_screen.dart';

enum RunPhase { setup, active, rest }

/// Guided workout runner: camera setup checks, live tracking, rest and
/// summary (FR-GW, FR-PE, FR-FA, FR-VF). Works with the camera (ML Kit) or
/// in Demo mode, where synthetic landmarks from the demonstrator drive the
/// same engine.
class WorkoutRunScreen extends ConsumerStatefulWidget {
  final Routine? routine;
  final GuidedWorkout? resumeFrom;
  final bool demo;
  final bool demoMistake;

  const WorkoutRunScreen({super.key, required Routine this.routine, this.demo = false, this.demoMistake = false})
      : resumeFrom = null;

  const WorkoutRunScreen.resume(GuidedWorkout this.resumeFrom, {super.key, this.demo = false, this.demoMistake = false})
      : routine = null;

  @override
  ConsumerState<WorkoutRunScreen> createState() => _WorkoutRunScreenState();
}

class _WorkoutRunScreenState extends ConsumerState<WorkoutRunScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late GuidedWorkout g;
  late CueBook cues;
  late VoiceService voice;
  RunPhase phase = RunPhase.setup;
  TrackingSession? session;
  late bool demo = widget.demo;
  late bool mistake = widget.demoMistake;
  bool muted = false;
  bool paused = false;

  // live state for the HUD (small widgets listen; no full rebuilds)
  final frame = ValueNotifier<FrameResult?>(null);
  final livePose = ValueNotifier<BodyPose?>(null);
  final demoPose = ValueNotifier<MannequinPose?>(null);
  final message = ValueNotifier<(String, bool)?>(null); // text, isGood
  final checks = ValueNotifier<Map<String, bool>>(const {});
  RepResult? lastRepForLabel;
  final lastCorrection = ValueNotifier<String?>(null);

  // timing
  final _clock = Stopwatch();
  late final Ticker _ticker;
  double _setStartT = 0;
  double _lastAnalysed = -1;
  double _readySince = -1;
  double _demoSetupSince = -1;
  Timer? _autosave;
  Timer? _restTimer;
  Timer? _messageTimer;
  int restLeft = 0;
  int restTotal = 0;

  // camera
  CameraController? _cam;
  PoseEstimator? _estimator;
  bool _busy = false;
  String? cameraError;
  double _brightness = 1;
  Vec2Like? _lastShoulder;
  double _steadyScore = 1;

  ExerciseDef get def => ref.read(appProvider).catalog.byId(g.current.exerciseId)!;

  /// Upper-body exercises only need head to hips in view, from about 1 m.
  String get _inViewLabel => def.isUpperBody ? 'Upper body in frame' : 'Full body in frame';
  String get _distanceLabel {
    final m = def.cameraDistance;
    return 'Distance about ${m == m.roundToDouble() ? m.round() : m.toStringAsFixed(1)} m';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final r = widget.routine;
    g = widget.resumeFrom ??
        GuidedWorkout(routineName: r!.name, items: List.of(r.items), startedAt: appClock());
    final app = ref.read(appProvider);
    cues = CueBook(app.catalog.cues);
    voice = VoiceService.system(enabled: app.settings.voice, haptics: app.settings.haptics, volume: app.settings.volume);
    _ticker = createTicker(_onTick)..start();
    _clock.start();
    _autosave = Timer.periodic(const Duration(seconds: 30), (_) => _save());
    WakelockPlus.enable().catchError((Object _) {});
    if (!demo) _startCamera();
    voice.speak(cues.text('warmup'), cueId: 'warmup');
    _enterSetup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _autosave?.cancel();
    _restTimer?.cancel();
    _messageTimer?.cancel();
    _stopCamera();
    voice.stop();
    WakelockPlus.disable().catchError((Object _) {});
    frame.dispose();
    livePose.dispose();
    demoPose.dispose();
    message.dispose();
    checks.dispose();
    lastCorrection.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release the camera in the background and save state (FR-PE-12, FR-GW-09).
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _save();
      if (!demo) _stopCamera();
    } else if (state == AppLifecycleState.resumed && !demo && _cam == null) {
      _startCamera();
    }
  }

  double get _now => _clock.elapsedMicroseconds / 1e6;

  void _save() {
    if (!mounted) return;
    ref.read(appProvider).saveResume(g.toJson());
  }

  // ---------------- camera ----------------
  Future<void> _startCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'No camera found');
      final front = ref.read(appProvider).settings.frontCamera;
      final cam = cams.firstWhere(
        (c) => c.lensDirection == (front ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => cams.first,
      );
      final ctrl = CameraController(cam, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await ctrl.initialize();
      // The lite ("base") model is the only one bundled, to keep the APK small.
      _estimator ??= MlKitPoseEstimator();
      await ctrl.startImageStream((img) => _onImage(img, cam, ctrl));
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _cam = ctrl;
        cameraError = null;
      });
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => cameraError = e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt'
            ? 'Camera permission was denied. Allow it in Settings > Apps > FormFlow > Permissions, or use Demo mode.'
            : 'The camera could not start (${e.description ?? e.code}). You can use Demo mode instead.');
      }
    } catch (e) {
      if (mounted) setState(() => cameraError = 'The camera or pose model is unavailable on this device. Use Demo mode instead.');
    }
  }

  Future<void> _stopCamera() async {
    final c = _cam;
    _cam = null;
    try {
      if (c != null && c.value.isStreamingImages) await c.stopImageStream();
      await c?.dispose();
    } catch (_) {}
  }

  Future<void> _onImage(CameraImage img, CameraDescription cam, CameraController ctrl) async {
    final tier = ref.read(appProvider).data.tier;
    final t = _now;
    // Analyse only the latest frame; drop frames while busy; cap FPS (FR-PE-09).
    if (_busy || paused || t - _lastAnalysed < 1 / tier.fps) return;
    _busy = true;
    _lastAnalysed = t;
    try {
      _brightness = MlKitPoseEstimator.brightness(img);
      final pose = await _estimator!.estimate(img, cam, ctrl.value.deviceOrientation);
      if (mounted) _process(pose, t);
    } catch (_) {
      // a failed frame is simply skipped
    } finally {
      _busy = false;
    }
  }

  // ---------------- per frame ----------------
  void _onTick(Duration _) {
    if (!demo || paused || g.finished) return;
    final t = _now;
    final motion = DemoMotion(def, mistake: mistake);
    final setT = t - _setStartT;
    final u = phase == RunPhase.active ? motion.u(setT) : 0.0;
    final m = MannequinRig.solve(def.keyframes, u);
    demoPose.value = m;
    final tier = ref.read(appProvider).data.tier;
    if (t - _lastAnalysed < 1 / tier.fps) return;
    _lastAnalysed = t;
    _process(SyntheticPose.fromMannequin(m), t);
  }

  void _process(BodyPose? pose, double t) {
    if (g.finished) return;
    livePose.value = pose;
    if (phase == RunPhase.setup) {
      _updateChecks(pose, t);
      return;
    }
    if (phase != RunPhase.active || session == null) return;
    final r = session!.process(pose, t);
    frame.value = r;
    if (!muted) voice.handle(r.actions);
    if (r.justPaused) _show(cues.text('step_back'), false);
    if (r.viewHint != null) _show(r.viewHint!, false);
    if (r.activeIssues.isNotEmpty) {
      final top = r.activeIssues.first;
      _show(cues.text(top.cue, side: top.side), false, hold: 1.3);
    }
    final rep = r.rep;
    if (rep != null) {
      lastRepForLabel = rep;
      if (rep.issues.isEmpty) {
        lastCorrection.value = rep.clean ? null : 'Go deeper next time';
      } else {
        final p0 = rep.issues.first.split(':');
        lastCorrection.value = cues.text(p0.first, side: p0.length > 1 ? (p0[1] == 'left' ? BodySide.left : BodySide.right) : null);
      }
      if (rep.issues.isEmpty) {
        _show(rep.clean ? 'Good rep' : 'Go deeper next time', rep.clean, hold: 1.3);
      } else {
        final parts = rep.issues.first.split(':');
        _show(cues.text(parts.first, side: parts.length > 1 ? (parts[1] == 'left' ? BodySide.left : BodySide.right) : null),
            false,
            hold: 1.3);
      }
      setState(() {});
    }
    _checkSetEnd(t);
  }

  void _show(String text, bool good, {double hold = 1.3}) {
    message.value = (text, good);
    _messageTimer?.cancel();
    _messageTimer = Timer(Duration(milliseconds: (hold * 1000).round()), () {
      if (mounted) message.value = null;
    });
  }

  // Camera setup checks before each tracked set (FR-PE-13).
  void _updateChecks(BodyPose? pose, double t) {
    var fullBody = false, distanceOk = false;
    if (pose != null) {
      final f = Measurements.framing(pose, focus: def.focus);
      fullBody = f.fullBody;
      distanceOk = f.distanceOk;
      final sh = pose.point(LandmarkId.leftShoulder) ?? pose.point(LandmarkId.rightShoulder);
      if (sh != null) {
        final prev = _lastShoulder;
        if (prev != null) {
          final move = (sh.x - prev.x).abs() + (sh.y - prev.y).abs();
          _steadyScore = 0.8 * _steadyScore + 0.2 * (move < 0.03 ? 1 : 0);
        }
        _lastShoulder = Vec2Like(sh.x, sh.y);
      }
    }
    final c = {
      _inViewLabel: fullBody,
      _distanceLabel: distanceOk,
      'Lighting': _brightness > 0.2,
      'Phone steady': _steadyScore > 0.6,
    };
    checks.value = c;
    // Demo mode has no real camera to adjust, so it never blocks the set.
    if (demo) {
      if (_demoSetupSince < 0) _demoSetupSince = t;
      if (t - _demoSetupSince > 2.5) {
        _demoSetupSince = -1;
        _startSet();
        return;
      }
    }
    if (c.values.every((v) => v)) {
      if (_readySince < 0) _readySince = t;
      if (t - _readySince > 1.0) _startSet();
    } else {
      _readySince = -1;
    }
  }

  void _enterSetup() {
    _readySince = -1;
    _demoSetupSince = -1;
    phase = RunPhase.setup;
    frame.value = null;
    if (mounted) setState(() {});
  }

  void _startSet() {
    final app = ref.read(appProvider);
    lastCorrection.value = null;
    session = TrackingSession(
      def,
      cues: cues,
      smoother: demo ? null : PoseSmoother(),
      repSpeech: app.settings.repSpeech,
      voice: app.settings.voice && !muted,
    );
    _setStartT = _now;
    phase = RunPhase.active;
    if (!muted) voice.speak('${def.name}. ${cues.text('get_ready')}', cueId: 'get_ready');
    setState(() {});
  }

  void _checkSetEnd(double t) {
    final s = session;
    if (s == null) return;
    final it = g.current;
    if (def.isTimed) {
      if (s.holdSeconds >= it.seconds) _endSet();
    } else if (s.cleanReps >= it.reps) {
      _endSet();
    }
  }

  void _endSet() {
    final s = session;
    if (s == null || phase != RunPhase.active) return;
    final elapsed = _now - _setStartT;
    if (def.isTimed) s.recordTimedResult(elapsed);
    session = null;
    if (!muted) voice.speak(cues.text('set_complete'), cueId: 'set_complete');
    final rest = g.completeSet(
      attempts: s.attempts,
      clean: s.cleanReps,
      reps: s.reps,
      seconds: s.holdSeconds.round(),
      view: frame.value?.view.name ?? 'side',
    );
    _save();
    if (rest == 0) {
      _finish();
    } else {
      _startRest(rest);
    }
  }

  void _startRest(int seconds) {
    phase = RunPhase.rest;
    restLeft = seconds;
    restTotal = seconds;
    if (!muted) {
      final next = ref.read(appProvider).catalog.byId(g.current.exerciseId);
      voice.speak('${cues.text('rest_start')}. ${cues.text('next_exercise')}: ${next?.name ?? ''}', cueId: 'rest_start');
    }
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (tm) {
      if (!mounted) return;
      if (paused) return;
      setState(() => restLeft--);
      if (restLeft <= 0) {
        tm.cancel();
        _enterSetup();
      }
    });
    setState(() {});
  }

  void _skipExercise() {
    _restTimer?.cancel();
    session = null;
    g.skipExercise();
    if (g.finished) {
      _finish();
    } else {
      _enterSetup();
    }
  }

  void _finish() {
    if (!mounted) return;
    final app = ref.read(appProvider);
    final sessionRecord = g.toSession(appClock());
    if (sessionRecord.exercises.isNotEmpty) {
      app.addSession(sessionRecord);
    } else {
      app.saveResume(null);
    }
    if (!muted) voice.speak(cues.text('cooldown'), cueId: 'cooldown');
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SummaryScreen(session: sessionRecord, justFinished: true)));
  }

  void _label(bool right) {
    final rep = lastRepForLabel;
    if (rep == null) return;
    ref.read(appProvider).addLabel(LabLabel(def.id, rep.clean, right, appClock()));
    setState(() => lastRepForLabel = null);
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    if (g.finished) return const Scaffold();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          _topBar(),
          Expanded(child: phase == RunPhase.rest ? _restView() : _trackingView(app.settings.testerMode)),
        ]),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(children: [
        IconButton(
          tooltip: 'End workout',
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('End workout?'),
                content: const Text('Your finished sets are saved.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep going')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('End')),
                ],
              ),
            );
            if (ok == true) {
              if (session != null && session!.attempts > 0) _endSetSilently();
              _finish();
            }
          },
          icon: const Icon(Icons.close),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(def.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            Text(g.label, style: const TextStyle(color: FF.muted, fontSize: 12)),
          ]),
        ),
        if (demo)
          FilterChip(
            key: const Key('demo_mistake'),
            label: const Text('Mistake'),
            selected: mistake,
            onSelected: (v) => setState(() => mistake = v),
          ),
        IconButton(
          tooltip: muted ? 'Unmute' : 'Mute',
          onPressed: () => setState(() {
            muted = !muted;
            session?.feedback.voiceEnabled = !muted;
          }),
          icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
        ),
        IconButton(
          tooltip: paused ? 'Resume' : 'Pause',
          onPressed: () => setState(() => paused = !paused),
          icon: Icon(paused ? Icons.play_arrow : Icons.pause),
        ),
      ]),
    );
  }

  void _endSetSilently() {
    final s = session;
    if (s == null) return;
    g.completeSet(attempts: s.attempts, clean: s.cleanReps, reps: s.reps, seconds: s.holdSeconds.round());
    session = null;
  }

  Widget _viewport() {
    final cam = _cam;
    final mirror = !demo && (cam?.description.lensDirection == CameraLensDirection.front);
    Widget base;
    double aspect;
    if (demo) {
      aspect = 1;
      base = ValueListenableBuilder<MannequinPose?>(
        valueListenable: demoPose,
        builder: (context, m, _) => m == null
            ? const SizedBox()
            : CustomPaint(
                painter: MannequinPainter(pose: m, muscles: def.normalisedMuscles, glow: 0.4, props: def.keyframes.props),
              ),
      );
    } else if (cam != null && cam.value.isInitialized) {
      aspect = 1 / cam.value.aspectRatio;
      base = CameraPreview(cam);
    } else {
      aspect = 3 / 4;
      base = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: cameraError == null
              ? const CircularProgressIndicator()
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.no_photography_outlined, size: 48, color: FF.muted),
                  const SizedBox(height: 12),
                  Text(cameraError!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(() {
                      demo = true;
                      _enterSetup();
                    }),
                    child: const Text('Use Demo mode'),
                  ),
                ]),
        ),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: Container(
          color: demo ? const Color(0xFF10142C) : Colors.black,
          child: Stack(fit: StackFit.expand, children: [
            base,
            RepaintBoundary(
              child: _SkeletonLayer(pose: livePose, frame: frame, mirror: mirror, focus: focusLandmarks(def.focus)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _trackingView(bool tester) {
    final s = session;
    final it = g.current;
    return Stack(children: [
      Positioned.fill(child: _viewport()),
      if (phase == RunPhase.setup) Positioned(left: 12, right: 12, top: 8, child: _setupPanel()),
      if (phase == RunPhase.active && s != null) ...[
        Positioned(
          left: 12,
          top: 8,
          child: ValueListenableBuilder<FrameResult?>(
            valueListenable: frame,
            builder: (context, _, __) => _hudBox(
              def.isTimed
                  ? Text('${s.holdSeconds.floor()}/${it.seconds}s',
                      key: const Key('hold_counter'),
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, fontFeatures: FF.tabular))
                  : Text('${s.cleanReps}/${it.reps}',
                      key: const Key('rep_counter'),
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, fontFeatures: FF.tabular)),
              def.isTimed ? 'hold' : 'clean reps · ${s.attempts} tries',
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 8,
          child: ValueListenableBuilder<FrameResult?>(
            valueListenable: frame,
            builder: (context, f, __) {
              final timed = def.isTimed;
              final hasScore = timed ? true : s.reps.isNotEmpty;
              final score = timed
                  ? (f == null ? 0.0 : (f.inHold && !f.activeIssues.any((i) => i.severity != Severity.minor) ? 100.0 : 40.0))
                  : s.averageForm;
              return _hudBox(
                Text(hasScore ? '${score.round()}%' : '--',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: hasScore ? FF.scoreColor(score) : FF.text,
                        fontFeatures: FF.tabular)),
                timed ? 'form now' : 'form',
              );
            },
          ),
        ),
        if (!def.isTimed) Positioned(right: 16, top: 110, bottom: 140, child: _DepthMeter(frame: frame)),
      ],
      Positioned(left: 12, right: 12, bottom: tester ? 120 : 76, child: _FeedbackBar(message: message, frame: frame, def: def, cues: cues, lastCorrection: lastCorrection)),
      if (tester && lastRepForLabel != null)
        Positioned(
          left: 12,
          right: 12,
          bottom: 70,
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: FF.good),
                onPressed: () => _label(true),
                icon: const Icon(Icons.thumb_up),
                label: Text('Right (${lastRepForLabel!.clean ? 'good' : 'bad'})'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: FF.bad),
                onPressed: () => _label(false),
                icon: const Icon(Icons.thumb_down),
                label: const Text('Wrong'),
              ),
            ),
          ]),
        ),
      Positioned(
        left: 12,
        right: 12,
        bottom: 12,
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(backgroundColor: Colors.black54),
              onPressed: _skipExercise,
              child: const Text('Skip exercise'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              key: const Key('end_set'),
              onPressed: phase == RunPhase.active ? _endSet : _startSet,
              child: Text(phase == RunPhase.active ? 'End set' : 'Start now'),
            ),
          ),
        ]),
      ),
      if (paused)
        Positioned.fill(
          child: Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: const Text('Paused', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
          ),
        ),
    ]);
  }

  Widget _hudBox(Widget value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          value,
          Text(label, style: const TextStyle(color: FF.muted, fontSize: 12)),
        ]),
      );

  Widget _setupPanel() {
    return ValueListenableBuilder<Map<String, bool>>(
      valueListenable: checks,
      builder: (context, c, _) {
        final ready = c.isNotEmpty && c.values.every((v) => v);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ready ? FF.good : FF.outline, width: 2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(ready ? Icons.check_circle : Icons.center_focus_strong, color: ready ? FF.good : FF.accent),
              const SizedBox(width: 8),
              Text(ready ? 'Ready' : 'Camera setup', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const Spacer(),
              Text(def.isTimed ? '${g.current.seconds}s hold' : '${g.current.reps} reps',
                  style: const TextStyle(color: FF.muted)),
            ]),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: (c.isEmpty
                      ? {_inViewLabel: false, _distanceLabel: false, 'Lighting': false, 'Phone steady': false}
                      : c)
                  .entries
                  .map((e) => Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(e.value ? Icons.check : Icons.close, size: 16, color: e.value ? FF.good : FF.bad),
                        const SizedBox(width: 4),
                        Text(e.key, style: const TextStyle(fontSize: 13)),
                      ]))
                  .toList(),
            ),
            const SizedBox(height: 6),
            Text(def.cameraTip, style: const TextStyle(color: FF.muted, fontSize: 12)),
          ]),
        );
      },
    );
  }

  Widget _restView() {
    final cat = ref.read(appProvider).catalog;
    final next = cat.byId(g.current.exerciseId);
    return Container(
      color: FF.bg,
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 12),
        const Text('Rest', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        ProgressRing(
          value: restTotal == 0 ? 0 : restLeft / restTotal,
          size: 200,
          stroke: 14,
          child: Text('$restLeft', key: const Key('rest_left'), style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, fontFeatures: FF.tabular)),
        ),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlinedButton(
            onPressed: () => setState(() {
              restLeft += 15;
              restTotal += 15;
            }),
            child: const Text('+15 s'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            key: const Key('skip_rest'),
            onPressed: () {
              _restTimer?.cancel();
              _enterSetup();
            },
            child: const Text('Skip'),
          ),
        ]),
        const Spacer(),
        if (next != null)
          Card(
            child: ListTile(
              leading: ExerciseThumb(def: next, size: 56),
              title: const Text('Up next', style: TextStyle(color: FF.muted, fontSize: 13)),
              subtitle: Text('${next.name} · ${g.label.split(', ').last}',
                  style: const TextStyle(color: FF.text, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
      ]),
    );
  }
}

/// Plain coordinate holder for the steadiness check.
class Vec2Like {
  final double x, y;
  const Vec2Like(this.x, this.y);
}

class _SkeletonLayer extends StatefulWidget {
  final ValueNotifier<BodyPose?> pose;
  final ValueNotifier<FrameResult?> frame;
  final bool mirror;
  final Set<LandmarkId> focus;
  const _SkeletonLayer({required this.pose, required this.frame, required this.mirror, required this.focus});

  @override
  State<_SkeletonLayer> createState() => _SkeletonLayerState();
}

class _SkeletonLayerState extends State<_SkeletonLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.pose, widget.frame, _pulse]),
      builder: (context, _) => CustomPaint(
        painter: SkeletonPainter(
          pose: widget.pose.value,
          wrong: (widget.frame.value?.highlight ?? const []).toSet(),
          mirror: widget.mirror,
          pulse: _pulse.value,
          focus: widget.focus,
        ),
      ),
    );
  }
}

class _DepthMeter extends StatelessWidget {
  final ValueNotifier<FrameResult?> frame;
  const _DepthMeter({required this.frame});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FrameResult?>(
      valueListenable: frame,
      builder: (context, f, _) {
        final p = (f?.progress ?? 0).clamp(0.0, 1.0);
        final reached = p >= 0.999;
        return Column(children: [
          const Text('depth', style: TextStyle(fontSize: 10, color: FF.muted)),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              width: 16,
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8), border: Border.all(color: FF.outline)),
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                heightFactor: p,
                child: Container(
                  decoration: BoxDecoration(color: reached ? FF.good : FF.accent, borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(f?.metric == null ? '--' : '${f!.metric!.round()}°', style: const TextStyle(fontSize: 11, fontFeatures: FF.tabular)),
        ]);
      },
    );
  }
}

/// Green bar with a check for good form, red with an alert for
/// corrections (FR-VF-01); messages stay 1.3 s (FR-VF-10).
class _FeedbackBar extends StatelessWidget {
  final ValueNotifier<(String, bool)?> message;
  final ValueNotifier<FrameResult?> frame;
  final ExerciseDef def;
  final CueBook cues;
  final ValueNotifier<String?> lastCorrection;
  const _FeedbackBar({required this.message, required this.frame, required this.def, required this.cues, required this.lastCorrection});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([message, lastCorrection]),
      builder: (context, _) {
        final m = message.value;
        final paused = frame.value?.paused == true;
        final last = lastCorrection.value;
        final text = m?.$1 ?? (paused ? cues.text('step_back') : (last ?? 'Looking good, keep going'));
        final good = m?.$2 ?? (!paused && last == null);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: (good ? FF.good : FF.bad).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(good ? Icons.check_circle : Icons.warning_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  key: const Key('feedback_text'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ]),
        );
      },
    );
  }
}

