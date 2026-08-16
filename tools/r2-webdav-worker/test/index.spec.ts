import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

const baseUrl = "https://joycomic.test";
const auth = `Basic ${btoa("joycomic-test:test-password")}`;

function davFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  headers.set("Authorization", auth);
  return SELF.fetch(`${baseUrl}${path}`, { ...init, headers });
}

describe("JoyComic R2 WebDAV bridge", () => {
  beforeEach(async () => {
    let cursor: string | undefined;
    do {
      const listed = await env.BACKUPS.list({
        prefix: "joycomic-webdav/",
        cursor,
      });
      if (listed.objects.length > 0) {
        await env.BACKUPS.delete(listed.objects.map((object) => object.key));
      }
      cursor = listed.truncated ? listed.cursor : undefined;
    } while (cursor !== undefined);
  });

  it("requires HTTP Basic authentication", async () => {
    const response = await SELF.fetch(baseUrl, { method: "PROPFIND" });

    expect(response.status).toBe(401);
    expect(response.headers.get("WWW-Authenticate")).toContain("Basic");
  });

  it("supports the exact JoyComic backup and restore request flow", async () => {
    const root = await davFetch("/", {
      method: "PROPFIND",
      headers: { Depth: "0" },
    });
    expect(root.status).toBe(207);

    const directory = await davFetch("/joycomic_backups", {
      method: "MKCOL",
    });
    expect(directory.status).toBe(201);

    const bytes = new Uint8Array([0x50, 0x4b, 0x03, 0x04]);
    const upload = await davFetch(
      "/joycomic_backups/backup_2026-08-16.zip",
      {
        method: "PUT",
        headers: { "Content-Type": "application/zip" },
        body: bytes,
      },
    );
    expect(upload.status).toBe(201);

    const listing = await davFetch("/joycomic_backups", {
      method: "PROPFIND",
      headers: { Depth: "1" },
    });
    const xml = await listing.text();
    expect(listing.status).toBe(207);
    expect(xml).toContain(
      "<d:href>/joycomic_backups/backup_2026-08-16.zip</d:href>",
    );

    const download = await davFetch(
      "/joycomic_backups/backup_2026-08-16.zip",
    );
    expect(download.status).toBe(200);
    expect(new Uint8Array(await download.arrayBuffer())).toEqual(bytes);
    expect(download.headers.get("Content-Type")).toBe("application/zip");
  });

  it("supports HEAD and file deletion without deleting collections", async () => {
    const path = "/joycomic_backups/backup_2026-08-17.zip";
    await davFetch(path, { method: "PUT", body: new Uint8Array([1, 2, 3]) });

    const head = await davFetch(path, { method: "HEAD" });
    expect(head.status).toBe(200);
    expect(head.headers.get("Content-Length")).toBe("3");

    const deleted = await davFetch(path, { method: "DELETE" });
    expect(deleted.status).toBe(204);
    expect((await davFetch(path)).status).toBe(404);
    expect((await davFetch("/", { method: "DELETE" })).status).toBe(405);
  });

  it("rejects encoded path traversal", async () => {
    const response = await davFetch("/safe/%2E%2E%2Fsecret.zip", {
      method: "PUT",
      body: new Uint8Array([1]),
    });

    expect(response.status).toBe(400);
  });
});
