// Small bounded windows with quiet boundaries and context on both sides.
(() => {
  const RATE = 16000;
  function plan(audio, seconds = 30, overlapSeconds = 0.4) {
    const limit = Math.floor(seconds * RATE), overlap = Math.floor(overlapSeconds * RATE);
    if (audio.length <= limit) return [{ start: 0, end: audio.length, coreStart: 0, coreEnd: audio.length }];
    const windows = [];
    for (let coreStart = 0; coreStart < audio.length;) {
      let coreEnd = Math.min(audio.length, coreStart + limit - 2 * overlap);
      if (coreEnd < audio.length) {
        const first = Math.max(coreStart + RATE * 4, coreEnd - RATE * 5);
        // Prefer at least 200 ms of silence near the end, not a single
        // low-energy sample in the middle of a spoken word.
        const step = 320; let run = 0, best = 0, boundary = coreEnd;
        for (let offset = first; offset + step <= coreEnd; offset += step) {
          let energy = 0;
          for (let i = offset; i < offset + step; i++) energy += audio[i] * audio[i];
          run = energy / step < 0.0001 ? run + step : 0;
          if (run >= RATE * 0.2 && run >= best) { best = run; boundary = offset + step - Math.floor(run / 2); }
        }
        if (best) coreEnd = boundary;
      }
      windows.push({ start: Math.max(0, coreStart - overlap), end: Math.min(audio.length, coreEnd + overlap), coreStart, coreEnd });
      coreStart = coreEnd;
    }
    return windows;
  }
  const key = word => word.toLocaleLowerCase().replace(/[^\p{L}\p{N}]/gu, '');
  function append(output, candidates, window) {
    const first = window.coreStart / RATE, last = window.coreEnd / RATE;
    for (const candidate of candidates) {
      if (!candidate.text?.trim() || candidate.end <= first || candidate.start >= last) continue;
      let text = candidate.text.trim();
      const previous = output.at(-1);
      if (previous && candidate.start < previous.end + 0.05) {
        const before = previous.text.trim().split(/\s+/), after = text.split(/\s+/);
        // A matching full sentence may be intentional repetition. Only a
        // few words can belong to the small shared audio context; never
        // deduplicate more than that overlap could plausibly contain.
        const contextWords = Math.ceil(Math.max(0, previous.end - candidate.start) * 8);
        for (let n = Math.min(contextWords, before.length, after.length); n >= 3; n--) {
          if (before.slice(-n).map(key).join(' ') === after.slice(0, n).map(key).join(' ')) {
            text = after.slice(n).join(' '); break;
          }
        }
      }
      if (text) output.push({ ...candidate, text, start: Math.max(first, candidate.start), end: Math.min(last, candidate.end) });
    }
  }
  globalThis.CW_CHUNKS = { plan, append };
  if (typeof module !== 'undefined') module.exports = globalThis.CW_CHUNKS;
})();
