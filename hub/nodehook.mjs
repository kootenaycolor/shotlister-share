import { register } from "node:module";
register("data:text/javascript," + encodeURIComponent(`
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
export async function load(url, context, next) {
  if (url.endsWith(".wasm")) {
    const b = readFileSync(fileURLToPath(url));
    return { format: "module", shortCircuit: true, source: "const b = Uint8Array.from(atob('" + b.toString("base64") + "'), c => c.charCodeAt(0)); export default new WebAssembly.Module(b);" };
  }
  if (/\.(bin|ttf|woff2?|otf)$/.test(url)) {
    const b = readFileSync(fileURLToPath(url));
    return { format: "module", shortCircuit: true, source: "const b = Uint8Array.from(atob('" + b.toString("base64") + "'), c => c.charCodeAt(0)); export default b.buffer;" };
  }
  if (url.endsWith(".json")) {
    return { format: "json", shortCircuit: true, source: readFileSync(fileURLToPath(url), "utf8") };
  }
  return next(url, context);
}
`));
