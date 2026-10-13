const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");

const storePath = path.join(
  os.tmpdir(),
  `ih-qa-unit-${process.pid}-${Date.now()}.jsonl`,
);
process.env.QA_STORE_PATH = storePath;

const qaStore = require("../lib/qa-store");

function reset(lines = []) {
  fs.writeFileSync(storePath, lines.length ? `${lines.join("\n")}\n` : "");
}

test.after(() => {
  try {
    fs.unlinkSync(storePath);
  } catch {
    // ignore
  }
});

test("append puts newest row first", () => {
  reset();
  qaStore.append({ id: "1", at: "t1", q: "Two sum?", a: "hash map" });
  qaStore.append({ id: "2", at: "t2", q: "BFS?", a: "queue" });

  const items = qaStore.list();
  assert.equal(items.length, 2);
  assert.equal(items[0].q, "BFS?");
  assert.equal(items[1].a, "hash map");
});

test("upsert replaces answer for an existing id in place", () => {
  reset();
  qaStore.append({ id: "1", at: "t1", q: "Two sum?", a: "hash map" });
  qaStore.append({ id: "2", at: "t2", q: "BFS?", a: "queue" });
  qaStore.upsert({ id: "1", at: "t3", q: "Two sum?", a: "two pointers" });

  const items = qaStore.list();
  assert.equal(items.length, 2);
  assert.equal(items[1].id, "1");
  assert.equal(items[1].a, "two pointers");
});

test("upsert inserts at the top when id is unknown", () => {
  reset();
  qaStore.append({ id: "1", at: "t1", q: "Q1", a: "A1" });
  qaStore.upsert({ id: "new", at: "t2", q: "Q2", a: "A2" });
  assert.equal(qaStore.list()[0].id, "new");
});

test("a corrupt line is skipped and does not wipe history on next write", () => {
  reset([
    JSON.stringify({ id: "1", at: "t1", q: "Q1", a: "A1" }),
    "{not valid json",
    JSON.stringify({ id: "2", at: "t2", q: "Q2", a: "A2" }),
  ]);
  assert.equal(qaStore.list().length, 2);

  qaStore.append({ id: "3", at: "t3", q: "Q3", a: "A3" });
  assert.deepEqual(
    qaStore.list().map((row) => row.id),
    ["3", "1", "2"],
  );
});

test("store is truncated to MAX_ITEMS", () => {
  reset();
  for (let i = 0; i < qaStore.MAX_ITEMS + 3; i += 1) {
    qaStore.append({ id: String(i), at: "t", q: "q", a: "a" });
  }
  assert.equal(qaStore.readAll().length, qaStore.MAX_ITEMS);
  assert.equal(qaStore.list()[0].id, String(qaStore.MAX_ITEMS + 2));
});

test("missing store file lists as empty", () => {
  fs.rmSync(storePath, { force: true });
  assert.deepEqual(qaStore.list(), []);
});
