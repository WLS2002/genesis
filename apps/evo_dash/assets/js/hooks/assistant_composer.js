const storageKey = (scope, chatId) =>
  chatId ? `genesis:assistant-draft:${encodeURIComponent(scope)}:${encodeURIComponent(chatId)}` : null;

// The server owns conversation state; this hook owns immediate text editing.
// Browser-local drafts bridge reconnects without making keystrokes wait for RPCs.
const AssistantComposer = {
  mounted() {
    this._composing = false;
    this._ignoreImeEnterUntil = 0;
    this._draftRevisions = new Map();
    this._submissions = new Map();
    this._submissionSeq = 0;
    this._draftKey = undefined;
    this._onInput = () => {
      this._draftText = this._textarea.value;
      this._draftRevisions.set(this._draftKey, this._revision(this._draftKey) + 1);
      this._writeDraft(this._draftKey, this._draftText);
      this._resize();
    };
    this._onCompositionStart = () => { this._composing = true; };
    this._onCompositionEnd = () => {
      this._composing = false;
      // Safari may report compositionend before its final Enter keydown.
      this._ignoreImeEnterUntil = Date.now() + 40;
      this._onInput();
    };
    this._onKeydown = event => {
      if (event.key !== 'Enter' || event.shiftKey) return;
      if (this._composing || event.isComposing || event.keyCode === 229 || Date.now() < this._ignoreImeEnterUntil) return;
      event.preventDefault();
      event.stopPropagation();
      if (this.el.dataset.busy !== 'true') this.el.requestSubmit();
    };
    this._onSubmit = event => {
      if (this.el.dataset.busy === 'true') {
        event.preventDefault();
        event.stopPropagation();
        return;
      }
      const order = ++this._submissionSeq;
      const token = `${Date.now().toString(36)}-${order}-${Math.random().toString(36).slice(2)}`;
      const field = this.el.querySelector('#assistant-submission');
      if (field) field.value = token;
      this._submissions.set(token, {
        key: this._draftKey,
        chatId: this._chatId,
        revision: this._revision(this._draftKey),
        text: this._textarea.value,
        order
      });
    };
    // Capture on the form before LiveView serializes it in its window listener.
    this.el.addEventListener('submit', this._onSubmit, { capture: true });
    this._sentHandle = this.handleEvent('assistant:sent', payload => this._acceptSent(payload));
    this._draftHandle = this.handleEvent('assistant:draft', ({ chat_id: chatId, text }) => {
      if (String(chatId) !== this._chatId || typeof text !== 'string') return;
      this._textarea.value = text;
      this._onInput();
      this._textarea.focus({ preventScroll: true });
    });
    this._focusHandle = this.handleEvent('assistant:focus', ({ chat_id: chatId, target }) => {
      if (String(chatId) !== this._chatId) return;
      if (target == null || target === 'composer') {
        this._textarea.focus({ preventScroll: true });
      }
    });
    this._syncContext();
  },

  updated() {
    this._syncContext();
  },

  destroyed() {
    this._unbindTextarea();
    this.el.removeEventListener('submit', this._onSubmit, { capture: true });
    for (const handle of [this._sentHandle, this._draftHandle, this._focusHandle]) {
      if (handle != null) this.removeHandleEvent(handle);
    }
  },

  _syncContext() {
    const textarea = this.el.querySelector('#assistant-message');
    if (!textarea) return;
    if (textarea !== this._textarea) {
      this._unbindTextarea();
      this._textarea = textarea;
      textarea.addEventListener('input', this._onInput);
      textarea.addEventListener('keydown', this._onKeydown);
      textarea.addEventListener('compositionstart', this._onCompositionStart);
      textarea.addEventListener('compositionend', this._onCompositionEnd);
    }

    const chatId = this.el.dataset.chatId || '';
    const key = storageKey(this.el.dataset.scope || 'local', chatId);
    const serverDraft = this.el.dataset.draft ?? textarea.value;
    if (key !== this._draftKey) {
      this._draftKey = key;
      this._chatId = chatId;
      this._lastServerDraft = serverDraft;
      this._serverDraftRevision = this._revision(key);
      const cached = this._readDraft(key);
      this._draftText = cached ?? serverDraft;
      if (cached != null && cached !== serverDraft) this._serverDraftRevision = -1;
      textarea.value = this._draftText;
      if (cached != null && cached !== serverDraft) {
        this.pushEvent('chat_input', { message: cached });
      }
    } else {
      // Apply server-driven prefills only while the local text is unchanged.
      // An older debounced update must not eat characters typed in the meantime.
      const serverChanged = serverDraft !== this._lastServerDraft;
      const pending = [...this._submissions.values()].some(submission => submission.key === key);
      // Successful submissions clear server state before their receipt arrives.
      // Let the matching receipt clear the exact submitted revision instead.
      const awaitingClearReceipt = serverDraft === '' && pending;
      if (serverChanged && !awaitingClearReceipt &&
          this._revision(key) === this._serverDraftRevision && this._draftText === this._lastServerDraft) {
        this._draftText = serverDraft;
        this._writeDraft(key, serverDraft);
      }
      if (serverChanged && !pending && serverDraft === this._draftText) {
        this._serverDraftRevision = this._revision(key);
      }
      this._lastServerDraft = serverDraft;
      textarea.value = this._draftText;
    }
    this._resize();
  },

  _acceptSent({ chat_id: chatId, text, submission_id: token }) {
    if (typeof text !== 'string') return;
    const id = String(chatId);
    const matches = submission => submission.chatId === id && submission.text.trim() === text.trim();
    // New servers echo the exact token. An older receipt can only correlate to
    // the earliest matching local submission, so uncertain drafts stay intact.
    const entry = token
      ? [token, this._submissions.get(token)]
      : [...this._submissions].find(([, submission]) => matches(submission));
    if (!entry?.[1] || !matches(entry[1])) return;
    const submission = entry[1];
    const unchanged = this._revision(submission.key) === submission.revision;
    for (const [knownToken, known] of this._submissions) {
      if (known.key === submission.key && known.order <= submission.order) this._submissions.delete(knownToken);
    }
    if (!unchanged) return;
    const cached = this._readDraft(submission.key);
    if (cached != null && cached.trim() === text.trim()) this._removeDraft(submission.key);
    if (id === this._chatId && submission.key === this._draftKey && this._draftText.trim() === text.trim()) {
      this._draftText = '';
      this._textarea.value = '';
      this._resize();
    }
  },

  _revision(key) {
    return this._draftRevisions.get(key) || 0;
  },

  _resize() {
    const textarea = this._textarea;
    if (!textarea) return;
    const style = window.getComputedStyle(textarea);
    const min = Number.parseFloat(style.minHeight) || 48;
    const cssMax = Number.parseFloat(style.maxHeight);
    const max = Number.isFinite(cssMax) && cssMax > 0 ? Math.min(cssMax, 240) : 240;
    textarea.style.height = 'auto';
    textarea.style.height = `${Math.max(min, Math.min(textarea.scrollHeight, max))}px`;
    textarea.style.overflowY = textarea.scrollHeight > max ? 'auto' : 'hidden';
  },

  _readDraft(key) {
    if (!key) return null;
    try { return window.sessionStorage.getItem(key); } catch { return null; }
  },

  _writeDraft(key, text) {
    if (!key) return;
    try { window.sessionStorage.setItem(key, text); } catch { /* The live draft still works when browser storage is unavailable. */ }
  },

  _removeDraft(key) {
    if (!key) return;
    try { window.sessionStorage.removeItem(key); } catch { /* No browser-local draft is available to clear. */ }
  },

  _unbindTextarea() {
    if (!this._textarea) return;
    this._textarea.removeEventListener('input', this._onInput);
    this._textarea.removeEventListener('keydown', this._onKeydown);
    this._textarea.removeEventListener('compositionstart', this._onCompositionStart);
    this._textarea.removeEventListener('compositionend', this._onCompositionEnd);
  }
};

export default AssistantComposer;
