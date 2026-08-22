(function setupPopup() {
  const DEFAULTS = {
    enabled: true,
    profile: "holypanda",
    volume: 0.42,
    releaseSound: true,
    pitchVariation: true,
    disabledHosts: []
  };
  const profiles = globalThis.SIMUBOARD_PROFILES || [];
  const byId = new Map(profiles.map((profile) => [profile.id, profile]));
  const extensionApi = globalThis.chrome;
  const storageApi = extensionApi?.storage?.sync;
  const runtimeUrl = extensionApi?.runtime?.getURL
    ? (path) => extensionApi.runtime.getURL(path)
    : (path) => path;
  const elements = Object.fromEntries(
    ["enabled", "profile", "volume", "volumeValue", "releaseSound", "pitchVariation", "siteMuted", "host", "family", "tone", "preview"]
      .map((id) => [id, document.getElementById(id)])
  );
  let state = { ...DEFAULTS };
  let activeHost = "";

  function readSettings(callback) {
    if (storageApi) {
      storageApi.get(DEFAULTS, callback);
      return;
    }
    const local = JSON.parse(localStorage.getItem("simuboard-preview") || "{}");
    callback({ ...DEFAULTS, ...local });
  }

  function writeSettings(patch) {
    if (storageApi) {
      storageApi.set(patch);
      return;
    }
    localStorage.setItem("simuboard-preview", JSON.stringify({ ...state, ...patch }));
  }

  for (const profile of profiles) {
    const option = document.createElement("option");
    option.value = profile.id;
    option.textContent = `${profile.name} · ${profile.family}`;
    elements.profile.append(option);
  }

  function renderProfile() {
    const profile = byId.get(state.profile) || profiles[0];
    if (!profile) return;
    elements.family.textContent = profile.family;
    elements.tone.textContent = profile.tone;
  }

  function render() {
    elements.enabled.checked = state.enabled;
    elements.profile.value = state.profile;
    elements.volume.value = state.volume;
    elements.volumeValue.value = `${Math.round(state.volume * 100)}%`;
    elements.releaseSound.checked = state.releaseSound;
    elements.pitchVariation.checked = state.pitchVariation;
    elements.siteMuted.checked = activeHost ? state.disabledHosts.includes(activeHost) : false;
    elements.siteMuted.disabled = !activeHost;
    elements.host.textContent = activeHost || "此页面不支持插件";
    document.body.classList.toggle("is-disabled", !state.enabled);
    renderProfile();
  }

  function save(patch) {
    state = { ...state, ...patch };
    writeSettings(patch);
    render();
  }

  readSettings((stored) => {
    state = { ...DEFAULTS, ...stored };
    if (!byId.has(state.profile)) state.profile = DEFAULTS.profile;
    render();
  });

  const receiveActiveTab = ([tab] = []) => {
    try {
      const url = new URL(tab?.url || location.href);
      activeHost = ["http:", "https:"].includes(url.protocol) ? url.hostname : "";
    } catch (_) {
      activeHost = "";
    }
    render();
  };
  if (extensionApi?.tabs?.query) extensionApi.tabs.query({ active: true, currentWindow: true }, receiveActiveTab);
  else receiveActiveTab();

  elements.enabled.addEventListener("change", () => save({ enabled: elements.enabled.checked }));
  elements.profile.addEventListener("change", () => save({ profile: elements.profile.value }));
  elements.releaseSound.addEventListener("change", () => save({ releaseSound: elements.releaseSound.checked }));
  elements.pitchVariation.addEventListener("change", () => save({ pitchVariation: elements.pitchVariation.checked }));
  elements.volume.addEventListener("input", () => {
    elements.volumeValue.value = `${Math.round(Number(elements.volume.value) * 100)}%`;
  });
  elements.volume.addEventListener("change", () => save({ volume: Number(elements.volume.value) }));
  elements.siteMuted.addEventListener("change", () => {
    if (!activeHost) return;
    const disabledHosts = new Set(state.disabledHosts);
    elements.siteMuted.checked ? disabledHosts.add(activeHost) : disabledHosts.delete(activeHost);
    save({ disabledHosts: [...disabledHosts] });
  });
  elements.preview.addEventListener("click", () => {
    const audio = new Audio(runtimeUrl(`audio/${state.profile}/press/GENERIC_R2.mp3`));
    audio.volume = Number(elements.volume.value);
    audio.playbackRate = state.pitchVariation ? 0.97 + Math.random() * 0.06 : 1;
    audio.play().catch(() => {});
  });
})();
