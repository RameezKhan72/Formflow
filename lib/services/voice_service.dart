import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../domain/feedback.dart';
import '../domain/landmarks.dart';
import '../domain/rules.dart';

/// Plays a pre-recorded cue clip. Returns false when no clip exists so the
/// next stage of the fallback chain is used (FR-VF-08).
abstract class ClipPlayer {
  Future<bool> play(String assetPath, double volume);
}

/// Default: no clips bundled yet; checks the asset and reports false.
class AssetCheckClipPlayer implements ClipPlayer {
  @override
  Future<bool> play(String assetPath, double volume) async {
    try {
      await rootBundle.load(assetPath);
      // A low-latency player (e.g. flutter_soloud) plugs in here once the
      // recorded clips are added to assets/audio/.
      return false;
    } catch (_) {
      return false;
    }
  }
}

/// Voice and haptic feedback with the fallback chain: recorded clip ->
/// system TTS -> on-screen text with haptic.
class VoiceService {
  final ClipPlayer clips;
  final FlutterTts? _tts;
  bool enabled;
  bool haptics;
  double volume;
  bool _ttsReady = false;
  bool _ttsFailed = false;

  VoiceService({ClipPlayer? clips, FlutterTts? tts, this.enabled = true, this.haptics = true, this.volume = 1})
      : clips = clips ?? AssetCheckClipPlayer(),
        _tts = tts;

  factory VoiceService.system({bool enabled = true, bool haptics = true, double volume = 1}) {
    FlutterTts? tts;
    try {
      tts = FlutterTts();
    } catch (_) {
      tts = null;
    }
    return VoiceService(tts: tts, enabled: enabled, haptics: haptics, volume: volume);
  }

  Future<void> _initTts() async {
    if (_ttsReady || _ttsFailed || _tts == null) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(volume);
      await _tts.awaitSpeakCompletion(false);
      _ttsReady = true;
    } catch (_) {
      _ttsFailed = true;
    }
  }

  /// Speaks a cue. Returns true if audio was produced.
  Future<bool> speak(String text, {String? cueId, BodySide? side}) async {
    if (!enabled) return false;
    if (cueId != null && await clips.play(CueBook.clipPath(cueId, side: side), volume)) return true;
    await _initTts();
    if (_ttsReady) {
      try {
        await _tts!.speak(text);
        return true;
      } catch (_) {
        _ttsFailed = true;
      }
    }
    await buzz();
    return false;
  }

  Future<void> buzz() async {
    if (!haptics) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  Future<void> tone() async {
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  Future<void> handle(List<FeedbackAction> actions) async {
    for (final a in actions) {
      switch (a.kind) {
        case FeedbackKind.speak:
          await speak(a.text ?? '', cueId: a.cueId, side: a.side);
          break;
        case FeedbackKind.haptic:
          await buzz();
          break;
        case FeedbackKind.tone:
          await tone();
          break;
      }
    }
  }

  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
