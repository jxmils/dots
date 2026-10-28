"""Validate every generated strip before packing it into app assets."""
from build import P, COUNTS, extract
import json

counts = {**COUNTS, 'move-left': 8}
report = {'checked': 0, 'failures': []}
for path in sorted(P.glob('*/*-source.png')):
    state = path.name.removesuffix('-source.png')
    if state not in counts:
        continue
    try:
        extract(path, counts[state])
    except Exception as error:
        report['failures'].append({'id': path.parent.name, 'state': state, 'error': str(error)})
        print('FAIL', path.parent.name, state, error, flush=True)
    report['checked'] += 1
    (P / 'source-audit.json').write_text(json.dumps(report, indent=2) + '\n')
print('Checked', report['checked'], 'strips;', len(report['failures']), 'need correction', flush=True)
