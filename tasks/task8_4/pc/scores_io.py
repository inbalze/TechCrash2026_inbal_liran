"""Shared high-score persistence for all hub games.

Usage:
    import scores_io
    scores_io.save('pacman', 12400)    # only writes if new value is higher
    scores = scores_io.load()          # {'dino':0, 'pacman':0, 'shooter':0, 'simon':0}
"""

import json
import os

_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'scores.json')
_KEYS = ('dino', 'pacman', 'shooter', 'simon')


def load():
    try:
        with open(_FILE) as f:
            d = json.load(f)
        return {k: d.get(k, 0) for k in _KEYS}
    except Exception:
        return {k: 0 for k in _KEYS}


def save(key, value):
    """Persist a new score only if it beats the current record."""
    value = int(value)
    scores = load()
    if value > scores.get(key, 0):
        scores[key] = value
        try:
            with open(_FILE, 'w') as f:
                json.dump(scores, f, indent=2)
        except Exception:
            pass
