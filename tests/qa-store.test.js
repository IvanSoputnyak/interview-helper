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

test.after(() => {
  try {
    fs.unlinkSync(storePath);
  } catch {
    // ignore
  }
});

test("append and list minimal rows", () => {
  qaStore.append({ id: "1", at: "t1", q: "Two sum?", a: "hash map" });
  qaStore.append({ id: "2", at: "t2", q: "BFS?", a: "queue" });

  const items = qaStore.list();
  assert.equal(items.length, 2);
  assert.equal(items[0].q, "BFS?");
  assert.equal(items[1].a, "hash map");
});

test("upsert replaces answer for same id", () => {
  qaStore.upsert({ id: "1", at: "t3", q: "Two sum?", a: "two pointers" });
  const row = qaStore.list().find((item) => item.id === "1");
  assert.equal(row.a, "two pointers");
});
