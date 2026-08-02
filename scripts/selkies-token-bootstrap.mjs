#!/usr/bin/env node

const MIN_SECRET_LENGTH = 32;
const FORBIDDEN_SECRETS = new Set([
  "mypasswd",
  "changeme",
  "password",
  "controller-token",
  "viewer-token",
]);

function requireSecret(name) {
  const value = process.env[name] ?? "";
  if (value.length < MIN_SECRET_LENGTH || FORBIDDEN_SECRETS.has(value.toLowerCase())) {
    throw new Error(`${name} must be a non-default secret of at least ${MIN_SECRET_LENGTH} characters`);
  }
  return value;
}

function optionalSecret(name) {
  const value = process.env[name] ?? "";
  if (!value) return null;
  if (value.length < MIN_SECRET_LENGTH || FORBIDDEN_SECRETS.has(value.toLowerCase())) {
    throw new Error(`${name} must be a non-default secret of at least ${MIN_SECRET_LENGTH} characters`);
  }
  return value;
}

function parsePort(raw) {
  const port = Number(raw);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`invalid SELKIES_PORT: ${raw}`);
  }
  return port;
}

const masterToken = requireSecret("SELKIES_MASTER_TOKEN");
const controllerToken = requireSecret("EGO_VIEWER_CONTROLLER_TOKEN");
const viewerToken = optionalSecret("EGO_VIEWER_VIEWER_TOKEN");

const uniqueSecrets = new Set([masterToken, controllerToken, viewerToken].filter(Boolean));
const expectedSecretCount = viewerToken ? 3 : 2;
if (uniqueSecrets.size !== expectedSecretCount) {
  throw new Error("Selkies master, controller, and viewer tokens must be distinct");
}

const tokens = {
  [controllerToken]: { role: "controller", slot: null, mk_control: true },
};
if (viewerToken) {
  tokens[viewerToken] = { role: "viewer", slot: null, mk_control: false };
}

if (process.argv.includes("--check")) {
  process.stdout.write(`${JSON.stringify({ ok: true, tokenCount: Object.keys(tokens).length })}\n`);
  process.exit(0);
}

const port = parsePort(process.env.SELKIES_PORT ?? process.env.PORT ?? "8080");
const timeoutMs = Number(process.env.EGO_SELKIES_BOOTSTRAP_TIMEOUT_MS ?? "60000");
if (!Number.isInteger(timeoutMs) || timeoutMs < 1000 || timeoutMs > 120000) {
  throw new Error("EGO_SELKIES_BOOTSTRAP_TIMEOUT_MS must be between 1000 and 120000");
}

const endpoint = `http://127.0.0.1:${port}/api/tokens`;
const deadline = Date.now() + timeoutMs;
let lastError = null;

while (Date.now() < deadline) {
  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        authorization: `Bearer ${masterToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(tokens),
    });
    if (response.ok) {
      process.stdout.write(`${JSON.stringify({ ok: true, tokenCount: Object.keys(tokens).length })}\n`);
      process.exit(0);
    }
    lastError = new Error(`Selkies token API returned HTTP ${response.status}`);
  } catch (error) {
    lastError = error;
  }
  await new Promise((resolve) => setTimeout(resolve, 250));
}

throw new Error(`Selkies token bootstrap timed out: ${lastError?.message ?? "unknown error"}`);
