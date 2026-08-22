import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import { resolve } from "node:path";
import vm from "node:vm";

const root = resolve(import.meta.dirname, "..");
const manifest = JSON.parse(await readFile(resolve(root, "manifest.json"), "utf8"));
assert.equal(manifest.manifest_version, 3);
assert.equal(manifest.action.default_popup, "popup.html");

const profileContext = { globalThis: {} };
vm.runInNewContext(await readFile(resolve(root, "profiles.js"), "utf8"), profileContext);
const profiles = profileContext.globalThis.SIMUBOARD_PROFILES;
assert.equal(profiles.length, 13);
assert.equal(new Set(profiles.map(({ id }) => id)).size, profiles.length);

const requiredGeneric = [
  ...[0, 1, 2, 3, 4].map((row) => `press/GENERIC_R${row}.mp3`),
  "release/GENERIC.mp3"
];

for (const profile of profiles) {
  for (const relativePath of requiredGeneric) {
    const file = resolve(root, "audio", profile.id, relativePath);
    assert.ok((await stat(file)).size > 0, `${profile.id}/${relativePath} is missing or empty`);
  }
  if (!profile.genericOnly) {
    for (const phase of ["press", "release"]) {
      for (const key of ["SPACE", "ENTER", "BACKSPACE"]) {
        const file = resolve(root, "audio", profile.id, phase, `${key}.mp3`);
        assert.ok((await stat(file)).size > 0, `${profile.id}/${phase}/${key}.mp3 is missing or empty`);
      }
    }
  }
}

const listeners = {};
const played = [];
class FakeAudio {
  constructor(url) {
    this.url = url;
    this.paused = true;
    this.ended = true;
    this.currentTime = 0;
  }
  pause() { this.paused = true; }
  play() {
    this.paused = false;
    played.push(this.url);
    return Promise.resolve();
  }
}

const extensionContext = {
  SIMUBOARD_PROFILES: profiles,
  Audio: FakeAudio,
  chrome: {
    runtime: { getURL: (path) => `chrome-extension://test/${path}` },
    storage: {
      sync: { get: (defaults, callback) => callback(defaults) },
      onChanged: { addListener: () => {} }
    }
  },
  location: { hostname: "example.test" },
  addEventListener: (name, listener) => { listeners[name] = listener; }
};
vm.createContext(extensionContext);
vm.runInContext(await readFile(resolve(root, "content.js"), "utf8"), extensionContext);
listeners.keydown({ isComposing: false, key: "a", code: "KeyA", repeat: false });
listeners.keyup({ isComposing: false, key: "a", code: "KeyA" });
assert.deepEqual(played, [
  "chrome-extension://test/audio/holypanda/press/GENERIC_R2.mp3",
  "chrome-extension://test/audio/holypanda/release/GENERIC.mp3"
]);

console.log(`Verified Battuta ${manifest.version}: ${profiles.length} profiles, audio assets, and keyboard playback routing.`);
