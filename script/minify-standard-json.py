"""
Strip comments and blank lines from every source in a solc standard-json input.

Why this exists: some Blockscout deployments sit behind a WAF that rejects
verification payloads somewhere between 64KB and 128KB. Our standard-json is
~210KB because it carries all 34 OpenZeppelin sources. Comments and whitespace
do not reach the bytecode (foundry.toml sets bytecode_hash="none" and
cbor_metadata=false), so stripping them halves the payload while recompiling to
byte-identical output -- verified by script/verify-contracts.sh before each
submission is even attempted.

    python3 script/minify-standard-json.py in.json out.json
"""
import json, sys

def strip(src: str) -> str:
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i+1] == '/':
            while i < n and src[i] != '\n': i += 1
        elif c == '/' and i + 1 < n and src[i+1] == '*':
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i+1] == '/'): i += 1
            i += 2
        elif c in '"\'':
            q = c; out.append(c); i += 1
            while i < n:
                if src[i] == '\\': out.append(src[i:i+2]); i += 2; continue
                out.append(src[i])
                if src[i] == q: i += 1; break
                i += 1
        else:
            out.append(c); i += 1
    # collapse blank lines and trailing whitespace
    lines = [l.rstrip() for l in ''.join(out).split('\n')]
    return '\n'.join(l for l in lines if l.strip())

d = json.load(open(sys.argv[1]))
for path, obj in d['sources'].items():
    obj['content'] = strip(obj['content'])
json.dump(d, open(sys.argv[2], 'w'), separators=(',', ':'))
