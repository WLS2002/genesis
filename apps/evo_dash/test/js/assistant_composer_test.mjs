import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const source = await readFile(new URL('../../assets/js/hooks/assistant_composer.js', import.meta.url), 'utf8');
const { default: Composer } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

class MemoryStorage {
  values = new Map();
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, String(value)); }
  removeItem(key) { this.values.delete(key); }
}
class Textarea extends EventTarget {
  value = '';
  style = {};
  scrollHeight = 72;
  focusCount = 0;
  focusOptions = undefined;
  focus(options) { this.focusCount++; this.focusOptions = options; }
}
class Form extends EventTarget {
  dataset = { chatId: 'chat-1', scope: 'local', busy: 'false', draft: '' };
  textarea = new Textarea();
  submits = 0;
  submission = { value: '' };
  querySelector(selector) {
    if (selector === '#assistant-submission') return this.submission;
    assert.equal(selector, '#assistant-message'); return this.textarea;
  }
  requestSubmit() { this.submits++; this.dispatchEvent(new Event('submit', { cancelable: true })); }
}
const draftKey = (scope, chat) => `genesis:assistant-draft:${encodeURIComponent(scope)}:${encodeURIComponent(chat)}`;
function create(storage = new MemoryStorage(), dataset = {}) {
  globalThis.window = { sessionStorage: storage, getComputedStyle: () => ({ minHeight: '48px', maxHeight: '240px' }) };
  const el = new Form(); Object.assign(el.dataset, dataset);
  const handlers = new Map(); const pushed = [];
  const hook = Object.assign({ el, handleEvent: (name, handler) => { handlers.set(name, handler); return name; }, removeHandleEvent: name => handlers.delete(name), pushEvent: (name, payload) => pushed.push({ name, payload }) }, Composer);
  hook.mounted();
  return { hook, el, textarea: el.textarea, storage, handlers, pushed };
}
function key(target, options = {}) {
  const event = new Event('keydown', { cancelable: true, bubbles: true });
  for (const [name, value] of Object.entries({ key: 'Enter', shiftKey: false, isComposing: false, keyCode: 13, ...options })) Object.defineProperty(event, name, { value });
  target.dispatchEvent(event); return event;
}
function input(state, text) { state.textarea.value = text; state.textarea.dispatchEvent(new Event('input', { bubbles: true })); }

test('Enter submits once, prevents a newline and preserves the draft until acceptance', () => {
  const s = create(); input(s, '修改布局');
  const event = key(s.textarea);
  assert.equal(s.el.submits, 1); assert.equal(event.defaultPrevented, true);
  assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), '修改布局');
});
test('Shift+Enter retains native multiline input', () => {
  const s = create(); const event = key(s.textarea, { shiftKey: true });
  assert.equal(s.el.submits, 0); assert.equal(event.defaultPrevented, false);
});
test('all IME confirmation signals leave Enter to the input method', () => {
  for (const options of [{ isComposing: true }, { keyCode: 229 }]) {
    const s = create(); const event = key(s.textarea, options);
    assert.equal(s.el.submits, 0); assert.equal(event.defaultPrevented, false);
  }
  const s = create(); s.textarea.dispatchEvent(new Event('compositionstart'));
  assert.equal(key(s.textarea).defaultPrevented, false); assert.equal(s.el.submits, 0);
  s.textarea.dispatchEvent(new Event('compositionend'));
  assert.equal(key(s.textarea).defaultPrevented, false); assert.equal(s.el.submits, 0);
});
test('busy Enter keeps editable draft without submitting or inserting a newline', () => {
  const s = create(undefined, { busy: 'true' }); input(s, '下一条需求');
  assert.equal(key(s.textarea).defaultPrevented, true); assert.equal(s.el.submits, 0);
  assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), '下一条需求');
});
test('draft restores after remount and synchronizes the server', () => {
  const storage = new MemoryStorage(); const s = create(storage); input(s, '还没有发送'); s.hook.destroyed();
  const restored = create(storage);
  assert.equal(restored.textarea.value, '还没有发送');
  assert.deepEqual(restored.pushed, [{ name: 'chat_input', payload: { message: '还没有发送' } }]);
});
test('conversation and node scope separate drafts, including explicitly cleared drafts', () => {
  const s = create(); input(s, '会话一');
  s.el.dataset.chatId = 'chat-2'; s.textarea.value = ''; s.hook.updated();
  assert.equal(s.textarea.value, ''); input(s, '会话二');
  s.el.dataset.scope = 'remote'; s.textarea.value = ''; s.hook.updated(); assert.equal(s.textarea.value, '');
  s.el.dataset.scope = 'local'; s.el.dataset.chatId = 'chat-1'; s.textarea.value = ''; s.hook.updated();
  assert.equal(s.textarea.value, '会话一'); input(s, ''); s.hook.destroyed();
  const restored = create(s.storage, { draft: '服务器旧草稿' }); assert.equal(restored.textarea.value, '');
});
test('a stale server patch does not overwrite text typed after its snapshot', () => {
  const s = create(undefined, { draft: '第一段' }); input(s, '第一段，加上新内容');
  s.textarea.value = '第一段'; s.hook.updated();
  assert.equal(s.textarea.value, '第一段，加上新内容');
});
test('explicit server prefill updates an unchanged draft', () => {
  const s = create(); s.el.dataset.draft = '帮我查看任务'; s.textarea.value = '帮我查看任务'; s.hook.updated();
  assert.equal(s.textarea.value, '帮我查看任务');
});
test('successful submission clears only its accepted text, not subsequent input', () => {
  const s = create(); input(s, '已发送'); key(s.textarea);
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '已发送' });
  assert.equal(s.textarea.value, ''); assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), null);
  input(s, '第二条'); key(s.textarea); input(s, '第三条正在起草');
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '第二条' });
  assert.equal(s.textarea.value, '第三条正在起草');
  assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), '第三条正在起草');
});
test('acceptance from another conversation never clears the current draft', () => {
  const s = create(); input(s, '会话一发送内容'); key(s.textarea);
  s.el.dataset.chatId = 'chat-2'; s.textarea.value = ''; s.hook.updated(); input(s, '会话二草稿');
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '会话一发送内容' });
  assert.equal(s.textarea.value, '会话二草稿'); assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), null);
});
test('autogrow caps long drafts and releases scrolling for short input', () => {
  const s = create(); s.textarea.scrollHeight = 600; input(s, '长文本');
  assert.equal(s.textarea.style.height, '240px'); assert.equal(s.textarea.style.overflowY, 'auto');
  s.textarea.scrollHeight = 60; input(s, '短'); assert.equal(s.textarea.style.height, '60px'); assert.equal(s.textarea.style.overflowY, 'hidden');
});
test('destroy removes input, keyboard and server-event listeners', () => {
  const s = create(); s.hook.destroyed(); input(s, '不再保存'); key(s.textarea);
  assert.equal(s.el.submits, 0); assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), null); assert.equal(s.handlers.size, 0);
});
test('late draft clearing after acceptance does not eat a newly typed follow-up', () => {
  const s = create(undefined, { draft: '已发送' }); input(s, '已发送'); key(s.textarea);
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '已发送' });
  input(s, '随后起草的内容'); s.el.dataset.draft = ''; s.textarea.value = ''; s.hook.updated();
  assert.equal(s.textarea.value, '随后起草的内容');
  assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), '随后起草的内容');
});
test('editing remains functional when the browser blocks session storage', () => {
  const unavailable = { getItem() { throw Error('blocked'); }, setItem() { throw Error('blocked'); }, removeItem() { throw Error('blocked'); } };
  const s = create(unavailable); input(s, '本地编辑仍可用'); key(s.textarea);
  assert.equal(s.el.submits, 1); assert.equal(s.textarea.value, '本地编辑仍可用');
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '本地编辑仍可用' }); assert.equal(s.textarea.value, '');
});

test('explicit draft action replaces the current draft, saves it, resizes and focuses', () => {
  const s = create(); input(s, '用户原草稿'); s.textarea.scrollHeight = 120;
  s.handlers.get('assistant:draft')({ chat_id: 'chat-1', text: '查看当前任务' });
  assert.equal(s.textarea.value, '查看当前任务');
  assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), '查看当前任务');
  assert.equal(s.textarea.style.height, '120px'); assert.equal(s.textarea.focusCount, 1);
  s.hook.updated(); assert.equal(s.textarea.value, '查看当前任务');
});
test('draft and focus actions from another chat do not affect the current editor', () => {
  const s = create(); input(s, '保持我的草稿');
  s.handlers.get('assistant:draft')({ chat_id: 'chat-other', text: '其他会话' });
  s.handlers.get('assistant:focus')({ chat_id: 'chat-other' });
  assert.equal(s.textarea.value, '保持我的草稿'); assert.equal(s.textarea.focusCount, 0);
});
test('explicit focus acts on the current chat, while ordinary patches never steal focus', () => {
  const s = create(); s.hook.updated(); assert.equal(s.textarea.focusCount, 0);
  s.handlers.get('assistant:focus')({ chat_id: 'chat-1' });
  assert.equal(s.textarea.focusCount, 1); assert.deepEqual(s.textarea.focusOptions, { preventScroll: true });
  s.hook.updated(); assert.equal(s.textarea.focusCount, 1);
});
test('explicit draft rejects malformed text and all action handlers are removed on destroy', () => {
  const s = create(); input(s, '保留');
  s.handlers.get('assistant:draft')({ chat_id: 'chat-1', text: null });
  assert.equal(s.textarea.value, '保留'); assert.equal(s.textarea.focusCount, 0);
  assert.equal(s.handlers.size, 3); s.hook.destroyed(); assert.equal(s.handlers.size, 0);
});
test('same text retyped after submission is a new draft, not the accepted submission', () => {
  const s = create(undefined, { draft: '继续' }); input(s, '继续'); key(s.textarea);
  input(s, ''); input(s, '继续');
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '继续' });
  assert.equal(s.textarea.value, '继续');
  assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), '继续');
});
test('server empty patch before acceptance preserves a retyped same-text revision', () => {
  const s = create(undefined, { draft: '继续' }); input(s, '继续'); s.el.requestSubmit();
  input(s, ''); input(s, '继续'); s.el.dataset.draft = ''; s.textarea.value = ''; s.hook.updated();
  assert.equal(s.textarea.value, '继续');
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '继续' });
  assert.equal(s.textarea.value, '继续'); assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), '继续');
});
test('late receipt for an old chat preserves its newer cached same-text draft', () => {
  const s = create(undefined, { draft: '继续' }); input(s, '继续'); s.el.requestSubmit();
  input(s, ''); input(s, '继续');
  s.el.dataset.chatId = 'chat-2'; s.el.dataset.draft = ''; s.textarea.value = ''; s.hook.updated(); input(s, '当前草稿');
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '继续' });
  assert.equal(s.textarea.value, '当前草稿'); assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), '继续');
  s.el.dataset.chatId = 'chat-1'; s.textarea.value = ''; s.hook.updated(); assert.equal(s.textarea.value, '继续');
});
test('both Enter and button form submissions attach distinct correlation tokens', () => {
  const s = create(); input(s, '第一条'); key(s.textarea); const first = s.el.submission.value;
  assert.ok(first); input(s, '第二条'); s.el.requestSubmit(); assert.ok(s.el.submission.value); assert.notEqual(s.el.submission.value, first);
});
test('out-of-order same-text receipts clear only their submitted revision', () => {
  const s = create(undefined, { draft: '继续' }); input(s, '继续'); key(s.textarea); const first = s.el.submission.value;
  input(s, ''); input(s, '继续'); s.el.requestSubmit(); const second = s.el.submission.value;
  s.el.dataset.draft = ''; s.textarea.value = ''; s.hook.updated(); assert.equal(s.textarea.value, '继续');
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '继续', submission_id: first }); assert.equal(s.textarea.value, '继续');
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '继续', submission_id: second });
  assert.equal(s.textarea.value, ''); assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), null);
});
test('a successful retry token is distinguishable from an earlier rejected same-text submission', () => {
  const s = create(); input(s, '继续'); s.el.requestSubmit();
  input(s, ''); input(s, '继续'); s.el.requestSubmit(); const accepted = s.el.submission.value;
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '继续', submission_id: accepted });
  assert.equal(s.textarea.value, ''); assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), null);
});
test('empty server patch waits for the corresponding acceptance even for an unchanged draft', () => {
  const s = create(undefined, { draft: '继续' }); input(s, '继续'); s.el.requestSubmit(); const token = s.el.submission.value;
  s.el.dataset.draft = ''; s.textarea.value = ''; s.hook.updated();
  assert.equal(s.textarea.value, '继续'); assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), '继续');
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '继续', submission_id: token }); assert.equal(s.textarea.value, '');
});
test('unknown tokens and duplicate acknowledgements cannot clear later drafts', () => {
  const s = create(); input(s, '继续'); key(s.textarea); const token = s.el.submission.value;
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '继续', submission_id: 'unknown' }); assert.equal(s.textarea.value, '继续');
  s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '继续', submission_id: token });
  input(s, '继续'); s.handlers.get('assistant:sent')({ chat_id: 'chat-1', text: '继续', submission_id: token });
  assert.equal(s.textarea.value, '继续'); assert.equal(s.storage.getItem(draftKey('local', 'chat-1')), '继续');
});
test('destroy also unregisters submission token capture', () => {
  const s = create(); input(s, '内容'); s.el.requestSubmit(); const token = s.el.submission.value;
  s.hook.destroyed(); s.el.requestSubmit(); assert.equal(s.el.submission.value, token);
});
