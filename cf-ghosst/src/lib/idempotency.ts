/**
 * Idempotency for POST /v1/claims. A repeated key returns the first response
 * verbatim, so a dropped connection can never charge coins twice.
 */
export async function replay(
  env: Env,
  userId: string,
  key: string,
): Promise<Response | null> {
  const row = await env.DB.prepare(
    `SELECT response FROM idempotency WHERE key = ?1 AND user_id = ?2`,
  )
    .bind(key, userId)
    .first<{ response: string }>();

  if (!row) return null;
  return new Response(row.response, {
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function store(
  env: Env,
  userId: string,
  key: string,
  res: Response,
): Promise<void> {
  const body = await res.clone().text();
  await env.DB.prepare(
    `INSERT INTO idempotency (key, user_id, response, created_at)
     VALUES (?1, ?2, ?3, ?4) ON CONFLICT(key) DO NOTHING`,
  )
    .bind(key, userId, body, new Date().toISOString())
    .run();
}
