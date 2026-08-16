const ALLOW_METHODS = "OPTIONS, PROPFIND, MKCOL, PUT, GET, HEAD, DELETE";
const MAX_LIST_ITEMS = 5_000;
const encoder = new TextEncoder();

type SecretName = "DAV_USERNAME" | "DAV_PASSWORD";

class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

interface DavPath {
  relative: string;
  href: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (request.method === "OPTIONS") return optionsResponse();
      if (!(await isAuthorized(request, env))) return unauthorizedResponse();

      const path = parseDavPath(url.pathname);
      switch (request.method) {
        case "PROPFIND":
          return await propfind(request, env, path);
        case "MKCOL":
          return mkcol(path);
        case "PUT":
          return await putObject(request, env, path);
        case "GET":
          return await getObject(env, path, false);
        case "HEAD":
          return await getObject(env, path, true);
        case "DELETE":
          return await deleteObject(env, path);
        default:
          return new Response("Method Not Allowed", {
            status: 405,
            headers: { Allow: ALLOW_METHODS },
          });
      }
    } catch (error) {
      if (error instanceof HttpError) {
        return new Response(error.message, { status: error.status });
      }
      console.error(
        JSON.stringify({
          message: "Unhandled WebDAV request error",
          method: request.method,
          path: url.pathname,
          error: error instanceof Error ? error.message : String(error),
        }),
      );
      return new Response("Internal Server Error", { status: 500 });
    }
  },
} satisfies ExportedHandler<Env>;

async function isAuthorized(request: Request, env: Env): Promise<boolean> {
  const provided = request.headers.get("Authorization") ?? "";
  const username = readSecret(env, "DAV_USERNAME");
  const password = readSecret(env, "DAV_PASSWORD");
  const expected = `Basic ${utf8Base64(`${username}:${password}`)}`;
  const [providedHash, expectedHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  return timingSafeEqual(providedHash, expectedHash);
}

function timingSafeEqual(left: ArrayBuffer, right: ArrayBuffer): boolean {
  const method = Reflect.get(crypto.subtle, "timingSafeEqual");
  if (typeof method === "function") {
    return Boolean(Reflect.apply(method, crypto.subtle, [left, right]));
  }
  const leftBytes = new Uint8Array(left);
  const rightBytes = new Uint8Array(right);
  let difference = leftBytes.length ^ rightBytes.length;
  for (let index = 0; index < leftBytes.length; index += 1) {
    difference |= leftBytes[index] ^ (rightBytes[index] ?? 0);
  }
  return difference === 0;
}

function readSecret(env: Env, name: SecretName): string {
  const value = Reflect.get(env, name);
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpError(500, `Missing Worker secret: ${name}`);
  }
  return value;
}

function utf8Base64(value: string): string {
  const bytes = encoder.encode(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function unauthorizedResponse(): Response {
  return new Response("Unauthorized", {
    status: 401,
    headers: {
      "Cache-Control": "no-store",
      "WWW-Authenticate": 'Basic realm="JoyComic R2 WebDAV", charset="UTF-8"',
    },
  });
}

function optionsResponse(): Response {
  return new Response(null, {
    status: 204,
    headers: {
      Allow: ALLOW_METHODS,
      DAV: "1",
      "MS-Author-Via": "DAV",
    },
  });
}

function parseDavPath(pathname: string): DavPath {
  let decoded: string;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    throw new HttpError(400, "Invalid URL encoding");
  }
  if (decoded.includes("\0") || decoded.includes("\\")) {
    throw new HttpError(400, "Invalid WebDAV path");
  }
  const segments = decoded.split("/").filter((segment) => segment.length > 0);
  if (segments.some((segment) => segment === "." || segment === "..")) {
    throw new HttpError(400, "Path traversal is not allowed");
  }
  const relative = segments.join("/");
  return { relative, href: hrefFor(relative, pathname.endsWith("/")) };
}

function hrefFor(relative: string, collection: boolean): string {
  const encoded = relative
    .split("/")
    .filter(Boolean)
    .map((segment) => encodeURIComponent(segment))
    .join("/");
  if (encoded.length === 0) return "/";
  return `/${encoded}${collection ? "/" : ""}`;
}

function rootPrefix(env: Env): string {
  const prefix = env.ROOT_PREFIX.replace(/^\/+|\/+$/g, "");
  if (prefix.length === 0 || prefix.split("/").includes("..")) {
    throw new HttpError(500, "ROOT_PREFIX is invalid");
  }
  return prefix;
}

function objectKey(env: Env, relative: string): string {
  return `${rootPrefix(env)}/${relative}`;
}

function collectionPrefix(env: Env, relative: string): string {
  const base = objectKey(env, relative);
  return base.endsWith("/") ? base : `${base}/`;
}

async function propfind(
  request: Request,
  env: Env,
  path: DavPath,
): Promise<Response> {
  const depth = request.headers.get("Depth") ?? "0";
  if (depth !== "0" && depth !== "1") {
    throw new HttpError(403, "Only Depth 0 and Depth 1 are supported");
  }

  const exact = path.relative.length > 0
    ? await env.BACKUPS.head(objectKey(env, path.relative))
    : null;
  const isCollection = exact === null;
  const responses = [
    exact === null
      ? collectionXml(hrefFor(path.relative, true))
      : objectXml(path.href, exact),
  ];

  if (depth === "1" && isCollection) {
    const prefix = collectionPrefix(env, path.relative);
    let cursor: string | undefined;
    let count = 0;
    do {
      const listed = await env.BACKUPS.list({
        prefix,
        delimiter: "/",
        cursor,
        limit: Math.min(1_000, MAX_LIST_ITEMS - count),
        include: ["httpMetadata"],
      });
      for (const childPrefix of listed.delimitedPrefixes) {
        responses.push(
          collectionXml(hrefFor(stripStoragePrefix(env, childPrefix), true)),
        );
        count += 1;
      }
      for (const object of listed.objects) {
        responses.push(
          objectXml(hrefFor(stripStoragePrefix(env, object.key), false), object),
        );
        count += 1;
      }
      cursor = listed.truncated ? listed.cursor : undefined;
    } while (cursor !== undefined && count < MAX_LIST_ITEMS);
  }

  const body = [
    '<?xml version="1.0" encoding="utf-8"?>',
    '<d:multistatus xmlns:d="DAV:">',
    ...responses,
    "</d:multistatus>",
  ].join("");
  return new Response(body, {
    status: 207,
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": "application/xml; charset=utf-8",
      DAV: "1",
    },
  });
}

function collectionXml(href: string): string {
  return [
    "<d:response>",
    `<d:href>${escapeXml(href)}</d:href>`,
    "<d:propstat><d:prop>",
    "<d:resourcetype><d:collection/></d:resourcetype>",
    "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>",
    "</d:response>",
  ].join("");
}

function objectXml(href: string, object: R2Object): string {
  const contentType = object.httpMetadata?.contentType ?? "application/octet-stream";
  return [
    "<d:response>",
    `<d:href>${escapeXml(href)}</d:href>`,
    "<d:propstat><d:prop>",
    "<d:resourcetype/>",
    `<d:getcontentlength>${object.size}</d:getcontentlength>`,
    `<d:getcontenttype>${escapeXml(contentType)}</d:getcontenttype>`,
    `<d:getetag>${escapeXml(object.httpEtag)}</d:getetag>`,
    `<d:getlastmodified>${object.uploaded.toUTCString()}</d:getlastmodified>`,
    "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>",
    "</d:response>",
  ].join("");
}

function escapeXml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function stripStoragePrefix(env: Env, key: string): string {
  const prefix = `${rootPrefix(env)}/`;
  if (!key.startsWith(prefix)) throw new HttpError(500, "Unexpected R2 key");
  return key.slice(prefix.length).replace(/\/$/, "");
}

function mkcol(path: DavPath): Response {
  if (path.relative.length === 0) {
    return new Response("Root collection already exists", { status: 405 });
  }
  return new Response(null, { status: 201 });
}

async function putObject(
  request: Request,
  env: Env,
  path: DavPath,
): Promise<Response> {
  if (path.relative.length === 0 || request.body === null) {
    throw new HttpError(400, "PUT requires a file path and request body");
  }
  const key = objectKey(env, path.relative);
  const existed = (await env.BACKUPS.head(key)) !== null;
  await env.BACKUPS.put(key, request.body, {
    httpMetadata: {
      contentType:
        request.headers.get("Content-Type") ?? "application/octet-stream",
    },
  });
  return new Response(null, { status: existed ? 204 : 201 });
}

async function getObject(
  env: Env,
  path: DavPath,
  headOnly: boolean,
): Promise<Response> {
  if (path.relative.length === 0) {
    return new Response("Use PROPFIND for collections", {
      status: 405,
      headers: { Allow: ALLOW_METHODS },
    });
  }
  const key = objectKey(env, path.relative);
  if (headOnly) {
    const object = await env.BACKUPS.head(key);
    if (object === null) return new Response("Not Found", { status: 404 });
    return new Response(null, { status: 200, headers: objectHeaders(object) });
  }
  const object = await env.BACKUPS.get(key);
  if (object === null) return new Response("Not Found", { status: 404 });
  return new Response(object.body, {
    status: 200,
    headers: objectHeaders(object),
  });
}

function objectHeaders(object: R2Object): Headers {
  const headers = new Headers({
    "Cache-Control": "private, no-store",
    "Content-Length": object.size.toString(),
    ETag: object.httpEtag,
    "Last-Modified": object.uploaded.toUTCString(),
  });
  object.writeHttpMetadata(headers);
  return headers;
}

async function deleteObject(env: Env, path: DavPath): Promise<Response> {
  if (path.relative.length === 0) {
    return new Response("Deleting the WebDAV root is not allowed", {
      status: 405,
    });
  }
  const key = objectKey(env, path.relative);
  if ((await env.BACKUPS.head(key)) === null) {
    return new Response("Not Found", { status: 404 });
  }
  await env.BACKUPS.delete(key);
  return new Response(null, { status: 204 });
}
