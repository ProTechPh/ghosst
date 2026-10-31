import { DatabaseSync } from "node:sqlite";

/**
 * Minimal D1 stand-in over node:sqlite (Node 26). Covers the subset the Worker
 * uses: prepare/bind/first/run/all/batch, numbered ?N params, batch = one
 * transaction. Not a D1 emulator — no meta.duration, no RETURNING-in-batch.
 */
export function d1(schema) {
  const raw = new DatabaseSync(":memory:");
  raw.exec(schema);
  return { raw, prepare: (sql) => new Statement(raw, sql), batch: (stmts) => batch(raw, stmts) };
}

async function batch(raw, stmts) {
  raw.exec("BEGIN");
  try {
    const out = [];
    for (const s of stmts) out.push(await s.run());
    raw.exec("COMMIT");
    return out;
  } catch (err) {
    raw.exec("ROLLBACK");
    throw err;
  }
}

class Statement {
  constructor(raw, sql, values = []) {
    this.raw = raw;
    this.sql = sql;
    this.values = values;
  }

  bind(...values) {
    // D1 rejects undefined; the Worker never sends it, but null is normal.
    return new Statement(this.raw, this.sql, values.map((v) => (v === undefined ? null : v)));
  }

  _stmt() {
    return this.raw.prepare(this.sql);
  }

  async first(column) {
    const row = this._stmt().get(...this.values);
    if (!row) return null;
    return column ? (row[column] ?? null) : row;
  }

  async all() {
    return { results: this._stmt().all(...this.values), meta: { changes: 0 } };
  }

  async run() {
    const r = this._stmt().run(...this.values);
    return { results: [], meta: { changes: Number(r.changes) } };
  }
}
