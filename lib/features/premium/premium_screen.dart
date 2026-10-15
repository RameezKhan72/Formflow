import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/entitlements.dart';
import '../../domain/exercise.dart';
import '../../domain/routine.dart';
import '../../services/ads_service.dart';
import '../../services/purchase_service.dart';
import '../../state/app_state.dart';
import '../tracking/workout_run_screen.dart';

/// FormFlow Premium paywall (doc item 11): all exercises, no ads. Free users
/// can also watch a rewarded ad to try one premium exercise for 24 hours.
class PremiumScreen extends ConsumerStatefulWidget {
  final ExerciseDef? exercise;
  const PremiumScreen({super.key, this.exercise});

  static Future<void> open(BuildContext context, {ExerciseDef? exercise}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PremiumScreen(exercise: exercise)));

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  String? _price;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(purchaseProvider).price().then((p) {
      if (mounted) setState(() => _price = p);
    });
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _buy() async {
    setState(() => _busy = true);
    final r = await ref.read(purchaseProvider).buy();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case PurchaseOutcome.purchased:
        ref.read(appProvider).setPremium(true);
        _snack('Welcome to FormFlow Premium');
        Navigator.of(context).maybePop();
      case PurchaseOutcome.pending:
        _snack('Payment pending. Premium unlocks when it completes.');
      case PurchaseOutcome.cancelled:
        break;
      case PurchaseOutcome.unavailable:
        _snack('The store is not available on this device right now.');
      case PurchaseOutcome.error:
        _snack('The purchase did not go through. Please try again.');
    }
  }

  Future<void> _watchAd(ExerciseDef e) async {
    setState(() => _busy = true);
    final ok = await ref.read(adsProvider).showRewarded();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.read(appProvider).unlockWithReward(e.id);
      _snack('${e.name} unlocked for 24 hours');
      Navigator.of(context).maybePop();
    } else {
      _snack('No ad is available right now. Please try again in a moment.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final cat = app.catalog;
    final e = widget.exercise;
    final premiumCount = cat.premiumCount;
    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Center(
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFFFFD36E), Color(0xFFFFA63D)]),
                boxShadow: [BoxShadow(color: const Color(0xFFFFA63D).withValues(alpha: 0.45), blurRadius: 28)],
              ),
              child: const Icon(Icons.workspace_premium, size: 54, color: Color(0xFF3A2400)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('FormFlow Premium',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            app.isPremium ? 'You have full access. Thank you!' : 'Train every muscle with real-time form coaching.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: FF.muted),
          ),
          const SizedBox(height: 20),
          _benefit(Icons.fitness_center, 'All ${cat.exercises.length} exercises', '$premiumCount pro exercises in 8 muscle sections'),
          _benefit(Icons.videocam, 'AI form tracking for every exercise', 'Rep counting and voice corrections for all of them'),
          _benefit(Icons.view_in_ar, '3D muscle demonstrations', 'See exactly which muscles each move works'),
          _benefit(Icons.block, 'No ads', 'A clean, distraction-free app'),
          const SizedBox(height: 20),
          if (app.isPremium)
            const Card(
              child: ListTile(
                leading: Icon(Icons.verified, color: FF.good),
                title: Text('Premium is active'),
              ),
            )
          else ...[
            SizedBox(
              height: 56,
              child: FilledButton(
                key: const Key('buy_premium'),
                onPressed: _busy ? null : _buy,
                child: Text(_price == null ? 'Go Premium' : 'Go Premium · $_price'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('restore_premium'),
              onPressed: _busy
                  ? null
                  : () async {
                      await ref.read(purchaseProvider).restore();
                      if (mounted) _snack('Checking your purchases...');
                    },
              child: const Text('Restore purchases'),
            ),
            if (e != null && e.premium && !app.canUse(e)) ...[
              const SizedBox(height: 12),
              const Row(children: [
                Expanded(child: Divider()),
                Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('or', style: TextStyle(color: FF.muted))),
                Expanded(child: Divider()),
              ]),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('watch_ad_unlock'),
                onPressed: _busy ? null : () => _watchAd(e),
                icon: const Icon(Icons.ondemand_video),
                label: Text('Watch an ad to try ${e.name} for 24 h'),
              ),
            ],
          ],
          const SizedBox(height: 16),
          const Text(
            'Payment is handled by Google Play or the App Store. You can restore Premium on a new phone with the same account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: FF.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _benefit(IconData icon, String title, String sub) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: FF.accentSoft, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: FF.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(sub, style: const TextStyle(color: FF.muted, fontSize: 13)),
            ]),
          ),
        ]),
      );
}

/// Before starting a workout: if it contains locked premium exercises,
/// offer Premium, a rewarded ad (unlocks them for 24 h) or skipping them.
/// Returns the exercise ids that may be used, or null to cancel.
Future<Set<String>?> ensureUnlocked(BuildContext context, WidgetRef ref, List<String> exerciseIds) async {
  final app = ref.read(appProvider);
  final locked = app.lockedIn(exerciseIds);
  if (locked.isEmpty) return exerciseIds.toSet();
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.lock, color: Color(0xFFFFC94D)),
            SizedBox(width: 8),
            Text('Premium exercises', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Text(
            '${locked.map((e) => e.name).join(', ')} ${locked.length == 1 ? 'is' : 'are'} part of FormFlow Premium.',
            style: const TextStyle(color: FF.muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('unlock_premium'),
            onPressed: () => Navigator.pop(c, 'premium'),
            icon: const Icon(Icons.workspace_premium),
            label: const Text('Go Premium'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('unlock_ad'),
            onPressed: () => Navigator.pop(c, 'ad'),
            icon: const Icon(Icons.ondemand_video),
            label: Text('Watch an ad, unlock for ${Entitlements.rewardUnlock.inHours} h'),
          ),
          TextButton(
            key: const Key('unlock_skip'),
            onPressed: () => Navigator.pop(c, 'skip'),
            child: const Text('Skip them this time'),
          ),
        ]),
      ),
    ),
  );
  if (!context.mounted) return null;
  switch (choice) {
    case 'premium':
      await PremiumScreen.open(context);
      if (!context.mounted) return null;
      return app.lockedIn(exerciseIds).isEmpty ? exerciseIds.toSet() : null;
    case 'ad':
      final ok = await ref.read(adsProvider).showRewarded();
      if (!ok) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('No ad is available right now. Please try again.')));
        }
        return null;
      }
      for (final e in locked) {
        app.unlockWithReward(e.id);
      }
      return exerciseIds.toSet();
    case 'skip':
      final ids = locked.map((e) => e.id).toSet();
      final rest = exerciseIds.where((id) => !ids.contains(id)).toSet();
      return rest.isEmpty ? null : rest;
    default:
      return null;
  }
}

/// Starts a workout after the premium check (locked exercises are unlocked
/// with Premium or a rewarded ad, or left out).
Future<void> startWorkout(BuildContext context, WidgetRef ref, Routine routine, {bool demo = false}) async {
  final ok = await ensureUnlocked(context, ref, routine.items.map((i) => i.exerciseId).toList());
  if (ok == null || !context.mounted) return;
  final r = routine.copyWith(items: routine.items.where((i) => ok.contains(i.exerciseId)).toList());
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutRunScreen(routine: r, demo: demo)));
}
