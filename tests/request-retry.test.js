// The viewer's request retry rules (public/request-retry.js), driven with a fake request and a fake clock.
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  CONNECTION_WAIT_MS,
  HttpError,
  MAX_RETRIES,
  delayBeforeRetry,
  isTransientFailure,
  withRetry,
} = require("../public/request-retry");

const networkError = () => new TypeError("Failed to fetch");

/** A request that fails with each of `failures` in turn, then succeeds with "ok"; counts its calls. */
function scriptedRequest(failures) {
  const request = async () => {
    request.calls += 1;
    if (request.calls <= failures.length) {
      throw failures[request.calls - 1];
    }
    return "ok";
  };
  request.calls = 0;
  return request;
}

/** Retry options with a recorded fake clock and connection; nothing really waits. */
function fakeEnvironment({ online = true, connectionReturns = true } = {}) {
  const env = {
    sleeps: [],
    statusLines: [],
    connectionWaits: [],
    options: {
      onRetry: (text) => env.statusLines.push(text),
      isOnline: () => online,
      waitForConnection: async (ms) => {
        env.connectionWaits.push(ms);
        return connectionReturns;
      },
      sleep: async (ms) => {
        env.sleeps.push(ms);
      },
    },
  };
  return env;
}

test("isTransientFailure treats a network error as transient", () => {
  assert.equal(isTransientFailure(networkError()), true);
});

for (const status of [502, 503, 504]) {
  test(`isTransientFailure treats HTTP ${status} as transient`, () => {
    assert.equal(isTransientFailure(new HttpError(status, "busy")), true);
  });
}

for (const status of [400, 401, 413, 500]) {
  test(`isTransientFailure treats HTTP ${status} as permanent`, () => {
    assert.equal(isTransientFailure(new HttpError(status, "no")), false);
  });
}

test("isTransientFailure treats an unreadable reply (SyntaxError) as permanent", () => {
  assert.equal(isTransientFailure(new SyntaxError("Unexpected token <")), false);
});

test("delayBeforeRetry doubles from one second for the first three retries", () => {
  assert.deepEqual([1, 2, 3].map(delayBeforeRetry), [1000, 2000, 4000]);
});

test("delayBeforeRetry is capped at eight seconds", () => {
  assert.equal(delayBeforeRetry(10), 8000);
});

test("withRetry when the first attempt succeeds returns at once without waiting", async () => {
  const env = fakeEnvironment();
  const result = await withRetry(scriptedRequest([]), env.options);
  assert.equal(result, "ok");
  assert.deepEqual(env.sleeps, []);
});

test("withRetry after a network error then success returns the result", async () => {
  const env = fakeEnvironment();
  assert.equal(await withRetry(scriptedRequest([networkError()]), env.options), "ok");
});

test("withRetry after a 503 then success returns the result", async () => {
  const env = fakeEnvironment();
  assert.equal(await withRetry(scriptedRequest([new HttpError(503, "busy")]), env.options), "ok");
});

test("withRetry waits 1s, 2s, 4s between attempts", async () => {
  const env = fakeEnvironment();
  await withRetry(scriptedRequest([networkError(), networkError(), networkError()]), env.options);
  assert.deepEqual(env.sleeps, [1000, 2000, 4000]);
});

test("withRetry reports each retry as attempt n of the maximum", async () => {
  const env = fakeEnvironment();
  await withRetry(scriptedRequest([networkError(), networkError()]), env.options);
  assert.deepEqual(env.statusLines, [`Reconnecting (1/${MAX_RETRIES})…`, `Reconnecting (2/${MAX_RETRIES})…`]);
});

test("withRetry when every attempt fails tries once plus the maximum retries", async () => {
  const env = fakeEnvironment();
  const request = scriptedRequest(Array.from({ length: 10 }, networkError));
  await assert.rejects(withRetry(request, env.options));
  assert.equal(request.calls, 1 + MAX_RETRIES);
});

test("withRetry when every attempt fails throws the last error", async () => {
  const env = fakeEnvironment();
  const last = new HttpError(504, "last");
  const request = scriptedRequest([networkError(), networkError(), networkError(), last]);
  await assert.rejects(withRetry(request, env.options), (error) => error === last);
});

test("withRetry does not retry a 400", async () => {
  const env = fakeEnvironment();
  const request = scriptedRequest([new HttpError(400, "bad")]);
  await assert.rejects(withRetry(request, env.options), /bad/);
  assert.equal(request.calls, 1);
});

test("withRetry does not retry a 500", async () => {
  const env = fakeEnvironment();
  const request = scriptedRequest([new HttpError(500, "Failed to analyze")]);
  await assert.rejects(withRetry(request, env.options));
  assert.equal(request.calls, 1);
});

test("withRetry when offline waits for the connection before retrying", async () => {
  const env = fakeEnvironment({ online: false });
  await withRetry(scriptedRequest([networkError()]), env.options);
  assert.deepEqual(env.connectionWaits, [CONNECTION_WAIT_MS]);
});

test("withRetry when offline says it is waiting for the connection", async () => {
  const env = fakeEnvironment({ online: false });
  await withRetry(scriptedRequest([networkError()]), env.options);
  assert.equal(env.statusLines[0], "Waiting for connection…");
});

test("withRetry when online does not wait for the connection", async () => {
  const env = fakeEnvironment();
  await withRetry(scriptedRequest([networkError()]), env.options);
  assert.deepEqual(env.connectionWaits, []);
});

test("withRetry when the connection never returns throws the original error without retrying", async () => {
  const env = fakeEnvironment({ online: false, connectionReturns: false });
  const original = networkError();
  const request = scriptedRequest([original]);
  await assert.rejects(withRetry(request, env.options), (error) => error === original);
  assert.equal(request.calls, 1);
});
