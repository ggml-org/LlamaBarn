#!/usr/bin/env -S deno run --allow-read --allow-net

const catalogPath = new URL("../LlamaBarn/ModelCatalog/ModelCatalog.swift", import.meta.url);
const catalogText = await Deno.readTextFile(catalogPath);

const urls = [...new Set(
  [...catalogText.matchAll(/https:\/\/huggingface\.co\/[^"'\s]+\.gguf(?:[^"'\s]*)?/gi)]
    .map((match) => match[0])
)];

if (urls.length === 0) {
  console.error(`No GGUF URLs found in ${catalogPath.pathname}`);
  Deno.exit(1);
}

console.log(`Validating ${urls.length} GGUF URL(s)...`);

const results = await Promise.all(urls.map(async (url) => {
  try {
    let response = await fetch(url, { method: "HEAD", redirect: "follow" });
    if (response.status === 405 || response.status === 403) {
      response = await fetch(url, { method: "GET", redirect: "follow" });
    }
    return { url, ok: response.ok, status: response.status };
  } catch (error) {
    return { url, ok: false, status: 0, error: String(error) };
  }
}));

for (const { url, ok, status, error } of results) {
  console.log(`${ok ? "OK " : "ERR"} ${status} ${url}${error ? ` (${error})` : ""}`);
}

if (results.some(({ ok }) => !ok)) {
  Deno.exit(1);
}

console.log("All GGUF URLs are reachable.");
