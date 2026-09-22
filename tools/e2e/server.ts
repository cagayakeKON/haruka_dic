// Isolated fixture static server: API and missing assets never receive SPA HTML.
import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, resolve, sep } from "node:path";

const root = resolve(import.meta.dirname, "../../frontend/build/web-controls");
const types: Record<string, string> = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".json": "application/json",
  ".wasm": "application/wasm",
};

async function serve(
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  try {
    const pathname = decodeURIComponent(
      new URL(request.url ?? "/", "http://127.0.0.1").pathname,
    );
    const isPage =
      /^\/(?:admin\/)?fixture(?:\/next)?$/.test(pathname) || pathname === "/";
    const path = resolve(root, isPage ? "index.html" : `.${pathname}`);
    if (!path.startsWith(root + sep) || !(await stat(path)).isFile())
      throw new Error("not found");
    response.writeHead(200, {
      "Content-Type": types[extname(path)] ?? "application/octet-stream",
      "Cache-Control": "no-store",
    });
    response.end(await readFile(path));
  } catch {
    response.writeHead(404, { "Content-Type": "text/plain" });
    response.end("Not found");
  }
}

const server = createServer((request, response) => {
  void serve(request, response);
});
server.listen(5174, "127.0.0.1");
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => server.close());
