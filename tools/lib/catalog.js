"use strict";
// Build the translation catalog from the installed DaylightUI sources.
// Mirrors the original author's tests/locale_keys intent: every string that is
// looked up through L[...] or shown from a labelled/choice field is UI text.

const fs = require("node:fs");
const path = require("node:path");
const { tokenize } = require("./lua");

const FIELDS = new Set([
  "label", "desc", "pitch", "title", "short", "blurb", "hint", "help",
  "note", "text", "sub", "empty", "more", "confirm", "tooltip", "tips", "mouseover", "explanation",
]);
const WALKED = new Set(["values", "choices", "labels"]);

function listFiles(root) {
  const out = [];
  const skip = new Set(["Libs", "Locales", "tests", "tools", "docs", "screenshots", "DaylightUI_Dev"]);
  (function walk(dir) {
    for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
      if (item.name.startsWith(".")) continue;
      const full = path.join(dir, item.name);
      if (item.isDirectory()) {
        if (!skip.has(item.name)) walk(full);
      } else if (item.name.endsWith(".lua") && item.name !== "PatchNotes.lua") {
        out.push(full);
      }
    }
  })(root);
  return out.sort();
}

function extract(root) {
  const data = new Map();
  for (const file of listFiles(root)) {
    const source = fs.readFileSync(file, "utf8").replace(/^\uFEFF/, "");
    const tokens = tokenize(source);
    const stack = [];
    const rel = path.relative(root, file).replace(/\\/g, "/");
    for (let i = 0; i < tokens.length; i++) {
      const t = tokens[i];
      const before = tokens.slice(Math.max(0, i - 3), i).map((x) => x.value);
      if (t.kind === "tok" && t.value === "{") {
        stack.push(before.length > 1 && before[before.length - 1] === "=" ? before[before.length - 2] : "");
      }
      if (t.kind === "tok" && t.value === "}" && stack.length) stack.pop();
      if (t.kind !== "str") continue;
      const value = t.value;
      let reason = null;
      if (before.length > 1 && before[before.length - 2] === "L" && before[before.length - 1] === "[") {
        reason = "locale";
      } else if (before.length > 1 && before[before.length - 1] === "=" && FIELDS.has(before[before.length - 2])) {
        reason = "display";
      } else if (stack.some((s) => WALKED.has(s)) && !(i + 1 < tokens.length && ["]", "="].includes(tokens[i + 1].value))) {
        reason = "choice";
      } else if (before.length > 1 && before[before.length - 1] === "(" && ["T", "Text"].includes(before[before.length - 2])) {
        reason = "display";
      }
      if (!reason) continue;
      if (!/[A-Za-z]/.test(value)) continue;
      if (value.includes("\\")) continue;
      if (value.startsWith("Interface/") || value.startsWith("Fonts/")) continue;
      let item = data.get(value);
      if (!item) { item = { reasons: [], refs: [] }; data.set(value, item); }
      if (!item.reasons.includes(reason)) item.reasons.push(reason);
      const ref = rel + ":" + t.line;
      if (!item.refs.includes(ref)) item.refs.push(ref);
    }
  }
  return new Map([...data.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
}

module.exports = { extract, listFiles, FIELDS };
