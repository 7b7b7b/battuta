(function startSimuBoard() {
  const DEFAULTS = {
    enabled: true,
    profile: "holypanda",
    volume: 0.42,
    releaseSound: true,
    pitchVariation: true,
    disabledHosts: []
  };

  const profiles = globalThis.SIMUBOARD_PROFILES || [];
  const profileMap = new Map(profiles.map((profile) => [profile.id, profile]));
  const pools = new Map();
  const pressed = new Set();
  let settings = { ...DEFAULTS };

  function isPlayableEvent(event) {
    if (event.isComposing || event.key === "Process" || event.key === "Dead") return false;
    if (["Shift", "Control", "Alt", "Meta", "CapsLock", "NumLock", "ScrollLock"].includes(event.key)) return false;
    if (/^F\d{1,2}$/.test(event.key)) return false;
    return event.key.length === 1 || ["Backspace", "Enter", "Tab", " ", "Delete", "Escape"].includes(event.key);
  }

  function isActiveHere() {
    return settings.enabled && !settings.disabledHosts.includes(location.hostname);
  }

  function rowForCode(code) {
    if (/^(Backquote|Digit\d|Minus|Equal)$/.test(code)) return "R0";
    if (/^(Key[QWERTYUIOP]|BracketLeft|BracketRight|Backslash)$/.test(code)) return "R1";
    if (/^(Key[ASDFGHJKL]|Semicolon|Quote)$/.test(code)) return "R2";
    if (/^(Key[ZXCVBNM]|Comma|Period|Slash)$/.test(code)) return "R3";
    return "R4";
  }

  function specialName(event) {
    if (event.code === "Space") return "SPACE";
    if (event.code === "Enter" || event.code === "NumpadEnter") return "ENTER";
    if (event.code === "Backspace" || event.code === "Delete") return "BACKSPACE";
    return null;
  }

  function audioPath(event, phase) {
    const profile = profileMap.get(settings.profile) || profiles[0];
    if (!profile) return null;
    const special = profile.genericOnly ? null : specialName(event);
    if (phase === "release") {
      return `audio/${profile.id}/release/${special || "GENERIC"}.mp3`;
    }
    return `audio/${profile.id}/press/${special || `GENERIC_${rowForCode(event.code)}`}.mp3`;
  }

  function getPool(path) {
    if (!pools.has(path)) {
      const voices = Array.from({ length: 8 }, () => {
        const audio = new Audio(chrome.runtime.getURL(path));
        audio.preload = "auto";
        return audio;
      });
      pools.set(path, { voices, cursor: 0 });
    }
    return pools.get(path);
  }

  function play(path) {
    if (!path) return;
    const pool = getPool(path);
    const audio = pool.voices.find((voice) => voice.paused || voice.ended) || pool.voices[pool.cursor];
    pool.cursor = (pool.cursor + 1) % pool.voices.length;
    audio.pause();
    audio.currentTime = 0;
    audio.volume = Math.max(0, Math.min(1, Number(settings.volume)));
    audio.playbackRate = settings.pitchVariation ? 0.97 + Math.random() * 0.06 : 1;
    audio.play().catch(() => {});
  }

  function warmCurrentProfile() {
    pools.clear();
    const fakeEvent = (code) => ({ code });
    for (const code of ["Digit1", "KeyQ", "KeyA", "KeyZ", "Tab", "Space", "Enter", "Backspace"]) {
      getPool(audioPath(fakeEvent(code), "press"));
      if (settings.releaseSound) getPool(audioPath(fakeEvent(code), "release"));
    }
  }

  function onKeyDown(event) {
    if (!isActiveHere() || !isPlayableEvent(event) || event.repeat || pressed.has(event.code)) return;
    pressed.add(event.code);
    play(audioPath(event, "press"));
  }

  function onKeyUp(event) {
    pressed.delete(event.code);
    if (!isActiveHere() || !settings.releaseSound || !isPlayableEvent(event)) return;
    play(audioPath(event, "release"));
  }

  chrome.storage.sync.get(DEFAULTS, (stored) => {
    settings = { ...DEFAULTS, ...stored };
    if (!profileMap.has(settings.profile)) settings.profile = DEFAULTS.profile;
    warmCurrentProfile();
  });

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "sync") return;
    for (const [key, change] of Object.entries(changes)) settings[key] = change.newValue;
    if (changes.profile || changes.releaseSound) warmCurrentProfile();
  });

  addEventListener("keydown", onKeyDown, true);
  addEventListener("keyup", onKeyUp, true);
  addEventListener("blur", () => pressed.clear(), true);
})();
