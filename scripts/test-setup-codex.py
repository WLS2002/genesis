#!/usr/bin/env python3
"""Process-level setup tests with a local MCP fixture and a disposable Codex CLI."""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SETUP = ROOT / "scripts/setup-codex.py"

SERVER = r'''
import json,os,sys,subprocess
from http.server import BaseHTTPRequestHandler,HTTPServer
from pathlib import Path
root=Path(os.environ['SETUP_FIXTURE'])
if len(sys.argv)>1:
    if sys.argv[1]=='url':
        print(os.environ.get('STORED_DASHBOARD_URL',''));sys.exit(0)
    if sys.argv[1]=='start':
        with (root/'starts').open('a') as f:f.write('start\n')
        port=sys.argv[sys.argv.index('--port')+1]
        p=subprocess.Popen([sys.executable,__file__],env={**os.environ,'FIXTURE_PORT':port},stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
        (root/'pid').write_text(str(p.pid))
    sys.exit(0)
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*a):pass
    def do_POST(self):
        if os.environ.get('OLD_SERVER'):
            self.send_error(404);return
        r=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        expected='Bearer '+(Path(os.environ['XDG_CONFIG_HOME'])/'genesis/mcp-token').read_text().strip()
        if self.headers.get('Authorization')!=expected:self.send_error(401);return
        method=r['method']
        if method=='notifications/initialized':self.send_response(202);self.end_headers();return
        if method=='initialize':data={'serverInfo':{'name':'genesis'},'protocolVersion':'2025-11-25'}
        elif method=='tools/list':data={'tools':[{'name':x} for x in ['genesis_check','genesis_start_task','genesis_get_task','genesis_list_tasks','genesis_cancel_task','genesis_list_models','genesis_get_result','genesis_send_message','genesis_reload_config']]}
        else:data={'structuredContent':{'version':'test','model_ready':bool(os.environ.get('MODEL_READY')),'warnings':[], 'config_files':{'config':str(Path(os.environ['XDG_CONFIG_HOME'])/'genesis/config.toml'),'credentials':str(Path(os.environ['XDG_CONFIG_HOME'])/'genesis/credentials.toml')}}}
        body=json.dumps({'jsonrpc':'2.0','id':r['id'],'result':data}).encode()
        self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
HTTPServer(('127.0.0.1',int(os.environ['FIXTURE_PORT'])),Handler).serve_forever()
'''


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'config/genesis'
        self.config.mkdir(parents=True)
        (self.config/'config.toml').write_text('# preserve existing user model settings\n')
        self.launcher = self.root / 'genesis'
        self.launcher.write_text('#!/usr/bin/env python3\n'+SERVER)
        self.launcher.chmod(0o755)
        binary=self.root/'bin';binary.mkdir()
        codex=binary/'codex'
        codex.write_text('#!/usr/bin/env python3\nimport os,json,sys\nfrom pathlib import Path\np=Path(os.environ["SETUP_FIXTURE"])/"codex-calls"\nwith p.open("a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\n')
        codex.chmod(0o755)
        with socket.socket() as s:
            s.bind(('127.0.0.1',0));self.port=s.getsockname()[1]
        self.env={**os.environ,'SETUP_FIXTURE':str(self.root),'XDG_CONFIG_HOME':str(self.root/'config'),
                  'XDG_DATA_HOME':str(self.root/'data'),'PATH':str(binary)+os.pathsep+os.environ['PATH']}
        self.addCleanup(self.stop)

    def stop(self):
        p=self.root/'pid'
        if p.exists():
            try:os.killpg(int(p.read_text()),signal.SIGTERM)
            except ProcessLookupError:pass

    def run_setup(self, saved_url=False):
        url_args=[] if saved_url else ['--url',f'http://127.0.0.1:{self.port}/mcp']
        return subprocess.run(['python3',str(SETUP),'--server-command',str(self.launcher),
            *url_args,'--config-dir',str(self.config),
            '--codex-home',str(self.root/'codex'),'--json'],env=self.env,capture_output=True,text=True,timeout=30)

    def test_cold_setup_reports_needed_model_input_and_reuses_service_on_rerun(self):
        first=self.run_setup()
        self.assertEqual(first.returncode,2,first.stderr)
        data=json.loads(first.stdout)
        self.assertEqual(data['status'],'needs_model_configuration')
        self.assertTrue(data['plugin_installed'])
        self.assertTrue(data['service_started'])
        self.assertEqual(data['config_files']['config'],str(self.config/'config.toml'))
        self.assertEqual(data['config_files']['credentials'],str(self.config/'credentials.toml'))
        self.assertTrue(any('genesis_reload_config' in step for step in data['next_steps']))
        self.assertFalse(any('/settings' in step for step in data['next_steps']))
        second=self.run_setup();self.assertEqual(second.returncode,2,second.stderr)
        self.assertFalse(json.loads(second.stdout)['service_started'])
        self.assertEqual((self.root/'starts').read_text().splitlines(),['start'])
        self.assertEqual((self.config/'config.toml').read_text(),'# preserve existing user model settings\n')
        provenance=self.config/'codex/plugins/genesis/skills/genesis/references/installation.json'
        self.assertEqual(json.loads(provenance.read_text())['source_root'],str(ROOT))
        self.assertEqual((self.config/'mcp-token').stat().st_mode&0o777,0o600)

    def test_ready_configuration_is_not_reported_as_a_provider_connectivity_test(self):
        self.env['MODEL_READY']='1'
        run=self.run_setup();self.assertEqual(run.returncode,0,run.stderr)
        data=json.loads(run.stdout)
        self.assertEqual(data['status'],'ready')
        self.assertFalse(data['provider_connection_tested'])

    def test_saved_lifecycle_url_is_reused_when_no_url_is_given(self):
        first=self.run_setup();self.assertEqual(first.returncode,2,first.stderr)
        self.env['STORED_DASHBOARD_URL']=f'http://127.0.0.1:{self.port}'
        rerun=self.run_setup(saved_url=True);self.assertEqual(rerun.returncode,2,rerun.stderr)
        self.assertFalse(json.loads(rerun.stdout)['service_started'])
        self.assertEqual((self.root/'starts').read_text().splitlines(),['start'])

    def test_occupied_incompatible_server_is_not_restarted_or_replaced(self):
        self.env['OLD_SERVER']='1'
        first=self.run_setup()
        self.assertEqual(first.returncode,1,first.stderr)
        before=(self.root/'starts').read_text()
        again=self.run_setup();self.assertEqual(again.returncode,1,again.stderr)
        self.assertEqual((self.root/'starts').read_text(),before)
        self.assertEqual(json.loads(again.stdout)['status'],'error')
        self.assertFalse((self.root/'codex-calls').exists())


if __name__=='__main__':unittest.main()
