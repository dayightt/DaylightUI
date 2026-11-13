"use strict";
// Lua string.format specifiers, in order. A translation must keep them equal:
// a dropped or added %s is the classic way to break an addon with a translation.
const FORMAT = /%(?:%|[-+0#]*\d*(?:\.\d+)?[cdiouxXeEfgGqs])/g;

function specifiers(text) {
  return String(text).match(FORMAT) || [];
}

function formatOk(key, value) {
  const a = specifiers(key);
  const b = specifiers(value);
  if (a.length !== b.length) return false;
  return a.every((x, i) => x === b[i]);
}

module.exports = { specifiers, formatOk };
