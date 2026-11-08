"""Write the runtime's immutable MCP identity before archiving a release."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def identity(platform):
    version = json.loads((ROOT/'plugins/genesis/.codex-plugin/plugin.json').read_text())['version']
    return {'revision': subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip(),
            'release': 'mcp-preview-'+version, 'platform': platform}

def stamp(release, platform):
    metadata = identity(platform)
    libraries = list(Path(release).glob('lib/evo_git-*/priv'))
    if len(libraries) != 1:
        raise ValueError('Expected exactly one evo_git library in the release.')
    (libraries[0]/'mcp-build-info.json').write_text(json.dumps(metadata, indent=2)+'\n', encoding='utf-8')
    return metadata
