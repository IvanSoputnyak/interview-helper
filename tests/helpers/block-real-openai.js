// Preloaded into every Node test file (see "test:node" in package.json): tests use the fake OpenAI server in
// server-openai.test.js, never the real API, so running the tests can never spend the OPENAI_API_KEY in .env.
const REAL_OPENAI_HOST = "api.openai.com";
const BLOCKED_MESSAGE = "Real OpenAI API calls are blocked in tests; point OPENAI_BASE_URL at a fake server.";

// dotenv never overrides a variable that is already set, so this keeps the real key in .env out of the server.
// A test that needs a key sets its own fake one together with OPENAI_BASE_URL.
process.env.OPENAI_API_KEY = "";
delete process.env.OPENAI_BASE_URL;

// Second line of defence for a test that sets a key but forgets OPENAI_BASE_URL. The OpenAI SDK takes
// globalThis.fetch when a client is created, and this runs before any test file loads the server.
const realFetch = globalThis.fetch;
globalThis.fetch = (input, init) => {
  const url = new URL(input instanceof Request ? input.url : String(input));
  if (url.hostname === REAL_OPENAI_HOST) {
    return Promise.reject(new Error(BLOCKED_MESSAGE));
  }
  return realFetch(input, init);
};
