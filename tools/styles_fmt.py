"""Write styles.json in its own layout: each key/feel entry on one line, short lists on one line."""
import json


def flat(v):
    return isinstance(v, list) and all(not isinstance(x, (dict, list)) or (isinstance(x, list) and all(not isinstance(y, (dict, list)) for y in x)) for x in v)


def enc(v, ind="", in_list=False):
    if isinstance(v, dict):
        if not v:
            return "{}"
        inner = ind + "  "
        return "{\n" + ",\n".join(inner + json.dumps(k, ensure_ascii=False) + ": " + enc(x, inner) for k, x in v.items()) + "\n" + ind + "}"
    if isinstance(v, list):
        if not v:
            return "[]"
        if flat(v):
            one = json.dumps(v, ensure_ascii=False, separators=(", ", ": "))
            if in_list or len(one) < 108:
                return one
        inner = ind + "  "
        return "[\n" + ",\n".join(inner + enc(x, inner, True) for x in v) + "\n" + ind + "]"
    return json.dumps(v, ensure_ascii=False)


def dump(d, path):
    open(path, "w", encoding="utf-8", newline="\n").write(enc(d) + "\n")
