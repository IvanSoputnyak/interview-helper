// Retry rules for the viewer's button requests (Capture & analyze, Improve, Explain), matching the Mac app's
// RequestRetry.swift: up to 3 retries with 1s/2s/4s backoff; when offline, first wait up to 30s for the connection.
// Loaded as a plain <script> in the browser (global `RequestRetry`) and with require() in the Node tests.
(function exportRequestRetry(root) {
  const MAX_RETRIES = 3;
  const BASE_DELAY_MS = 1000;
  const MAX_DELAY_MS = 8000;
  const CONNECTION_WAIT_MS = 30000;
  /**
   * Gateway / unavailable / timeout from the server. A 500 is not retried: it means OpenAI already failed
   * after the server's own retries, and repeating it would only repeat the cost.
   */
  const TRANSIENT_STATUSES = new Set([502, 503, 504]);
  const WAITING_FOR_CONNECTION_TEXT = "Waiting for connection…";

  /** A non-2xx reply from the server, carrying its HTTP status and JSON `error` message. */
  class HttpError extends Error {
    constructor(status, message) {
      super(message);
      this.status = status;
    }
  }

  /** `fetch` rejects with a TypeError when the request never got a reply (offline, server restarting). */
  function isTransientFailure(error) {
    if (error instanceof HttpError) {
      return TRANSIENT_STATUSES.has(error.status);
    }
    return error instanceof TypeError;
  }

  /** Exponential backoff for the 1-based `retry`: 1s, 2s, 4s, … capped at 8s. */
  function delayBeforeRetry(retry) {
    return Math.min(BASE_DELAY_MS * 2 ** (retry - 1), MAX_DELAY_MS);
  }

  function retryingText(retry) {
    return `Reconnecting (${retry}/${MAX_RETRIES})…`;
  }

  const realSleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  /**
   * Runs `operation`, retrying transient failures. `isOnline()` reports the live connection;
   * `waitForConnection(ms)` resolves true once it is back, or false after `ms`. `onRetry(text)` gets a
   * short status line for the button. Permanent errors, and the last error after the final retry, are thrown.
   */
  async function withRetry(operation, { onRetry, isOnline, waitForConnection, sleep = realSleep }) {
    for (let retry = 1; ; retry += 1) {
      try {
        return await operation();
      } catch (error) {
        if (retry > MAX_RETRIES || !isTransientFailure(error)) {
          throw error;
        }
        if (!isOnline()) {
          onRetry(WAITING_FOR_CONNECTION_TEXT);
          if (!(await waitForConnection(CONNECTION_WAIT_MS))) {
            throw error;
          }
        }
        onRetry(retryingText(retry));
        await sleep(delayBeforeRetry(retry));
      }
    }
  }

  const api = { CONNECTION_WAIT_MS, HttpError, MAX_RETRIES, delayBeforeRetry, isTransientFailure, withRetry };
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else {
    root.RequestRetry = api;
  }
})(typeof window === "undefined" ? globalThis : window);
