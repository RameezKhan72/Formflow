import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../domain/exercise.dart';

/// Realistic anatomical body map (asset A1).
///
/// Rendered offline in Blender from the Z-Anatomy model (CC BY-SA 4.0, see
/// ASSETS.md) by tool/anatomy/: a shaded grey figure (front and back), one
/// coverage mask per FormFlow muscle and a small ID map for taps. Muscles
/// are tinted at runtime by multiplying the mask colour over the shading,
/// so they keep the realistic lighting.
class BodyMapData {
  final Map<String, dynamic> meta;
  final Map<String, ui.Image> _bodies = {};
  final Map<String, ui.Image> _masks = {};
  final Map<String, Uint8List> _ids = {};
  final Map<String, Size> _idSize = {};
  final Map<String, Future<void>> _pending = {};

  BodyMapData(this.meta);

  static BodyMapData? _cached;
  static Future<BodyMapData>? _loading;
  static BodyMapData? get cached => _cached;

  static const base = 'assets/anatomy3d';

  static Future<BodyMapData> load([AssetBundle? bundle]) {
    if (_cached != null) return Future.value(_cached);
    return _loading ??= () async {
      final b = bundle ?? rootBundle;
      final meta = jsonDecode(await b.loadString('$base/meta.json')) as Map<String, dynamic>;
      final d = BodyMapData(meta);
      await d.ensureView('front', b);
      _cached = d;
      // back view and its id map load in the background
      d.ensureView('back', b);
      return d;
    }();
  }

  static Future<ui.Image> _decode(AssetBundle b, String path, {int? width}) async {
    final data = await b.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    return (await codec.getNextFrame()).image;
  }

  Future<void> ensureView(String view, [AssetBundle? bundle]) {
    return _pending[view] ??= () async {
      final b = bundle ?? rootBundle;
      _bodies[view] = await _decode(b, '$base/body_$view.webp');
      final id = await _decode(b, '$base/id_$view.png');
      final bytes = await id.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes != null) {
        _ids[view] = bytes.buffer.asUint8List();
        _idSize[view] = Size(id.width.toDouble(), id.height.toDouble());
      }
    }();
  }

  Future<void> ensureMask(String view, String muscle, [AssetBundle? bundle]) {
    final key = '$view/$muscle';
    if (!hasMuscle(view, muscle)) return Future.value();
    return _pending[key] ??= () async {
      _masks[key] = await _decode(bundle ?? rootBundle, '$base/mask_${view}_$muscle.webp');
    }();
  }

  ui.Image? body(String view) => _bodies[view];
  ui.Image? mask(String view, String muscle) => _masks['$view/$muscle'];

  Map<String, dynamic> _view(String view) => (meta['views'] as Map<String, dynamic>)[view] as Map<String, dynamic>;

  bool hasMuscle(String view, String muscle) => (_view(view)['boxes'] as Map<String, dynamic>).containsKey(muscle);

  /// Normalised bounding box of a muscle in a view, or null.
  Rect? box(String view, String muscle) {
    final b = (_view(view)['boxes'] as Map<String, dynamic>)[muscle] as List?;
    if (b == null) return null;
    final v = b.map((e) => (e as num).toDouble()).toList();
    return Rect.fromLTRB(v[0], v[1], v[2], v[3]);
  }

  /// Muscle under a normalised point (0..1) of a view, via the ID map.
  String? muscleAt(String view, Offset p) {
    final bytes = _ids[view];
    final s = _idSize[view];
    if (bytes == null || s == null) return null;
    final x = (p.dx * s.width).floor(), y = (p.dy * s.height).floor();
    if (x < 0 || y < 0 || x >= s.width || y >= s.height) return null;
    final g = bytes[(y * s.width.toInt() + x) * 4];
    final idx = (g / 16).round() - 1;
    final groups = (meta['groups'] as List).cast<String>();
    return idx >= 0 && idx < groups.length ? groups[idx] : null;
  }

  /// Which view shows a muscle best.
  String bestView(String muscle) {
    final f = box('front', muscle), b = box('back', muscle);
    if (f == null) return 'back';
    if (b == null) return 'front';
    return (b.width * b.height) > (f.width * f.height) * 1.3 ? 'back' : 'front';
  }
}

class _AnatomyPainter extends CustomPainter {
  final ui.Image body;
  final Map<ui.Image, Color> tints;
  final ui.Image? selectedMask;

  /// Source crop as fractions of the image (null = whole figure).
  final Rect? crop;

  _AnatomyPainter({required this.body, required this.tints, this.selectedMask, this.crop});

  Rect _src(ui.Image img) {
    final w = img.width.toDouble(), h = img.height.toDouble();
    final c = crop ?? const Rect.fromLTWH(0, 0, 1, 1);
    return Rect.fromLTRB(c.left * w, c.top * h, c.right * w, c.bottom * h);
  }

  Rect dstFor(Size size) {
    final src = _src(body);
    final s = (size.width / src.width) < (size.height / src.height) ? size.width / src.width : size.height / src.height;
    final w = src.width * s, h = src.height * s;
    return Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final dst = dstFor(size);
    canvas.saveLayer(dst, Paint());
    canvas.drawImageRect(body, _src(body), dst, Paint()..filterQuality = FilterQuality.medium);
    tints.forEach((mask, color) {
      final src = _src(mask);
      // multiply keeps the realistic shading; a small additive pass adds glow
      canvas.drawImageRect(
          mask,
          src,
          dst,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..blendMode = BlendMode.multiply
            ..colorFilter = ColorFilter.mode(color.withValues(alpha: 1), BlendMode.srcIn));
      canvas.drawImageRect(
          mask,
          src,
          dst,
          Paint()
            ..blendMode = BlendMode.plus
            ..colorFilter = ColorFilter.mode(color.withValues(alpha: 0.16), BlendMode.srcIn));
    });
    final sel = selectedMask;
    if (sel != null) {
      canvas.drawImageRect(
          sel,
          _src(sel),
          dst,
          Paint()
            ..blendMode = BlendMode.screen
            ..colorFilter = ColorFilter.mode(Colors.white.withValues(alpha: 0.35), BlendMode.srcIn));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AnatomyPainter old) =>
      old.body != body || old.tints.length != tints.length || old.selectedMask != selectedMask || old.crop != crop ||
      old.tints.entries.any((e) => tints[e.key] != e.value);
}

/// Full-body realistic muscle map (front or back). [colors] tints muscles;
/// muscles not in the map keep the natural grey.
class MuscleMap extends StatefulWidget {
  final bool back;
  final bool female; // only a male anatomy model is bundled; kept for API compatibility
  final Map<String, Color> colors;
  final String? selected;
  final ValueChanged<String>? onTapMuscle;
  final Rect? crop;

  const MuscleMap({
    super.key,
    required this.back,
    this.female = false,
    required this.colors,
    this.selected,
    this.onTapMuscle,
    this.crop,
  });

  @override
  State<MuscleMap> createState() => _MuscleMapState();
}

class _MuscleMapState extends State<MuscleMap> {
  BodyMapData? _data = BodyMapData.cached;

  String get _view => widget.back ? 'back' : 'front';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MuscleMap old) {
    super.didUpdateWidget(old);
    _load();
  }

  Future<void> _load() async {
    final d = _data ?? await BodyMapData.load();
    final view = _view;
    final futures = <Future<void>>[d.ensureView(view)];
    for (final m in widget.colors.keys) {
      futures.add(d.ensureMask(view, m));
    }
    if (widget.selected != null) futures.add(d.ensureMask(view, widget.selected!));
    await Future.wait(futures);
    if (mounted) setState(() => _data = d);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final body = d?.body(_view);
    if (d == null || body == null) return const SizedBox.expand();
    final tints = <ui.Image, Color>{};
    widget.colors.forEach((m, c) {
      final img = d.mask(_view, m);
      if (img != null) tints[img] = c;
    });
    final painter = _AnatomyPainter(
      body: body,
      tints: tints,
      selectedMask: widget.selected == null ? null : d.mask(_view, widget.selected!),
      crop: widget.crop,
    );
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return GestureDetector(
        onTapUp: widget.onTapMuscle == null
            ? null
            : (details) {
                final dst = painter.dstFor(size);
                final crop = widget.crop ?? const Rect.fromLTWH(0, 0, 1, 1);
                final p = details.localPosition - dst.topLeft;
                final nx = crop.left + p.dx / dst.width * crop.width;
                final ny = crop.top + p.dy / dst.height * crop.height;
                final m = d.muscleAt(_view, Offset(nx, ny));
                if (m != null) widget.onTapMuscle!(m);
              },
        child: RepaintBoundary(child: CustomPaint(size: size, painter: painter)),
      );
    });
  }
}

/// Mini muscle chip generated at runtime from the realistic map (A2,
/// FR-DM-08): a crop around the muscle with the muscle tinted.
class MuscleChip extends StatelessWidget {
  final String muscle;
  final double size;
  final bool female;
  final Color color;
  const MuscleChip({super.key, required this.muscle, this.size = 56, this.female = false, this.color = FF.muscle});

  @override
  Widget build(BuildContext context) {
    final d = BodyMapData.cached;
    final view = d?.bestView(muscle) ?? (MuscleIds.back.contains(muscle) ? 'back' : 'front');
    Rect? crop;
    final b = d?.box(view, muscle);
    if (b != null) {
      // square crop (in pixels) around the muscle, figure is 1:2
      final cx = b.center.dx, cy = b.center.dy;
      final half = (b.width / 2 > b.height ? b.width / 2 : b.height) + 0.05;
      crop = Rect.fromLTRB((cx - half).clamp(0.0, 1.0), (cy - half / 2).clamp(0.0, 1.0),
          (cx + half).clamp(0.0, 1.0), (cy + half / 2).clamp(0.0, 1.0));
    }
    return Semantics(
      label: '${MuscleIds.label(muscle)} muscle',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1F3D), Color(0xFF0B0E22)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FF.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: MuscleMap(back: view == 'back', colors: {muscle: color}, crop: crop),
      ),
    );
  }
}
