import os
import json

from ulauncher.config import DATA_DIR

HISTORY_FILE = os.path.join(DATA_DIR, 'calc_history.json')
MAX_HISTORY = 50


def load_history():
    try:
        with open(HISTORY_FILE, encoding='utf-8') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return []


def save_history_entry(expr, result):
    expr = expr.strip()
    history = load_history()
    if history and history[-1]['expr'] == expr and history[-1]['result'] == str(result):
        return
    history.append({'expr': expr, 'result': str(result)})
    history = history[-MAX_HISTORY:]
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
        with open(HISTORY_FILE, 'w', encoding='utf-8') as f:
            json.dump(history, f)
    except OSError:
        pass
