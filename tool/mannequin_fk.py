"""Python port of lib/domain/demo_motion.dart (MannequinRig). Used by the
build tools so 2D demos, the engine and the 3D models share one source of
truth: the keyframes in assets/data/exercises.json."""
import math

D0 = dict(shin=.23, thigh=.24, torso=.29, neck=.05, headR=.052, upperArm=.16, forearm=.15,
          footFwd=.085, heelBack=.03, footDrop=.035, floorY=.93, hipHalf=.055, shoulderHalf=.095)
RAD = {'head': .052, 'shoulder': .04, 'hip': .045, 'knee': .028, 'elbow': .022, 'wrist': .015, 'ankle': .02}


def d(a):
    r = math.radians(a)
    return (math.sin(r), -math.cos(r))


def add(p, v, k=1.0):
    return (p[0] + v[0] * k, p[1] + v[1] * k)


def complete(m):
    m = dict(m)
    for k, dv in [('shin', 0), ('thigh', 0), ('torso', 0), ('upperArm', 180), ('forearm', 180), ('foot', 90)]:
        m.setdefault(k, dv)
    for k in ['shin', 'thigh', 'foot', 'upperArm', 'forearm']:
        m.setdefault(k + '2', m[k])
    m.setdefault('head', m['torso'])
    return m


def lerp(a, b, u):
    return {k: a[k] + (b[k] - a[k]) * u for k in a}


def _foot(j, s, ankle, fa, D):
    al, dn = d(fa), d(fa + 90)
    j['toe' + s] = add(add(ankle, al, D['footFwd']), dn, D['footDrop'])
    j['heel' + s] = add(add(ankle, al, -D['heelBack']), dn, D['footDrop'])


def side(kf, a):
    k = kf.get('scale', 1.0)
    D = dict(D0)
    for n in ['shin', 'thigh', 'torso', 'neck', 'headR', 'upperArm', 'forearm', 'footFwd', 'heelBack', 'footDrop']:
        D[n] = D0[n] * k
    j = {'ankle': (0.0, 0.0)}
    j['knee'] = add(j['ankle'], d(a['shin']), D['shin'])
    j['hip'] = add(j['knee'], d(a['thigh']), D['thigh'])
    j['shoulder'] = add(j['hip'], d(a['torso']), D['torso'])
    j['neck'] = add(j['shoulder'], d(a['head']), D['neck'])
    j['head'] = add(j['neck'], d(a['head']), D['headR'])
    j['elbow'] = add(j['shoulder'], d(a['upperArm']), D['upperArm'])
    j['wrist'] = add(j['elbow'], d(a['forearm']), D['forearm'])
    _foot(j, '', j['ankle'], a['foot'], D)
    j['knee2'] = add(j['hip'], d(a['thigh2'] + 180), D['thigh'])
    j['ankle2'] = add(j['knee2'], d(a['shin2'] + 180), D['shin'])
    _foot(j, '2', j['ankle2'], a['foot2'], D)
    j['elbow2'] = add(j['shoulder'], d(a['upperArm2']), D['upperArm'])
    j['wrist2'] = add(j['elbow2'], d(a['forearm2']), D['forearm'])
    if kf.get('anchor') == 'wrist':
        sh = (kf['anchorX'] - j['wrist'][0], kf['anchorY'] - j['wrist'][1])
    else:
        my = -1e9
        for key, p in j.items():
            if key == 'neck':
                continue
            if kf.get('armIk') and (key.startswith('wrist') or key.startswith('elbow')):
                continue
            my = max(my, p[1] + RAD.get(key.replace('2', ''), 0))
        sh = (kf.get('anchorX', .45) - j['ankle'][0], D0['floorY'] - my)
    for key in j:
        j[key] = add(j[key], sh)
    if kf.get('armIk'):
        for s in ['', '2']:
            shp = j['shoulder']
            t = (shp[0] + .015, D0['floorY'] - .012)
            tt = (t[0] - shp[0], t[1] - shp[1])
            dist = min(math.hypot(*tt), D['upperArm'] + D['forearm'] - 1e-4)
            base = math.atan2(tt[1], tt[0])
            c = max(-1, min(1, (D['upperArm'] ** 2 + dist ** 2 - D['forearm'] ** 2) / (2 * D['upperArm'] * dist)))
            aa = math.acos(c)
            e1 = (shp[0] + math.cos(base + aa) * D['upperArm'], shp[1] + math.sin(base + aa) * D['upperArm'])
            e2 = (shp[0] + math.cos(base - aa) * D['upperArm'], shp[1] + math.sin(base - aa) * D['upperArm'])
            e = e1 if e1[0] < e2[0] else e2
            dv = (t[0] - e[0], t[1] - e[1])
            L = math.hypot(*dv) or 1
            off = (-.008, -.004) if s == '2' else (0, 0)
            j['elbow' + s] = add(e, off)
            j['wrist' + s] = add(add(e, dv, D['forearm'] / L), off)
    return j, False


def front(kf, a):
    D = D0
    cx = kf.get('anchorX', .45)
    ankL = (cx + .07, D['floorY'] - D['footDrop'])
    kn = add(ankL, d(a['shin']), D['shin'])
    hp = add(kn, d(a['thigh']), D['thigh'])
    hc = (hp[0] - D['hipHalf'], hp[1])
    sc = add(hc, d(a['torso']), D['torso'])
    shL = (sc[0] + D['shoulderHalf'], sc[1])
    el = add(shL, d(a['upperArm']), D['upperArm'])
    wr = add(el, d(a['forearm']), D['forearm'])
    m = lambda p: (2 * cx - p[0], p[1])
    j = dict(ankle=ankL, knee=kn, hip=hp, shoulder=shL, elbow=el, wrist=wr, toe=add(ankL, (.02, .03)), heel=add(ankL, (0, .035)))
    for key in list(j):
        j[key + '2'] = m(j[key])
    j['neck'] = add(sc, d(a['torso']), D['neck'])
    j['head'] = add(j['neck'], d(a['torso']), D['headR'])
    return j, True


def u_at(t, period, timed=False, mistake=False):
    if timed:
        return 1.0 if mistake else 0.0
    base = 0.5 - 0.5 * math.cos(2 * math.pi * t / period)
    return base * 0.6 if mistake else base


def solve(kf, u):
    a = lerp(complete(kf['start']), complete(kf['end']), u)
    return front(kf, a) if kf.get('view') == 'front' else side(kf, a)
