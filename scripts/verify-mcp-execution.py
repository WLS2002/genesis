"""Exercise a real MCP task against an isolated, local chat-completions provider."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import subprocess
import threading
import time


def verify_execution(connector, url, token, config, project):
    requests = []
    failures = []
    checkpoint = 'Native execution checkpoint'
    finish_gate = threading.Event()

    class Provider(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            requests.append(body)
            tools = {tool['function']['name'] for tool in body.get('tools', [])}
            if 'report_progress' not in tools:
                failures.append('Runner did not expose report_progress')
            delivered = any(message.get('role') == 'tool' for message in body['messages'])
            if delivered:
                if not finish_gate.wait(30):
                    failures.append('Progress was not observed before completion')
                message = {'role': 'assistant', 'content': 'Native execution completed.'}
                finish = 'stop'
            else:
                message = {'role': 'assistant', 'content': None, 'tool_calls': [{
                    'id': 'call_progress', 'type': 'function', 'function': {
                        'name': 'report_progress', 'arguments': json.dumps({
                            'summary': checkpoint, 'completed': [checkpoint]})}}]}
                finish = 'tool_calls'
            base = {'id': 'native-smoke', 'model': 'deepseek-chat', 'created': 1}
            usage = {'prompt_tokens': 20, 'completion_tokens': 10, 'total_tokens': 30}
            if body.get('stream'):
                delta = dict(message)
                if 'tool_calls' in delta:
                    delta['tool_calls'] = [dict(call, index=i) for i, call in enumerate(delta['tool_calls'])]
                chunks = [dict(base, object='chat.completion.chunk', choices=[{'index': 0, 'delta': delta, 'finish_reason': None}]),
                          dict(base, object='chat.completion.chunk', choices=[{'index': 0, 'delta': {}, 'finish_reason': finish}], usage=usage)]
                payload = ''.join('data: ' + json.dumps(chunk) + '\n\n' for chunk in chunks) + 'data: [DONE]\n\n'
                content_type = 'text/event-stream'
            else:
                payload = json.dumps(dict(base, object='chat.completion', choices=[{'index': 0, 'message': message, 'finish_reason': finish}], usage=usage))
                content_type = 'application/json'
            encoded = payload.encode()
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

    provider = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
    thread = threading.Thread(target=provider.serve_forever, daemon=True)
    thread.start()
    original = (config / 'config.toml').read_bytes()
    credentials = (config / 'credentials.toml').read_bytes()
    task_id = None
    terminal = False

    def call(name, arguments):
        result = connector.rpc(url, token, 'tools/call', {'name': name, 'arguments': arguments})['result']
        assert not result.get('isError'), result
        return result['structuredContent']

    try:
        (config / 'credentials.toml').write_text('DEEPSEEK_API_KEY = \"offline-fixture\"\n', encoding='utf-8')
        (config / 'config.toml').write_text(
            '[llm]\ndefault_provider_profile = "offline"\n[[llm.providers]]\n'
            'id = "offline"\nprovider = "deepseek"\nauth_mode = "api_key"\n'
            f'base_url = "http://127.0.0.1:{provider.server_port}/v1"\n'
            'default_model = "deepseek-chat"\n[[llm.providers.models]]\nmodel = "deepseek-chat"\n', encoding='utf-8')
        call('genesis_reload_config', {})
        project.mkdir()
        for args in [['init'], ['config', 'user.name', 'Genesis smoke'], ['config', 'user.email', 'smoke@example.invalid']]:
            subprocess.run(['git', *args], cwd=project, check=True, capture_output=True)
        (project / 'README.md').write_text('Native task execution fixture.\n', encoding='utf-8')
        for args in [['add', 'README.md'], ['commit', '-m', 'Initialize fixture']]:
            subprocess.run(['git', *args], cwd=project, check=True, capture_output=True)
        started = call('genesis_start_task', {'path': str(project.resolve()), 'objective': 'Report your progress, then finish without editing files.',
            'task_type': 'evolve', 'mode': 'simple', 'model_id': 'offline',
            'budget': {'max_agents': 2, 'max_depth': 1, 'max_turns_root': 6, 'max_turns': 4, 'max_duration_seconds': 120}})
        task_id = started['task_id'] if 'task_id' in started else started['id']
        deadline = time.monotonic() + 150
        observed_revision = None
        while True:
            assert not failures, failures
            task = call('genesis_get_task', {'task_id': task_id})
            report = task['progress']['report'] or {}
            if observed_revision is None and checkpoint in report.get('completed', []):
                observed_revision = report['revision']
                finish_gate.set()
            if task['status'] in ['completed', 'failed', 'cancelled']:
                terminal = True
                break
            assert time.monotonic() < deadline, 'Native task did not complete within its bound'
            time.sleep(.25)
        assert task['status'] == 'completed', task
        assert observed_revision is not None, task
        assert task['progress']['report']['revision'] > observed_revision, task
        assert task['progress']['report']['summary'] == 'Native execution completed.', task
        assert not failures, failures
        assert len(requests) >= 2, 'The real Runner never completed the progress tool round trip'
        replies = [m for request in requests for m in request['messages'] if m.get('role') == 'tool']
        assert any('recorded' in str(m.get('content')) for m in replies), replies
        return {'task_execution': True, 'progress_tool_round_trip': True, 'local_provider_requests': len(requests)}
    finally:
        finish_gate.set()
        try:
            if task_id and not terminal:
                call('genesis_cancel_task', {'task_id': task_id, 'force': True, 'wait_seconds': 20})
        finally:
            (config / 'config.toml').write_bytes(original)
            (config / 'credentials.toml').write_bytes(credentials)
            try:
                call('genesis_reload_config', {})
            finally:
                provider.shutdown()
                provider.server_close()
                thread.join()
