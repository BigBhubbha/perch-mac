// Perch agent board. Grok Bot agents report what they are doing, the Perch app reads it.
//
//   POST   /v1/events          Bearer WRITE_KEY   {"agent":"Architect III","status":"started","task":"Building Perch"}
//   GET    /v1/agents          Bearer READ_KEY    -> {"agents":[...], "now": 1730000000000}
//   DELETE /v1/agents/<id>     Bearer WRITE_KEY   remove one agent from the board
//   GET    /health                                -> {"ok":true}
//
// status is one of: started, working (a heartbeat or a new task line), finished, failed.
// Keep `task` short and free of private details: it is shown at the top of the screen.

import { DurableObject } from "cloudflare:workers";

const STATUSES = new Set(["started", "working", "finished", "failed"]);
const MAX_AGENTS = 40;
const FINISHED_TTL_MS = 12 * 60 * 60 * 1000; // finished or failed cards fade off after 12 hours
const STALE_AFTER_MS = 3 * 60 * 60 * 1000; // a working agent with no news for 3 hours is shown as quiet

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
