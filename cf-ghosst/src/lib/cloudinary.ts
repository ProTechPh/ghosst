/**
 * Cloudinary cleanup.
 *
 * The admin app uploads through an unsigned preset, which cannot delete. Removing
 * an asset needs a signed request, so it happens here where the API secret lives.
 * Best effort by design: a dangling image costs storage, not correctness.
 */

const HOST = "res.cloudinary.com";

/** `https://res.cloudinary.com/<cloud>/image/upload/v1/folder/name.jpg` → `folder/name`. */
export function publicIdOf(url: string, cloud: string): string | null {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  if (parsed.host !== HOST) return null;

  const parts = parsed.pathname.split("/").filter(Boolean);
  if (parts[0] !== cloud || parts[1] !== "image" || parts[2] !== "upload") return null;

  const rest = parts.slice(3).filter((seg) => !/^v\d+$/.test(seg) && !/^[a-z]{1,3}_[^/]*$/.test(seg));
  if (rest.length === 0) return null;

  rest[rest.length - 1] = rest[rest.length - 1].replace(/\.[a-z0-9]+$/i, "");
  return rest.join("/");
}

/** Cloudinary signs the alphabetically sorted params with the secret appended. */
export async function signParams(
  params: Record<string, string>,
  secret: string,
): Promise<string> {
  const body = Object.keys(params)
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join("&");
  const digest = await crypto.subtle.digest(
    "SHA-1",
    new TextEncoder().encode(body + secret),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Deletes one image; returns false when it is not ours or Cloudinary is not configured. */
export async function destroyImage(env: Env, url: string): Promise<boolean> {
  const cloud = env.CLOUDINARY_CLOUD_NAME;
  const key = env.CLOUDINARY_API_KEY;
  const secret = env.CLOUDINARY_API_SECRET;
  if (!cloud || !key || !secret) return false;

  const publicId = publicIdOf(url, cloud);
  if (!publicId) return false;

  try {
    const timestamp = String(Math.floor(Date.now() / 1000));
    const body = new URLSearchParams({
      public_id: publicId,
      timestamp,
      api_key: key,
      signature: await signParams({ public_id: publicId, timestamp }, secret),
    });
    const res = await fetch(`https://api.cloudinary.com/v1_1/${cloud}/image/destroy`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body,
    });
    if (!res.ok) return false;
    const out = (await res.json()) as { result?: string };
    return out.result === "ok" || out.result === "not found";
  } catch {
    return false;
  }
}
