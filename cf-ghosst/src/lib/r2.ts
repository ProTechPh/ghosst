import { AwsClient } from "aws4fetch";

export interface PresignedTicket {
  url: string;
  headers: Record<string, string>;
  expiresIn: number;
}

let client: AwsClient | null = null;

function s3(env: Env): AwsClient {
  // One signer per isolate — rebuilding it costs CPU on every request.
  if (!client) {
    client = new AwsClient({
      accessKeyId: env.R2_ACCESS_KEY_ID,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY,
      service: "s3",
      region: "auto",
    });
  }
  return client;
}

function encodeKey(key: string): string {
  return key.split("/").map(encodeURIComponent).join("/");
}

function objectUrl(env: Env, key: string): URL {
  return new URL(
    `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${env.R2_BUCKET}/${encodeKey(key)}`,
  );
}

/**
 * Presigned PUT for a direct upload.
 * 300s is plenty for a 300 MB APK on mobile data and keeps a leaked URL
 * worthless. `contentType` is a signed header: the client must replay it
 * byte-for-byte or R2 answers 403.
 */
export async function presignPut(
  env: Env,
  key: string,
  contentType: string,
  ttlSeconds = 300,
): Promise<PresignedTicket> {
  const url = objectUrl(env, key);
  url.searchParams.set("X-Amz-Expires", String(ttlSeconds));

  const headers = new Headers({ "content-type": contentType });
  const signed = await s3(env).sign(url.toString(), {
    method: "PUT",
    headers,
    aws: { signQuery: true },
  });

  return {
    url: signed.url,
    headers: { "content-type": contentType },
    expiresIn: ttlSeconds,
  };
}

/**
 * Presigned GET for a paid file. `filename` rides along as a signed
 * response-content-disposition so Android's downloader saves a sane name.
 */
export async function presignGet(
  env: Env,
  key: string,
  opts: { ttlSeconds?: number; filename?: string } = {},
): Promise<PresignedTicket> {
  const ttl = opts.ttlSeconds ?? 300;
  const url = objectUrl(env, key);
  url.searchParams.set("X-Amz-Expires", String(ttl));
  if (opts.filename) {
    url.searchParams.set(
      "response-content-disposition",
      `attachment; filename="${opts.filename.replace(/["\\]/g, "")}"`,
    );
  }

  const signed = await s3(env).sign(url.toString(), {
    method: "GET",
    aws: { signQuery: true },
  });

  return { url: signed.url, headers: {}, expiresIn: ttl };
}

/**
 * Verifies through the R2 binding (no SigV4): presigned PUT cannot carry
 * content-length-range, so the real size/type check happens here.
 */
export async function verifyObject(env: Env, key: string) {
  const head = await env.BUCKET.head(key);
  if (!head) return null;
  return {
    size: head.size,
    contentType: head.httpMetadata?.contentType ?? "",
    etag: head.etag,
  };
}
