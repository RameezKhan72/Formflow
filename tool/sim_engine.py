"""Python mirror of the Dart pose engine (demo_motion, measurements,
rep_counter, rules, tracking_session) used to check every exercise's
thresholds and rules quickly while authoring, before running `flutter test`.

    python3 tool/sim_engine.py [exercise_id ...]

It replays each exercise's demonstration (correct and shallow "mistake"
versions) exactly like test/domain/engine_test.dart and prints any failure.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = json.load(open(os.path.join(HERE, '..', 'assets', 'data', 'exercises.json')))

D = dict(shin=.23, thigh=.24, torso=.29, neck=.05, headR=.052, upperArm=.16, forearm=.15,
         footFwd=.085, heelBack=.03, footDrop=.035, floorY=.93, hipHalf=.055, shoulderHalf=.095)
RADIUS = {'head': D['headR'], 'shoulder': .04, 'hip': .045, 'knee': .028, 'elbow': .022, 'wrist': .015, 'ankle': .02}


def vd(deg):
    r = math.radians(deg)
    return (math.sin(r), -math.cos(r))


def add(a, b, k=1.0):
    return (a[0] + b[0] * k, a[1] + b[1] * k)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def length(v):
    return math.hypot(v[0], v[1])


def complete(m):
    out = dict(m)
    for k, v in dict(shin=0., thigh=0., torso=0., upperArm=180., forearm=180., foot=90.).items():
        out.setdefault(k, v)
    for k in ('shin', 'thigh', 'foot', 'upperArm', 'forearm'):
        out.setdefault(k + '2', out[k])
    out.setdefault('head', out['torso'])
    return out


def lerp_angles(a, b, u):
    out = {}
    for k in set(a) | set(b):
        va = a.get(k, b.get(k))
        vb = b.get(k, a.get(k))
        out[k] = va + (vb - va) * u
    return out


def solve(kf, u):
    a = lerp_angles(complete(kf.get('start2d', kf['start'])), complete(kf.get('end2d', kf['end'])), u)
    return front(kf, a) if kf.get('view') == 'front' else side(kf, a)


def foot(j, s, ankle, fa, k):
    al, dn = vd(fa), vd(fa + 90)
    j['toe' + s] = add(add(ankle, al, D['footFwd'] * k), dn, D['footDrop'] * k)
    j['heel' + s] = add(add(ankle, al, -D['heelBack'] * k), dn, D['footDrop'] * k)


def side(kf, a):
    k = kf.get('scale', 1.0)
    g = lambda key, d: a.get(key, d)
    shinA, thighA, torsoA = g('shin', 0), g('thigh', 0), g('torso', 0)
    footA = g('foot', 90)
    ua, fa = g('upperArm', 180), g('forearm', 180)
    shin2, thigh2, foot2 = g('shin2', shinA), g('thigh2', thighA), g('foot2', footA)
    ua2, fa2 = g('upperArm2', ua), g('forearm2', fa)
    headA = g('head', torsoA)
    j = {'ankle': (0., 0.)}
    j['knee'] = add(j['ankle'], vd(shinA), D['shin'] * k)
    j['hip'] = add(j['knee'], vd(thighA), D['thigh'] * k)
    j['shoulder'] = add(j['hip'], vd(torsoA), D['torso'] * k)
    j['neck'] = add(j['shoulder'], vd(headA), D['neck'] * k)
    j['head'] = add(j['neck'], vd(headA), D['headR'] * k)
    j['elbow'] = add(j['shoulder'], vd(ua), D['upperArm'] * k)
    j['wrist'] = add(j['elbow'], vd(fa), D['forearm'] * k)
    foot(j, '', j['ankle'], footA, k)
    j['knee2'] = add(j['hip'], vd(thigh2 + 180), D['thigh'] * k)
    j['ankle2'] = add(j['knee2'], vd(shin2 + 180), D['shin'] * k)
    foot(j, '2', j['ankle2'], foot2, k)
    j['elbow2'] = add(j['shoulder'], vd(ua2), D['upperArm'] * k)
    j['wrist2'] = add(j['elbow2'], vd(fa2), D['forearm'] * k)
    if kf.get('anchor', 'floor') == 'wrist':
        shift = sub((kf.get('anchorX', .45), kf.get('anchorY', .9)), j['wrist'])
    else:
        my = -1e9
        for key, p in j.items():
            if key == 'neck':
                continue
            if kf.get('armIk') and (key.startswith('wrist') or key.startswith('elbow')):
                continue
            my = max(my, p[1] + RADIUS.get(key.replace('2', ''), 0))
        shift = (kf.get('anchorX', .45) - j['ankle'][0], D['floorY'] - my)
    for key in j:
        j[key] = add(j[key], shift)
    if kf.get('armIk'):
        U, F = D['upperArm'] * k, D['forearm'] * k
        for s in ('', '2'):
            sh = j['shoulder']
            t = (sh[0] + .015, D['floorY'] - .012)
            tt = sub(t, sh)
            dist = min(length(tt), U + F - 1e-4)
            base = math.atan2(tt[1], tt[0])
            c = max(-1, min(1, (U * U + dist * dist - F * F) / (2 * U * dist)))
            aa = math.acos(c)
            e1 = (sh[0] + math.cos(base + aa) * U, sh[1] + math.sin(base + aa) * U)
            e2 = (sh[0] + math.cos(base - aa) * U, sh[1] + math.sin(base - aa) * U)
            e = e1 if e1[0] < e2[0] else e2
            dv = sub(t, e)
            L = length(dv) or 1
            off = (-.008, -.004) if s == '2' else (0, 0)
            j['elbow' + s] = add(e, off)
            j['wrist' + s] = add(add(e, dv, F / L), off)
    return j, False


def front(kf, a):
    cx = kf.get('anchorX', .45)
    g = lambda key, d: a.get(key, d)
    shinA, thighA, torsoA = g('shin', 0), g('thigh', 0), g('torso', 0)
    ua, fa = g('upperArm', 175), g('forearm', 178)
    ankleL = (cx + .07, D['floorY'] - D['footDrop'])
    kneeL = add(ankleL, vd(shinA), D['shin'])
    hipL = add(kneeL, vd(thighA), D['thigh'])
    hipC = (hipL[0] - D['hipHalf'], hipL[1])
    shC = add(hipC, vd(torsoA), D['torso'])
    m = lambda p: (2 * cx - p[0], p[1])
    shL = (shC[0] + D['shoulderHalf'], shC[1])
    elL = add(shL, vd(ua), D['upperArm'])
    wrL = add(elL, vd(fa), D['forearm'])
    j = dict(ankle=ankleL, knee=kneeL, hip=hipL, shoulder=shL, elbow=elL, wrist=wrL,
             toe=add(ankleL, (.02, .03)), heel=add(ankleL, (0, .035)))
    for key in list(j):
        j[key + '2'] = m(j[key])
    j['neck'] = add(shC, vd(torsoA), D['neck'])
    j['head'] = add(j['neck'], vd(torsoA), D['headR'])
    return j, True


# ---------------------------------------------------------------- landmarks (subset used by the engine)
JOINTS = ['shoulder', 'elbow', 'wrist', 'hip', 'knee', 'ankle', 'heel', 'toe']


def synthetic(j, is_front, near=.95, farc=.8):
    """Returns {('left'|'right', joint): (x, y, conf)} plus 'nose'."""
    L = {}
    fc = near if is_front else farc
    for jt in JOINTS:
        L[('left', jt)] = (*j[jt], near)
        if is_front:
            p = j[jt + '2']
        elif jt in ('shoulder', 'hip'):
            p = add(j[jt], (-.01, -.004))
        else:
            p = add(j.get(jt + '2', j[jt]), (-.01, -.004))
        L[('right', jt)] = (*p, fc)
    return L


def pt(L, s, jt, gate=.5):
    v = L.get((s, jt))
    return (v[0], v[1]) if v and v[2] >= gate else None


def angle_at(a, b, c):
    ba, bc = sub(a, b), sub(c, b)
    den = length(ba) * length(bc)
    if den < 1e-9:
        return None
    return math.degrees(math.acos(max(-1, min(1, (ba[0] * bc[0] + ba[1] * bc[1]) / den))))


def from_vertical(a, b):
    v = sub(b, a)
    n = length(v)
    return 0 if n < 1e-9 else math.degrees(math.acos(max(-1, min(1, -v[1] / n))))


def from_horizontal(a, b):
    v = sub(b, a)
    return 0 if length(v) < 1e-9 else math.degrees(math.atan2(abs(v[1]), abs(v[0])))


def for_side(L, s):
    m = {}
    sh, el, wr, hip, kn, an, heel, toe = (pt(L, s, x) for x in JOINTS)

    def put(k, v):
        if v is not None:
            m[k] = v
    if hip and kn and an: put('kneeAngle', angle_at(hip, kn, an))
    if sh and hip and kn: put('hipAngle', angle_at(sh, hip, kn))
    if sh and el and wr: put('elbowAngle', angle_at(sh, el, wr))
    if hip and sh and el: put('shoulderAngle', angle_at(hip, sh, el))
    if sh and hip and an: put('bodyLine', angle_at(sh, hip, an))
    if kn and an and toe: put('ankleAngle', angle_at(kn, an, toe))
    if hip and kn: put('thighAngle', from_vertical(kn, hip))
    torso = length(sub(sh, hip)) if sh and hip else None
    leg = length(sub(hip, an)) if hip and an else None
    if sh and hip:
        put('torsoLean', from_vertical(hip, sh))
        put('torsoHorizontal', from_horizontal(hip, sh))
    if torso and torso > 1e-6:
        if el and sh: put('elbowDrift', abs(el[0] - sh[0]) / torso)
        if wr and an: put('barGap', abs(wr[0] - an[0]) / torso)
        if wr and sh: put('wristAboveShoulder', (sh[1] - wr[1]) / torso)
        if kn and toe and heel:
            facing = 1.0 if toe[0] - heel[0] >= 0 else -1.0
            put('kneePastToe', (kn[0] - toe[0]) * facing / torso)
        if sh and hip and an:
            line = sub(sh, an)
            ln = length(line)
            if ln > 1e-6:
                hv = sub(hip, an)
                cross = line[0] * hv[1] - line[1] * hv[0]
                sign = 1.0 if line[0] >= 0 else -1.0
                put('hipOffset', cross / ln * sign / torso)
    if leg and leg > 1e-6 and heel and toe:
        put('heelRise', (toe[1] - heel[1]) / leg)
    return m


def bilateral(L):
    m = {}
    lk, rk, la, ra = pt(L, 'left', 'knee'), pt(L, 'right', 'knee'), pt(L, 'left', 'ankle'), pt(L, 'right', 'ankle')
    if lk and rk and la and ra:
        sp = abs(la[0] - ra[0])
        if sp > 1e-6:
            m['kneeSpacingToAnkleSpacing'] = abs(lk[0] - rk[0]) / sp
    l, r = for_side(L, 'left'), for_side(L, 'right')
    if 'shoulderAngle' in l and 'shoulderAngle' in r:
        m['armAsym'] = abs(l['shoulderAngle'] - r['shoulderAngle'])
    return m


def knee_inward(L, s):
    lh, rh = pt(L, 'left', 'hip'), pt(L, 'right', 'hip')
    kn, an = pt(L, s, 'knee'), pt(L, s, 'ankle')
    if not (lh and rh and kn and an):
        return None
    mid = (lh[0] + rh[0]) / 2
    w = abs(lh[0] - rh[0])
    if w < 1e-6:
        return None
    return (abs(an[0] - mid) - abs(kn[0] - mid)) / w


def all_m(L, s):
    m = for_side(L, s)
    m.update(bilateral(L))
    ki = knee_inward(L, s)
    if ki is not None:
        m['kneeInward'] = ki
    return m


def view_of(L):
    ls, rs = pt(L, 'left', 'shoulder'), pt(L, 'right', 'shoulder')
    hip = pt(L, 'left', 'hip') or pt(L, 'right', 'hip')
    if not ls or not rs or not hip:
        return 'side'
    mid = ((ls[0] + rs[0]) / 2, (ls[1] + rs[1]) / 2)
    t = length(sub(mid, hip))
    if t < 1e-6:
        return 'side'
    return 'front' if abs(ls[0] - rs[0]) / t > .45 else 'side'


def side_conf(L, s, focus):
    return sum(L[(s, j)][2] for j in focus if (s, j) in L)


def metric_value(L, metric, focus):
    l = for_side(L, 'left').get(metric['measure'])
    r = for_side(L, 'right').get(metric['measure'])
    if l is None and r is None:
        return None
    if l is None:
        return r, 'right'
    if r is None:
        return l, 'left'
    pol = metric.get('side', 'auto')
    if pol == 'min':
        return (l, 'left') if l <= r else (r, 'right')
    if pol == 'max':
        return (l, 'left') if l >= r else (r, 'right')
    s = 'left' if side_conf(L, 'left', focus) >= side_conf(L, 'right', focus) else 'right'
    return (l if s == 'left' else r), s


# ---------------------------------------------------------------- rep counter and rules
class Counter:
    def __init__(self, direction, th):
        self.dn = direction == 'down'
        self.th = th
        self.phase = 'idle'
        self.ext = 0
        self.depth = False
        self.t0 = 0

    def m(self, v):
        return v if self.dn else -v

    def update(self, value, t):
        v = self.m(value)
        st, co, de, hy = self.m(self.th['start']), self.m(self.th['complete']), self.m(self.th['depth']), self.th.get('hysteresis', 6)
        p = self.phase
        if p == 'idle':
            if v >= co:
                self.phase = 'ready'
            return None
        if p == 'ready':
            if v < st:
                self.phase = 'lowering'; self.ext = v; self.depth = False; self.t0 = t
                if v <= de:
                    self.phase = 'bottom'; self.depth = True
            return None
        if p == 'lowering':
            self.ext = min(self.ext, v)
            if v <= de:
                self.phase = 'bottom'; self.depth = True
            elif v > self.ext + hy:
                self.phase = 'rising'
            return self.finish(v, t, st, co, de)
        if p == 'bottom':
            self.ext = min(self.ext, v)
            if v > self.ext + hy:
                self.phase = 'rising'
            return self.finish(v, t, st, co, de)
        if p == 'rising':
            if v <= de:
                self.phase = 'bottom'; self.depth = True; self.ext = min(self.ext, v)
                return None
            if v < self.ext:
                self.ext = v; self.phase = 'lowering'
                return None
            return self.finish(v, t, st, co, de)

    def finish(self, v, t, st, co, de):
        if v < co:
            return None
        exc = st - self.ext
        need = (st - de) * .25
        dur = t - self.t0
        self.phase = 'ready'
        if exc < need or dur < .6:
            return None
        ev = dict(depth=self.depth, peak=self.ext if self.dn else -self.ext, dur=dur)
        self.depth = False
        return ev


def cond(when, m):
    if not when:
        return False
    for k, c in when.items():
        v = m.get(k)
        if v is None:
            return False
        if isinstance(c, bool):
            if (v > .5) != c:
                return False
        else:
            if 'gt' in c and not v > c['gt']:
                return False
            if 'lt' in c and not v < c['lt']:
                return False
    return True


def phase_ok(rp, ph, timed=False):
    if timed:
        return rp != 'rep_end'
    return {'any': True, 'moving': ph in ('lowering', 'bottom', 'rising'), 'lowering': ph == 'lowering',
            'bottom': ph in ('bottom', 'lowering'), 'rising': ph == 'rising'}.get(rp, False)


SEV = {'minor': 10, 'moderate': 20, 'major': 35}


def replay(ex, mistake=False, seconds=0, fps=15):
    kf = ex['keyframes']
    timed = ex['mode'] == 'timed'
    period = kf.get('period', 2.4)
    total = seconds if seconds > 0 else period * 3.2
    counter = Counter(ex['metric']['direction'], ex['thresholds'])
    counters = {}
    rep_issues = {}
    reps = []
    hold = 0
    focus = [f for f in ex.get('focus', ['shoulder', 'elbow', 'wrist', 'hip', 'knee', 'ankle']) if f in JOINTS]
    last_t = None
    issues_seen = []
    for i in range(int(total * fps)):
        t = i / fps
        dt = 0 if last_t is None else min(.5, max(0, t - last_t))
        last_t = t
        if timed:
            u = 1.0 if mistake else 0.0
        else:
            base = .5 - .5 * math.cos(2 * math.pi * t / period)
            u = base * .6 if mistake else base
        j, is_front = solve(kf, u)
        L = synthetic(j, is_front)
        mv = metric_value(L, ex['metric'], focus)
        if mv is None:
            continue
        value, mside = mv
        view = view_of(L)
        if timed:
            m = all_m(L, mside)
            in_hold = cond(ex.get('hold', {}), m)
            phase = 'bottom'
        else:
            ev = counter.update(value, t)
            phase = counter.phase
        active = []
        for r in ex['rules']:
            if r['phase'] == 'rep_end':
                continue
            if r.get('view') and r['view'] != view:
                continue
            if not phase_ok(r['phase'], phase, timed):
                for key in (r['id'], r['id'] + ':left', r['id'] + ':right'):
                    counters.pop(key, None)
                continue
            sides = ['left', 'right'] if r.get('bilateral') and view == 'front' else [None]
            for s in sides:
                m = all_m(L, s or mside)
                key = r['id'] if s is None else r['id'] + ':' + s
                if cond(r['when'], m):
                    counters[key] = counters.get(key, 0) + 1
                    if counters[key] >= r.get('persistFrames', 4):
                        active.append((key, r))
                else:
                    counters.pop(key, None)
        for key, r in active:
            rep_issues[key] = r
            issues_seen.append(r['cue'])
        if timed:
            blocking = any(r['severity'] != 'minor' for _, r in active)
            if in_hold and not blocking:
                hold += dt
        elif ev is not None:
            ctx = {'depthReached': 1 if ev['depth'] else 0, 'duration': ev['dur'], 'peak': ev['peak']}
            for r in ex['rules']:
                if r['phase'] == 'rep_end' and cond(r['when'], ctx):
                    rep_issues[r['id']] = r
            iss = list(rep_issues.values())
            rep_issues = {}
            score = max(0, 100 - sum(SEV[r['severity']] for r in iss))
            clean = ev['depth'] and not any(r['severity'] == 'major' for r in iss)
            reps.append(dict(clean=clean, score=score, depth=ev['depth'], issues=[r['cue'] for r in iss]))
    return reps, hold, issues_seen


def check(ex):
    errs = []
    if ex['mode'] == 'timed':
        _, hold, _ = replay(ex, seconds=5)
        if abs(hold - 5) > .4:
            errs.append('hold %.2f s (expected 5)' % hold)
        return errs
    reps, _, seen = replay(ex)
    if len(reps) < 2:
        errs.append('only %d attempts' % len(reps))
    if any(not r['clean'] for r in reps):
        errs.append('unclean reps: %s' % [r['issues'] for r in reps if not r['clean']])
    if reps and sum(r['score'] for r in reps) / len(reps) < 80:
        errs.append('avg form %.0f (issues %s)' % (sum(r['score'] for r in reps) / len(reps), [r['issues'] for r in reps]))
    reps, _, _ = replay(ex, mistake=True)
    if len(reps) < 2:
        errs.append('mistake: only %d attempts' % len(reps))
    if any(r['clean'] for r in reps):
        errs.append('mistake: clean reps')
    if any(r['depth'] for r in reps):
        errs.append('mistake: depth reached')
    return errs


def trace(ex, mistake=False):
    kf = ex['keyframes']
    focus = [f for f in ex.get('focus', []) if f in JOINTS]
    vals = []
    for i in range(21):
        u = i / 20 * (0.6 if mistake else 1)
        j, f = solve(kf, u)
        L = synthetic(j, f)
        mv = metric_value(L, ex['metric'], focus)
        vals.append(None if mv is None else round(mv[0], 1))
    return vals


if __name__ == '__main__':
    ids = sys.argv[1:]
    bad = 0
    for ex in DATA['exercises']:
        if ids and ex['id'] not in ids:
            continue
        e = check(ex)
        if e:
            bad += 1
            print('FAIL', ex['id'], ex['metric']['measure'], ex['thresholds'])
            for x in e:
                print('   ', x)
            print('    trace', trace(ex))
        elif ids:
            print('ok', ex['id'], trace(ex))
    print('%d failing' % bad)
