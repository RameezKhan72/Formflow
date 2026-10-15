import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Checks the realistic anatomy assets rendered by tool/anatomy/.
void main() {
  final cat = loadCatalog();

  test('every moving exercise has a 3D video and every exercise a still', () {
    for (final e in cat.exercises) {
      final thumb = File('assets/thumbs/${e.id}.webp');
      expect(thumb.existsSync(), isTrue, reason: e.id);
      final t = thumb.readAsBytesSync().sublist(0, 12);
      expect(ascii.decode(t.sublist(0, 4)), 'RIFF', reason: e.id);
      expect(ascii.decode(t.sublist(8, 12)), 'WEBP', reason: e.id);
      if (e.isTimed) continue; // holds show the still
      final video = File('assets/exercise_video/${e.id}.mp4');
      expect(video.existsSync(), isTrue, reason: e.id);
      // ISO base media file: 'ftyp' box at offset 4
      expect(ascii.decode(video.readAsBytesSync().sublist(4, 8)), 'ftyp', reason: e.id);
    }
  });

  test('logo and launcher icons exist', () {
    expect(File('assets/branding/logo.png').existsSync(), isTrue);
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(File('android/app/src/main/res/mipmap-$d/ic_launcher.png').existsSync(), isTrue, reason: d);
    }
  });

  test('the body map covers all 14 muscles', () {
    final meta = jsonDecode(File('assets/anatomy3d/meta.json').readAsStringSync()) as Map<String, dynamic>;
    final groups = (meta['groups'] as List).cast<String>();
    expect(groups, hasLength(14));
    final views = meta['views'] as Map<String, dynamic>;
    for (final g in groups) {
      final inFront = (views['front']['boxes'] as Map).containsKey(g);
      final inBack = (views['back']['boxes'] as Map).containsKey(g);
      expect(inFront || inBack, isTrue, reason: g);
    }
    for (final v in ['front', 'back']) {
      expect(File('assets/anatomy3d/body_$v.webp').existsSync(), isTrue);
      expect(File('assets/anatomy3d/id_$v.png').existsSync(), isTrue);
    }
  });

  test('media stays light (under 15 MB for all 56 exercises)', () {
    var total = 0;
    for (final dir in ['assets/anatomy3d', 'assets/exercise_video', 'assets/thumbs', 'assets/branding']) {
      for (final f in Directory(dir).listSync().whereType<File>()) {
        total += f.lengthSync();
      }
    }
    expect(total, lessThan(15 * 1024 * 1024));
  });
}
