"use strict";
// Minimal Lua 5.1 source reader: string-aware tokenizer and a reader for the
// generated Locale.lua table. It never executes Lua and never needs the game.

// Decode one Lua short-string token (including its quotes).
function decodeShortString(token) {
  const body = token.slice(1, -1);
  const chars = Array.from(body);
  const bytes = [];
  const push = (s) => { for (const b of Buffer.from(s, "utf8")) bytes.push(b); };
  for (let i = 0; i < chars.length; i++) {
    const c = chars[i];
    if (c !== "\\") { push(c); continue; }
    i++;
    const e = chars[i];
    if (e === undefined) break;
    if (e >= "0" && e <= "9") {
      let digits = e;
      while (digits.length < 3 && chars[i + 1] >= "0" && chars[i + 1] <= "9") {
        digits += chars[++i];
      }
      const code = parseInt(digits, 10);
      if (code > 0 && code < 256) bytes.push(code);
      continue;
    }
    if (e === "\n") { bytes.push(10); continue; }
    const map = { a: 7, b: 8, f: 12, n: 10, r: 13, t: 9, v: 11 };
    if (Object.prototype.hasOwnProperty.call(map, e)) bytes.push(map[e]);
    else push(e);
  }
  return Buffer.from(bytes).toString("utf8");
}

function countNewlines(s) {
  let n = 0;
  for (let i = 0; i < s.length; i++) if (s[i] === "\n") n++;
  return n;
}

// Tokenize Lua source. Returns [{kind:"str"|"tok", value, line}]. Comments and
// long-bracket strings are handled; long strings become ordinary string tokens.
function tokenize(source) {
  const tokens = [];
  let i = 0, line = 1;
  const n = source.length;
  while (i < n) {
    const c = source[i];
    if (c === "\n") { line++; i++; continue; }
    if (c === " " || c === "\t" || c === "\r" || c === "\f" || c === "\v") { i++; continue; }
    if (c === "-" && source[i + 1] === "-") {
      const long = /^--\[(=*)\[/.exec(source.slice(i, i + 64));
      if (long) {
        const close = "]" + long[1] + "]";
        const end = source.indexOf(close, i + long[0].length);
        const stop = end < 0 ? n : end + close.length;
        line += countNewlines(source.slice(i, stop));
        i = stop;
      } else {
        const end = source.indexOf("\n", i);
        i = end < 0 ? n : end;
      }
      continue;
    }
    if (c === "[") {
      const long = /^\[(=*)\[/.exec(source.slice(i, i + 64));
      if (long) {
        const close = "]" + long[1] + "]";
        const bodyStart = i + long[0].length;
        const end = source.indexOf(close, bodyStart);
        const body = source.slice(bodyStart, end < 0 ? n : end);
        tokens.push({ kind: "str", value: body[0] === "\n" ? body.slice(1) : body, line });
        line += countNewlines(body);
        i = end < 0 ? n : end + close.length;
        continue;
      }
    }
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < n) {
        if (source[j] === "\\") { j += 2; continue; }
        if (source[j] === c) break;
        j++;
      }
      const token = source.slice(i, Math.min(j + 1, n));
      tokens.push({ kind: "str", value: decodeShortString(token), line });
      line += countNewlines(token);
      i = j + 1;
      continue;
    }
    if (/[A-Za-z_]/.test(c)) {
      let j = i + 1;
      while (j < n && /[A-Za-z0-9_]/.test(source[j])) j++;
      tokens.push({ kind: "tok", value: source.slice(i, j), line });
      i = j;
      continue;
    }
    if (c === "." && source[i + 1] === ".") {
      tokens.push({ kind: "tok", value: "..", line });
      i += 2;
      continue;
    }
    tokens.push({ kind: "tok", value: c, line });
    i++;
  }
  // Fold "a" .. "b" the way Lua does before the key is looked up, so a
  // multi-line L[...] key is one catalog entry, not fragments.
  const folded = [];
  for (let i = 0; i < tokens.length; i++) {
    let t = tokens[i];
    if (t.kind === "str") {
      let value = t.value;
      while (
        i + 2 < tokens.length &&
        tokens[i + 1].kind === "tok" && tokens[i + 1].value === ".." &&
        tokens[i + 2].kind === "str"
      ) {
        value += tokens[i + 2].value;
        i += 2;
      }
      t = { kind: "str", value, line: t.line };
    }
    folded.push(t);
  }
  return folded;
}

// Read P.translations = { ["English"] = "中文", ... } from generated Locale.lua.
// The file is written one entry per line with quoted keys and values.
function readTranslations(source) {
  const out = new Map();
  const start = source.indexOf("P.translations");
  const lineRe = /^\s*\[("(?:\\.|[^"\\])*")\]\s*=\s*("(?:\\.|[^"\\])*")\s*,?\s*$/;
  const lines = source.slice(start).split(/\r?\n/);
  for (const line of lines) {
    if (line.trim() === "}") break;
    const m = lineRe.exec(line);
    if (!m) continue;
    out.set(JSON.parse(m[1]), JSON.parse(m[2]));
  }
  return out;
}

// Lua-compatible quoted string (JSON rules minus \u escapes, which Lua lacks).
function luaQuote(s) {
  let out = '"';
  for (const ch of String(s)) {
    const code = ch.codePointAt(0);
    if (ch === "\\") out += "\\\\";
    else if (ch === '"') out += '\\"';
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else if (ch === "\b") out += "\\b";
    else if (ch === "\f") out += "\\f";
    else if (code < 0x20) out += "\\" + String(code).padStart(3, "0");
    else out += ch;
  }
  return out + '"';
}

module.exports = { tokenize, decodeShortString, readTranslations, luaQuote };
