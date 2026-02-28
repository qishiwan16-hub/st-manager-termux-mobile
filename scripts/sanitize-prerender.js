#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const appDir = process.argv[2] ? path.resolve(process.argv[2]) : process.cwd();
const routes = process.argv.length > 3 ? process.argv.slice(3) : ["settings", "worlds"];
const appServerDir = path.join(appDir, ".next", "server", "app");

function isValidHtml(content) {
  if (!content.includes("<title")) return false;
  if (!content.includes("</title>")) return false;
  if (content.includes("?/title>")) return false;
  return true;
}

function isValidMeta(content) {
  try {
    const parsed = JSON.parse(content);
    return !!parsed && typeof parsed === "object" && parsed.headers && typeof parsed.headers === "object";
  } catch {
    return false;
  }
}

function safeRead(file) {
  try {
    return fs.readFileSync(file, "utf8");
  } catch {
    return null;
  }
}

function safeRemove(file) {
  try {
    fs.rmSync(file, { force: true });
  } catch {
    // best effort cleanup
  }
}

if (!fs.existsSync(appServerDir)) {
  process.exit(0);
}

let removedCount = 0;
for (const route of routes) {
  const htmlFile = path.join(appServerDir, `${route}.html`);
  const metaFile = path.join(appServerDir, `${route}.meta`);
  const rscFile = path.join(appServerDir, `${route}.rsc`);

  const html = safeRead(htmlFile);
  const meta = safeRead(metaFile);
  const invalid = !html || !isValidHtml(html) || !meta || !isValidMeta(meta);

  if (!invalid) continue;

  safeRemove(htmlFile);
  safeRemove(metaFile);
  safeRemove(rscFile);
  removedCount += 1;
  console.log(`[sanitize] removed corrupted prerender artifacts for /${route}`);
}

if (removedCount === 0) {
  console.log("[sanitize] prerender artifacts look healthy");
}
