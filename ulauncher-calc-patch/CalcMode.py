import re
import ast
import math
from decimal import Decimal
import operator as op

from ulauncher.api.shared.action.RenderResultListAction import RenderResultListAction
from ulauncher.search.BaseSearchMode import BaseSearchMode
from ulauncher.search.calc.CalcResultItem import CalcResultItem, CalcHistoryItem
from ulauncher.search.calc.CalcHistory import load_history


# supported operators
operators = {ast.Add: op.add, ast.Sub: op.sub, ast.Mult: op.mul,
             ast.Div: op.truediv, ast.Pow: op.pow, ast.BitXor: op.xor,
             ast.Mod: op.mod, ast.USub: op.neg}

# supported bare constants, e.g. "2*pi"
constants = {
    'pi': Decimal(str(math.pi)),
    'tau': Decimal(str(math.tau)),
    'e': Decimal(str(math.e)),
    'phi': Decimal(str((1 + math.sqrt(5)) / 2)),
}

def _factorial(x):
    if x != int(x):
        raise ValueError('factorial expects an integer')
    return math.factorial(int(x))


# supported functions; computed in float, converted back to Decimal.
# sin/cos/tan take radians (standard math convention); sind/cosd/tand
# are the degree-based variants for quick everyday use.
functions = {
    'sqrt': math.sqrt,
    'cbrt': lambda x: math.copysign(abs(x) ** (1 / 3), x),
    'sin': math.sin,
    'cos': math.cos,
    'tan': math.tan,
    'asin': math.asin,
    'acos': math.acos,
    'atan': math.atan,
    'sind': lambda x: math.sin(math.radians(x)),
    'cosd': lambda x: math.cos(math.radians(x)),
    'tand': lambda x: math.tan(math.radians(x)),
    'log10': math.log10,
    'log2': math.log2,
    'log': math.log10,
    'ln': math.log,
    'exp': math.exp,
    'abs': abs,
    'floor': math.floor,
    'ceil': math.ceil,
    'round': round,
    'fact': _factorial,
}

# Function names only enable calc mode when immediately followed by "(",
# since a bare word like "log" or "cos" could otherwise hijack an app
# search (e.g. "coscheduler", "logs"). Constants stay bare (e.g. "2*pi").
_FUNC_ALT = '|'.join(sorted(functions, key=len, reverse=True))
_CONST_ALT = '|'.join(sorted(constants, key=len, reverse=True))
_TOKEN = rf'(?:[\d\*+\/\-\.,e\(\)\^% ]|(?:{_FUNC_ALT})\(|(?:{_CONST_ALT})\b)'
_RE_CALC_SRC = rf'^(?:[\d\-\(\.,]|(?:{_FUNC_ALT})\(|(?:{_CONST_ALT})\b){_TOKEN}*$'

# "hist" / "history" (with optional surrounding whitespace) shows the calc
# history list instead of evaluating an expression.
_RE_HISTORY = re.compile(r'^\s*hist(?:ory)?\s*$', re.IGNORECASE)


def eval_expr(expr):
    """
    >>> eval_expr('2^6')
    64
    >>> eval_expr('2**6')
    64
    >>> eval_expr('2*6+')
    12
    >>> eval_expr('1 + 2*3**(4^5) / (6 + -7)')
    -5.0
    """
    expr = expr.replace("^", "**").replace(",", ".")
    try:
        return _eval(ast.parse(expr, mode='eval').body)
    # pylint: disable=broad-except
    except Exception:
        # if failed, try without the last symbol
        return _eval(ast.parse(expr[:-1], mode='eval').body)


def _eval(node):
    if isinstance(node, ast.Num):  # <number>
        return Decimal(str(node.n))
    if isinstance(node, ast.BinOp):  # <left> <operator> <right>
        return operators[type(node.op)](_eval(node.left), _eval(node.right))
    if isinstance(node, ast.UnaryOp):  # <operator> <operand> e.g., -1
        return operators[type(node.op)](_eval(node.operand))
    if isinstance(node, ast.Name):  # <constant> e.g. pi, e, tau, phi
        try:
            return constants[node.id.lower()]
        except KeyError:
            raise TypeError(node)
    if isinstance(node, ast.Call):  # <function>(<args>) e.g. sqrt(2)
        if not isinstance(node.func, ast.Name):
            raise TypeError(node)
        func_name = node.func.id.lower()
        if func_name not in functions:
            raise TypeError(node)
        args = [float(_eval(arg)) for arg in node.args]
        return Decimal(str(functions[func_name](*args)))

    raise TypeError(node)


class CalcMode(BaseSearchMode):
    RE_CALC = re.compile(_RE_CALC_SRC, flags=re.IGNORECASE)

    def is_enabled(self, query):
        return bool(re.match(self.RE_CALC, query)) or bool(_RE_HISTORY.match(query))

    def handle_query(self, query):
        if _RE_HISTORY.match(query):
            return self._render_history()

        try:
            result = eval_expr(query)
            if result is None:
                raise ValueError()

            # fixes issue with division where result is represented as a float (e.g., 1.0)
            # although it is an integer (1)
            if int(result) == result:
                result = int(result)

            items = [CalcResultItem(result=result)] + self._recent_history_items(query)
        # pylint: disable=broad-except
        except Exception:
            items = [CalcResultItem(error='Invalid expression')]
        return RenderResultListAction(items)

    def _recent_history_items(self, current_query, limit=5):
        """Recent history entries shown below a live calc result, so the
        history is visible while calculating without typing hist/history.
        Skips an entry that's identical to what's currently being typed,
        since that would just duplicate the live result above it."""
        current_expr = current_query.strip()
        items = []
        for entry in reversed(load_history()):
            if entry['expr'] == current_expr:
                continue
            items.append(CalcHistoryItem(entry['expr'], entry['result']))
            if len(items) >= limit:
                break
        return items

    def _render_history(self):
        history = load_history()
        if not history:
            return RenderResultListAction([CalcResultItem(error='No calc history yet')])
        items = [CalcHistoryItem(entry['expr'], entry['result']) for entry in reversed(history)]
        return RenderResultListAction(items)
