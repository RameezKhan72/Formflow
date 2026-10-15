import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../domain/exercise.dart';
import 'mannequin.dart';

/// Realistic 3D exercise demonstration (asset A3). The anatomical figure
/// (Z-Anatomy, CC BY-SA 4.0) is posed with the exercise keyframes and
/// rendered in Blender by tool/anatomy/pose_render.py, standing on a lit
/// floor with real contact shadows; worked muscles are red. Each exercise
/// is a small looping H.264 video, so no 3D engine runs on the phone.
/// Holds (plank, wall sit...) and reduced motion show the still frame.
class Exercise3DView extends StatefulWidget {
  final ExerciseDef def;
  final bool animate;
  const Exercise3DView({super.key, required this.def, this.animate = true});

  static String video(String id) => 'assets/exercise_video/$id.mp4';
  static String still(String id) => 'assets/thumbs/$id.webp';

  /// Video playback needs the platform plugin; widget tests use the still.
  static bool videoEnabled = !Platform.environment.containsKey('FLUTTER_TEST');

  /// Kept for call sites that choose between 3D and 2D.
  static bool get supported => true;

  @override
  State<Exercise3DView> createState() => _Exercise3DViewState();
}

class _Exercise3DViewState extends State<Exercise3DView> {
  VideoPlayerController? _c;
  bool _ready = false;
  bool? _wantVideo;

  bool _shouldPlay(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return widget.animate && !reduce && !widget.def.isTimed && Exercise3DView.videoEnabled;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final want = _shouldPlay(context);
    if (want != _wantVideo) {
      _wantVideo = want;
      if (want) {
        _start();
      } else {
        _stop();
      }
    }
  }

  @override
  void didUpdateWidget(covariant Exercise3DView old) {
    super.didUpdateWidget(old);
    if (old.def.id != widget.def.id || old.animate != widget.animate) {
      _stop();
      _wantVideo = _shouldPlay(context);
      if (_wantVideo!) _start();
    }
  }

  Future<void> _start() async {
    final c = VideoPlayerController.asset(
      Exercise3DView.video(widget.def.id),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _c = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      if (!mounted || _c != c) {
        await c.dispose();
        return;
      }
      await c.play();
      setState(() => _ready = true);
    } catch (_) {
      if (mounted && _c == c) setState(() => _ready = false);
    }
  }

  void _stop() {
    final c = _c;
    _c = null;
    _ready = false;
    c?.dispose();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Semantics(
      label: '3D demonstration of ${widget.def.name}',
      image: true,
      child: Stack(fit: StackFit.expand, children: [
        Image.asset(
          Exercise3DView.still(widget.def.id),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stack) => ExerciseDemo(def: widget.def, animate: widget.animate),
        ),
        if (c != null && _ready)
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio == 0 ? 1 : c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
      ]),
    );
  }
}
