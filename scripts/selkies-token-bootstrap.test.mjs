import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { once } from "node:events";
import { test } from "node:test";

const bootstrap = new URL("./selkies-token-bootstrap.mjs", import.meta.url);
const master = "master-0123456789abcdefghijklmnopqrstuvwxyz";
const controller = "controller-0123456789abcdefghijklmnopqrstuv";
const viewer = "viewer-0123456789abcdefghijklmnopqrstuvwxyz";

test("registers distinct controller and viewer tokens without logging secrets", async (t) => {
  let request;
  const server = createServer(async (incoming, response) => {
    const chunks = [];
    for await (const chunk of incoming) chunks.push(chunk);
    request = {
      method: incoming.method,
      url: incoming.url,
      authorization: incoming.headers.authorization,
      body: JSON.parse(Buffer.concat(chunks).toString("utf8")),
    };
    response.writeHead(200, { "content-type": "application/json" });
    response.end("{}");
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => server.close());

  const address = server.address();
  assert.notEqual(address, null);
  assert.equal(typeof address, "object");

  const child = spawn(process.execPath, [bootstrap.pathname], {
    env: {
      ...process.env,
      SELKIES_PORT: String(address.port),
      SELKIES_MASTER_TOKEN: master,
      EGO_VIEWER_CONTROLLER_TOKEN: controller,
      EGO_VIEWER_VIEWER_TOKEN: viewer,
      EGO_SELKIES_BOOTSTRAP_TIMEOUT_MS: "2000",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  const stdout = [];
  const stderr = [];
  child.stdout.on("data", (chunk) => stdout.push(chunk));
  child.stderr.on("data", (chunk) => stderr.push(chunk));
  const [exitCode] = await once(child, "exit");
  const output = Buffer.concat(stdout).toString("utf8");
  const errors = Buffer.concat(stderr).toString("utf8");

  assert.equal(exitCode, 0, errors);
  assert.deepEqual(JSON.parse(output), { ok: true, tokenCount: 2 });
  assert.equal(output.includes(master), false);
  assert.equal(output.includes(controller), false);
  assert.equal(output.includes(viewer), false);
  assert.deepEqual(request, {
    method: "POST",
    url: "/api/tokens",
    authorization: `Bearer ${master}`,
    body: {
      [controller]: { role: "controller", slot: null, mk_control: true },
      [viewer]: { role: "viewer", slot: null, mk_control: false },
    },
  });
});
