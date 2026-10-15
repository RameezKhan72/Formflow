"""Maps Z-Anatomy muscle names to FormFlow's 14 muscle IDs."""
RULES = [
    ('chest', ['pectoralis major', 'pectoralis minor']),
    ('abs', ['rectus abdominis', 'pyramidalis']),
    ('obliques', ['external oblique', 'internal oblique', 'external abdominal oblique', 'internal abdominal oblique']),
    ('lats', ['latissimus dorsi', 'teres major']),
    ('traps', ['trapezius']),
    ('shoulders', ['deltoid']),
    ('biceps', ['biceps brachii', 'brachialis muscle', 'coracobrachialis']),
    ('triceps', ['triceps brachii', 'anconeus']),
    ('forearms', ['brachioradialis', 'flexor carpi', 'extensor carpi', 'pronator teres', 'palmaris longus',
                  'flexor digitorum superficialis', 'extensor digitorum muscle', 'extensor digiti minimi muscle',
                  'abductor pollicis longus', 'extensor pollicis']),
    ('lower_back', ['erector spinae', 'iliocostalis', 'longissimus thoracis', 'longissimus', 'spinalis thoracis',
                    'quadratus lumborum', 'multifidus']),
    ('glutes', ['gluteus']),
    ('quads', ['rectus femoris', 'vastus', 'adductor longus', 'adductor magnus', 'adductor brevis', 'gracilis', 'pectineus']),
    ('hamstrings', ['biceps femoris', 'semitendinosus', 'semimembranosus']),
    ('calves', ['gastrocnemius', 'soleus', 'tibialis anterior', 'fibularis longus', 'fibularis brevis', 'peroneus']),
]
SKIP_WORDS = ('iliotibial tract', 'fascia', 'bursa', 'sheath', 'cross section', 'septum', 'retinaculum', 'aponeurosis of', 'ligament')


def group_of(name):
    n = name.lower()
    if 'arytenoid' in n or 'capitis' in n or 'of foot' in n and 'extensor digitorum' in n:
        return None
    for gid, words in RULES:
        if any(w in n for w in words):
            return gid
    return None


def is_label(name):
    base = name.rsplit('.', 1)
    return len(base) == 2 and base[1] in ('i', 'j', 'g', 't', 'e')
