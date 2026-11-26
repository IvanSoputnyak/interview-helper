const fs = require("fs");
const path = require("path");

const MAX_ITEMS = Number(process.env.HISTORY_MAX_ITEMS) || 25;
const STORE_PATH =
  process.env.QA_STORE_PATH || path.join(__dirname, "..", "data", "qa.jsonl");

function parseLine(line) {
  try {
    return JSON.parse(line);
  } catch {
    return null;
  }
}

/** Corrupt lines are skipped (not fatal) so one bad row never wipes the whole history on the next write. */
function readAll() {
  if (!fs.existsSync(STORE_PATH)) {
    return [];
  }
  return fs
    .readFileSync(STORE_PATH, "utf8")
    .split("\n")
    .filter(Boolean)
    .map(parseLine)
    .filter(Boolean);
}

function writeAll(items) {
  fs.mkdirSync(path.dirname(STORE_PATH), { recursive: true });
  const body = items.map((row) => JSON.stringify(row)).join("\n");
  const tmpPath = `${STORE_PATH}.tmp`;
  fs.writeFileSync(tmpPath, body ? `${body}\n` : "");
  fs.renameSync(tmpPath, STORE_PATH);
}

function list() {
  return readAll().slice(0, MAX_ITEMS);
}

/** Writes the newest MAX_ITEMS rows and returns them, so callers need no second read. */
function save(items) {
  const kept = items.slice(0, MAX_ITEMS);
  writeAll(kept);
  return kept;
}

/**
 * Adds a row at the top; returns the saved list.
 * @param {{ id: string, at: string, q: string, a: string }} entry
 */
function append(entry) {
  return save([entry, ...readAll()]);
}

/** Replaces the row with the same id in place (or adds it at the top); returns the saved list. */
function upsert(entry) {
  const items = readAll();
  const index = items.findIndex((row) => row.id === entry.id);
  if (index >= 0) {
    items[index] = { ...items[index], ...entry };
  } else {
    items.unshift(entry);
  }
  return save(items);
}

module.exports = {
  MAX_ITEMS,
  STORE_PATH,
  append,
  list,
  readAll,
  upsert,
};
