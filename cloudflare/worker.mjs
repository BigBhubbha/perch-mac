// Perch agent board. Grok Bot agents report what they are doing, the Perch app reads it.
//
//   POST   /v1/events          Bearer WRITE_KEY   {"agent":"Architect III","status":"started","task":"Building Perch"}
//   GET    /v1/agents          Bearer READ_KEY    -> {"agents":[...], "now": 1730000000000}
//   DELETE /v1/agents/<id>     Bearer WRITE_KEY   remove one agent from the board
//   POST   /v1/requests        Bearer READ_KEY    {"kind":"text","title":"...","body":"...","source":"Notes"}  something poured onto the Agents dot
//   GET    /v1/requests        Bearer READ_KEY    -> {"requests":[...]}  (bots read the queue, the app shows status)
//   POST   /v1/requests/<id>   Bearer WRITE_KEY   {"status":"claimed"|"done","by":"Architect III","note":"..."}
//   DELETE /v1/requests/<id>   Bearer READ_KEY    take a request back
//   GET    /health                                -> {"ok":true}
//
// status is one of: started, working (a heartbeat or a new task line), finished, failed.
// Keep `task` short and free of private details: it is shown at the top of the screen.

import { DurableObject } from "cloudflare:workers";

const STATUSES = new Set(["started", "working", "finished", "failed"]);
const MAX_AGENTS = 40;
const FINISHED_TTL_MS = 12 * 60 * 60 * 1000; // finished or failed cards fade off after 12 hours
const STALE_AFTER_MS = 3 * 60 * 60 * 1000; // a working agent with no news for 3 hours is shown as quiet
const MAX_REQUESTS = 50;
const DONE_REQUEST_TTL_MS = 3 * 24 * 60 * 60 * 1000; // done requests drop off after 3 days
const KINDS = new Set(["text", "link", "file", "song", "mail", "note"]);

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });

function bearer(request) {
  const h = request.headers.get("authorization") || "";
  return h.startsWith("Bearer ") ? h.slice(7).trim() : "";
}

// Constant-time compare so keys cannot be guessed one character at a time.
function same(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || !a || !b) return false;
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  for (let i = 0; i < Math.max(ea.length, eb.length); i++) diff |= (ea[i] || 0) ^ (eb[i] || 0);
  return diff === 0;
}

function slug(s) {
  return String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 48);
}

function clean(s, max) {
  if (s === undefined || s === null) return null;
  return String(s).replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, max) || null;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (path === "/health") return json({ ok: true });

    const key = bearer(request);
    const canWrite = same(key, env.WRITE_KEY);
    const canRead = canWrite || same(key, env.READ_KEY);
    const board = env.BOARD.get(env.BOARD.idFromName("shabd"));
    const queue = env.REQUESTS.get(env.REQUESTS.idFromName("shabd"));

    if (path === "/v1/agents" && request.method === "GET") {
      if (!canRead) return json({ error: "unauthorized" }, 401);
      return json(await board.list());
    }

    if (path === "/v1/events" && request.method === "POST") {
      if (!canWrite) return json({ error: "unauthorized" }, 401);
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: "send JSON" }, 400);
      }
      const name = clean(body.agent ?? body.name, 40);
      const status = String(body.status || "").toLowerCase();
      if (!name) return json({ error: "agent is required" }, 400);
      if (!STATUSES.has(status)) return json({ error: "status must be started, working, finished or failed" }, 400);
      const id = slug(body.id || name);
      if (!id) return json({ error: "agent needs letters or numbers" }, 400);
      const result = await board.report({ id, name, status, task: clean(body.task, 90), note: clean(body.note, 140) });
      return json(result, result.error ? 429 : 200);
    }

    if (path === "/v1/requests" && request.method === "GET") {
      if (!canRead) return json({ error: "unauthorized" }, 401);
      return json(await queue.listRequests());
    }

    if (path === "/v1/requests" && request.method === "POST") {
      if (!canRead) return json({ error: "unauthorized" }, 401);
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: "send JSON" }, 400);
      }
      const kind = String(body.kind || "text").toLowerCase();
      if (!KINDS.has(kind)) return json({ error: "unknown kind" }, 400);
      const title = clean(body.title, 120);
      // The body keeps its line breaks; only control characters other than newlines and tabs are removed.
      const text = body.body == null ? null : String(body.body).replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, " ").slice(0, 4000) || null;
      if (!title && !text) return json({ error: "title or body is required" }, 400);
      const result = await queue.addRequest({ kind, title, body: text, source: clean(body.source, 40) });
      return json(result, result.error ? 429 : 200);
    }

    const req = path.match(/^\/v1\/requests\/([a-z0-9]{6,32})$/);
    if (req && request.method === "POST") {
      if (!canWrite) return json({ error: "unauthorized" }, 401);
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: "send JSON" }, 400);
      }
      const status = String(body.status || "").toLowerCase();
      if (status !== "claimed" && status !== "done" && status !== "open") return json({ error: "status must be open, claimed or done" }, 400);
      return json(await queue.updateRequest(req[1], status, clean(body.by, 40), clean(body.note, 140)));
    }
    if (req && request.method === "DELETE") {
      if (!canRead) return json({ error: "unauthorized" }, 401);
      return json(await queue.removeRequest(req[1]));
    }

    const del = path.match(/^\/v1\/agents\/([a-z0-9-]{1,48})$/);
    if (del && request.method === "DELETE") {
      if (!canWrite) return json({ error: "unauthorized" }, 401);
      return json(await board.remove(del[1]));
    }

    return json({ error: "not found" }, 404);
  },
};

export class Board extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS agents (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      status TEXT NOT NULL,
      task TEXT,
      note TEXT,
      started_at INTEGER,
      updated_at INTEGER NOT NULL,
      finished_at INTEGER,
      run INTEGER NOT NULL DEFAULT 0
    )`);
  }

  prune(now) {
    this.sql.exec("DELETE FROM agents WHERE finished_at IS NOT NULL AND finished_at < ?", now - FINISHED_TTL_MS);
  }

  async list() {
    const now = Date.now();
    this.prune(now);
    const agents = this.sql
      .exec("SELECT * FROM agents ORDER BY (finished_at IS NULL) DESC, updated_at DESC LIMIT ?", MAX_AGENTS)
      .toArray()
      .map((r) => ({
        id: r.id,
        name: r.name,
        status: r.status === "working" ? "started" : r.status,
        quiet: r.finished_at === null && now - r.updated_at > STALE_AFTER_MS,
        task: r.task,
        note: r.note,
        run: r.run,
        startedAt: r.started_at,
        updatedAt: r.updated_at,
        finishedAt: r.finished_at,
      }));
    return { agents, now };
  }

  async report({ id, name, status, task, note }) {
    const now = Date.now();
    this.prune(now);
    const existing = this.sql.exec("SELECT * FROM agents WHERE id = ?", id).toArray()[0];
    if (!existing) {
      const count = this.sql.exec("SELECT COUNT(*) AS n FROM agents").one().n;
      if (count >= MAX_AGENTS) return { error: "board is full" };
    }
    const done = status === "finished" || status === "failed";
    if (!existing) {
      this.sql.exec(
        "INSERT INTO agents (id, name, status, task, note, started_at, updated_at, finished_at, run) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)",
        id, name, status, task, note, now, now, done ? now : null,
      );
    } else {
      // "started" after a finished run begins a new run, so the app can tell them apart.
      const newRun = status === "started" && existing.finished_at !== null;
      this.sql.exec(
        `UPDATE agents SET name = ?, status = ?, task = COALESCE(?, task), note = ?,
           started_at = ?, updated_at = ?, finished_at = ?, run = ? WHERE id = ?`,
        name, status, task, note,
        newRun ? now : existing.started_at ?? now,
        now,
        done ? now : null,
        newRun ? existing.run + 1 : existing.run,
        id,
      );
    }
    return { ok: true, id, status };
  }

  async remove(id) {
    this.sql.exec("DELETE FROM agents WHERE id = ?", id);
    return { ok: true };
  }
}

// The pour queue: things you poured onto the Agents dot in Perch, waiting for a bot to pick them up.
export class Requests extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
  }

  ensureRequests() {
    this.sql.exec(`CREATE TABLE IF NOT EXISTS requests (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      title TEXT,
      body TEXT,
      source TEXT,
      status TEXT NOT NULL,
      claimed_by TEXT,
      note TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )`);
    this.sql.exec("DELETE FROM requests WHERE status = 'done' AND updated_at < ?", Date.now() - DONE_REQUEST_TTL_MS);
  }

  async listRequests() {
    this.ensureRequests();
    const requests = this.sql
      .exec("SELECT * FROM requests ORDER BY (status = 'done') ASC, created_at DESC LIMIT ?", MAX_REQUESTS)
      .toArray()
      .map((r) => ({
        id: r.id, kind: r.kind, title: r.title, body: r.body, source: r.source, status: r.status,
        claimedBy: r.claimed_by, note: r.note, createdAt: r.created_at, updatedAt: r.updated_at,
      }));
    return { requests, now: Date.now() };
  }

  async addRequest({ kind, title, body, source }) {
    this.ensureRequests();
    const open = this.sql.exec("SELECT COUNT(*) AS n FROM requests WHERE status != 'done'").one().n;
    if (open >= MAX_REQUESTS) return { error: "too many open requests" };
    const id = crypto.randomUUID().replace(/-/g, "").slice(0, 12);
    const now = Date.now();
    this.sql.exec(
      "INSERT INTO requests (id, kind, title, body, source, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'open', ?, ?)",
      id, kind, title, body, source, now, now,
    );
    return { ok: true, id };
  }

  async updateRequest(id, status, by, note) {
    this.ensureRequests();
    this.sql.exec(
      "UPDATE requests SET status = ?, claimed_by = COALESCE(?, claimed_by), note = COALESCE(?, note), updated_at = ? WHERE id = ?",
      status, by, note, Date.now(), id,
    );
    return { ok: true, id, status };
  }

  async removeRequest(id) {
    this.ensureRequests();
    this.sql.exec("DELETE FROM requests WHERE id = ?", id);
    return { ok: true };
  }
}
