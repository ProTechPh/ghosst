import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

/**
 * The Worker's own imports are extensionless ("../lib/http"): a bundler resolves
 * them, Node's ESM resolver does not. Map those specifiers to the .ts file so
 * `node --test` can import src modules directly.
 */
export function resolve(specifier, context, next) {
  if (specifier.startsWith(".") && !/\.[cm]?[jt]s$/i.test(specifier)) {
    const url = new URL(`${specifier}.ts`, context.parentURL);
    if (existsSync(fileURLToPath(url))) return next(url.href, context);
  }
  return next(specifier, context);
}
