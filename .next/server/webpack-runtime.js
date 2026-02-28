"use strict";

const path = require("path");

const moduleFactories = Object.create(null);
const moduleCache = Object.create(null);
const loadedChunks = Object.create(null);

function __webpack_require__(moduleId) {
  const id = String(moduleId);

  if (__webpack_require__.c[id]) {
    return __webpack_require__.c[id].exports;
  }

  const factory = __webpack_require__.m[id];
  if (!factory) {
    const err = new Error(`Cannot find webpack module '${id}'`);
    err.code = "MODULE_NOT_FOUND";
    throw err;
  }

  const module = (__webpack_require__.c[id] = { exports: {} });
  factory(module, module.exports, __webpack_require__);
  return module.exports;
}

__webpack_require__.m = moduleFactories;
__webpack_require__.c = moduleCache;

__webpack_require__.o = (obj, prop) => Object.prototype.hasOwnProperty.call(obj, prop);

__webpack_require__.d = (exports, definition) => {
  for (const key in definition) {
    if (__webpack_require__.o(definition, key) && !__webpack_require__.o(exports, key)) {
      Object.defineProperty(exports, key, { enumerable: true, get: definition[key] });
    }
  }
};

__webpack_require__.r = (exports) => {
  if (typeof Symbol !== "undefined" && Symbol.toStringTag) {
    Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
  }
  Object.defineProperty(exports, "__esModule", { value: true });
};

__webpack_require__.n = (module) => {
  const getter = module && module.__esModule ? () => module.default : () => module;
  __webpack_require__.d(getter, { a: getter });
  return getter;
};

__webpack_require__.t = (value, mode) => {
  if (mode & 1) {
    value = __webpack_require__(value);
  }
  if (mode & 8) {
    return value;
  }
  if (typeof value === "object" && value) {
    if ((mode & 4) && value.__esModule) {
      return value;
    }
    if ((mode & 16) && typeof value.then === "function") {
      return value;
    }
  }
  const namespace = Object.create(null);
  __webpack_require__.r(namespace);
  const definition = { default: () => value };
  if (value && (typeof value === "object" || typeof value === "function")) {
    for (const key in value) {
      definition[key] = () => value[key];
    }
  }
  __webpack_require__.d(namespace, definition);
  return namespace;
};

function registerChunk(chunk) {
  if (!chunk || typeof chunk !== "object") {
    return;
  }

  if (chunk.modules && typeof chunk.modules === "object") {
    for (const id in chunk.modules) {
      __webpack_require__.m[id] = chunk.modules[id];
    }
  }

  const ids = Array.isArray(chunk.ids) ? chunk.ids : chunk.id != null ? [chunk.id] : [];
  for (const id of ids) {
    loadedChunks[id] = true;
  }
}

function ensureChunkLoaded(chunkId) {
  if (loadedChunks[chunkId]) {
    return;
  }

  const chunkPath = path.join(__dirname, "chunks", `${chunkId}.js`);
  const chunk = require(chunkPath);
  registerChunk(chunk);
}

__webpack_require__.C = registerChunk;
__webpack_require__.X = (_unused, chunkIds, execute) => {
  if (Array.isArray(chunkIds)) {
    for (const chunkId of chunkIds) {
      ensureChunkLoaded(chunkId);
    }
  }
  return execute();
};

module.exports = __webpack_require__;
