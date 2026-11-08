#!/usr/bin/env python3
"""Install/reuse Genesis for any HTTP MCP host; Codex registration is optional."""
import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('genesis_setup', Path(__file__).with_name('setup-codex.py'))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)
if __name__ == '__main__':
    sys.exit(setup.main(default_agent='none'))
