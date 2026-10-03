"""Generate offline Dart runtime license data; never download or rewrite texts."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
bundles = []
for path in sorted((root / 'tool/runtime_licenses').glob('*/manifest.json')):
    manifest = json.loads(path.read_text(encoding='utf-8'))
    if manifest['schemaVersion'] != 1:
        raise ValueError(f'Unsupported manifest: {path}')
    if not isinstance(manifest['complete'], bool) or manifest['complete'] != (not bool(manifest['issues'])):
        raise ValueError(f'Inconsistent runtime coverage declaration: {path}')
    if not manifest['targets'] or not manifest['components']:
        raise ValueError(f'Empty runtime bundle: {path}')
    for component in manifest['components']:
        for document in component['documents']:
            data = (path.parent / document['path']).read_bytes()
            if hashlib.sha256(data).hexdigest() != document.pop('sha256'):
                raise ValueError(f'License content hash mismatch: {path}: {document["path"]}')
            document['text'] = data.decode('utf-8')
            document['path'] = f'{manifest["sdkVersion"]}/{document["path"]}'
    bundles.append(manifest)
encoded = json.dumps(bundles, ensure_ascii=False, indent=2)
if "'''" in encoded:
    raise ValueError('Cannot encode raw Dart string delimiter')
target = root / 'lib/src/licenses/runtime_data.g.dart'
target.write_text(
    '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
    '// Source: tool/runtime_licenses; generator: tool/generate_runtime_licenses.py.\n\n'
    "/// Original runtime license texts embedded for offline source and AOT use.\n"
    f"const String runtimeLicenseData = r'''{encoded}''';\n",
    encoding='utf-8',
)
