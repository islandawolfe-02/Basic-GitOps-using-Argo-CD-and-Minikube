// Supplied browser client (read-only teaching equipment). It runs in the BROWSER.
// client.json: deadlineMs = complete-body waiting limit per HTTP attempt (40-650);
//              retries   = additional attempts after an UNAVAILABLE result (0-2);
//              deadlineMs * (retries + 1) must not exceed 650.
// A received HTTP error (e.g. 404) ends the action; it is not retried.
const $ = (id) => document.getElementById(id);
let client = null;

function validate(c) {
  const ok = Number.isInteger(c.deadlineMs) && c.deadlineMs >= 40 && c.deadlineMs <= 650 &&
    Number.isInteger(c.retries) && c.retries >= 0 && c.retries <= 2 && c.deadlineMs * (c.retries + 1) <= 650;
  if (!ok) throw new Error("client.json outside the supplied ranges or total budget");
  return c;
}

async function loadClient() {
  const response = await fetch("client.json", { cache: "no-store" });
  client = validate(await response.json());
  $("config").textContent = JSON.stringify(client);
}

async function attempt(path, actionId) {
  const requestId = crypto.randomUUID();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), client.deadlineMs);
  const started = performance.now();
  try {
    const response = await fetch(path, {
      headers: { "X-Request-Id": requestId, "X-Action-Id": actionId },
      signal: controller.signal, cache: "no-store",
    });
    const text = await response.text();            // the deadline covers the COMPLETE body
    return { request_id: requestId, received: true, status: response.status,
             echoed_request_id: response.headers.get("X-Request-Id"),
             release: response.headers.get("X-Lab-Release"), environment: response.headers.get("X-Lab-Environment"),
             elapsed_ms: Math.round(performance.now() - started), body: text };
  } catch (error) {
    return { request_id: requestId, received: false, status: null, error: error.name,
             elapsed_ms: Math.round(performance.now() - started) };
  } finally {
    clearTimeout(timer);
  }
}

async function loadBoard() {
  if (!client) await loadClient();
  const fixture = $("board").value;
  const actionId = crypto.randomUUID();
  const started = performance.now();
  const attempts = [];
  let final = null;
  for (let i = 0; i <= client.retries; i++) {
    const result = await attempt("/api/boards/" + encodeURIComponent(fixture), actionId);
    attempts.push(result);
    if (result.received) { final = result; break; }   // success or received HTTP error: stop
  }
  const observation = {
    action_id: actionId, fixture, client,
    outcome: final ? (final.status < 400 ? "received" : "http-error") : "unavailable",
    received_status: final ? final.status : null,
    echoed_request_id: final ? final.echoed_request_id : null,
    release: final ? final.release : null, environment: final ? final.environment : null,
    action_elapsed_ms: Math.round(performance.now() - started),
    attempts: attempts.map(({ body, ...rest }) => rest),
  };
  window.lastObservation = observation;                // read by the supplied helper
  $("observation").textContent = JSON.stringify(observation, null, 2);
  $("body").textContent = final ? final.body : "(no complete body received for this action)";
}

$("load").addEventListener("click", () => loadBoard().catch((e) => { $("observation").textContent = "error: " + e.message; }));
loadClient().catch((e) => { $("config").textContent = "unavailable: " + e.message; });
