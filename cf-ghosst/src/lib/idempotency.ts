/**
 * Idempotency for POST /v1/claims.
 *
 * The row is RESERVED before any work happens, so two in-flight requests with
 * the same key cannot both charge. A reserved-but-unfinished row means "still
 * running" — the client is told to retry rather than being charged twice.
 */
export type Reservation =
  | { state: "new" }
  | { state: "replay"; response: string }
  | { state: "in_flight" };

export async function reserve(
  env: Env,
  userId: string,
  key: string,
): Promise<Reservation> {
  const won = await env.DB.prepare(
    `INSERT INTO idempotency (user_id, key, response, created_at)
     VALUES (?1, ?2, '', ?3)
     ON CONFLICT(user_id, key) DO NOTHING
     RETURNING key`,
  )
    .bind(userId, key, new Date().toISOString())
    .first<{ key: string }>();

  if (won) return { state: "new" };

  const existing = await env.DB.prepare(
    `SELECT response FROM idempotency WHERE user_id = ?1 AND key = ?2`,
  )
    .bind(userId, key)
    .first<{ response: string }>();

  if (existing && existing.response) return { state: "replay", response: existing.response };
  return { state: "in_flight" };
}

export async function complete(
  env: Env,
  userId: string,
  key: string,
  res: Response,
): Promise<void> {
  const body = await res.clone().text();
  await env.DB.prepare(
    `UPDATE idempotency SET response = ?3 WHERE user_id = ?1 AND key = ?2`,
  )
    .bind(userId, key, body)
    .run();
}

/** Frees the reservation after a failure so the client may retry the same key. */
export async function release(env: Env, userId: string, key: string): Promise<void> {
  await env.DB.prepare(`DELETE FROM idempotency WHERE user_id = ?1 AND key = ?2`)
    .bind(userId, key)
    .run();
}
