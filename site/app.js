// Cube City Studio: start a story video or a chase / action video, follow the run, watch and
// download the videos. Everything talks straight to api.github.com from this browser. Videos are
// the releases the workflows publish (story-<run id>, chase-<run id>); their notes end with a JSON
// block this page reads.
"use strict";
(() => {
  const API = "https://api.github.com";
  const TOKEN_KEY = "cubecity.studio.token";
  const FORM_KEY = "cubecity.studio.form";
  const KIND_KEY = "cubecity.studio.kind";
  const PAGE = 30;
  // the inputs shown before "More options", per workflow
  const MAIN = {
    story: ["story_type", "idea", "script", "template"],
    chase: ["mode", "orientation", "duration", "title"],
  };
  const LABELS = {
    story_type: "Mood", idea: "Your idea", template: "Story recipe", script: "Script", language: "Language",
    voice: "Voices", music: "Music", orientation: "Shape", fps: "Frame rate", time: "Time of day", seed: "City seed",
    mode: "Mode", duration: "Length (seconds)", takes: "Takes", teaser: "Teaser hook (flash-forward at the start)",
    title: "Hook text on screen", _ref: "Branch",
  };
  const EMOJI = {
    funny: "😂", romantic: "💕", cringe: "😬", happy: "😄", sad: "😢", action: "💥", twist: "🌀", drama: "🎭", dark: "🖤",
    chase: "🚓", heli: "🚁", rush: "🚗", stunt: "🤸", destroy: "💥", survive: "⭐",
  };
  const CHIP_EMOJI = ["story_type", "mode"];
  const STEPS = {
    "Write the episode": "✍️ Writing the story",
    "Voices": "🎙️ Making the voices",
    "Record": "🎥 Recording the game",
    "Mix voices and write the upload text": "🎚️ Mixing sound and music",
    "Publish to the studio page": "📤 Putting the video here",
    "Install tools": "🧰 Getting ready",
    "Install Godot and recording tools": "🧰 Getting ready",
    "Pick the best take": "🏆 Picking the best take",
  };
  // what each file of a video is, in the order the download buttons are shown
  const ROLES = [
    ["video", "⬇ Video"], ["nomusic", "⬇ No-music video"], ["thumbnail", "⬇ Thumbnail"],
    ["upload", "⬇ Upload text"], ["screenplay", "⬇ Screenplay"],
  ];

  const $ = (sel, root = document) => root.querySelector(sel);
  let cfg = null;
  let flow = null; // the workflow the form is for
  let token = "";
  let pollTimer = 0;
  let videosPage = 1;
  let busy = false;
  let pending = null; // {known: Set of run ids seen before we pressed Make video, since: ms}
  let lastActive = new Set();
  let newRunId = 0;
  const releases = new Map(); // tag -> release

  // ---------- small helpers ----------
  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined && text !== null) e.textContent = String(text);
    return e;
  }
  function link(href, text, cls) {
    const a = el("a", cls, text);
    a.href = href;
    a.target = "_blank";
    a.rel = "noopener";
    return a;
  }
  function store(remember) { return remember ? window.localStorage : window.sessionStorage; }
  function readKey(s, k) { try { return s.getItem(k) || ""; } catch (e) { return ""; } }
  function writeKey(s, k, v) { try { if (v) s.setItem(k, v); else s.removeItem(k); } catch (e) { /* storage blocked */ } }
  function nice(name) { const s = name.replace(/_/g, " "); return s.charAt(0).toUpperCase() + s.slice(1); }
  function ago(iso) {
    const s = Math.max(0, (Date.now() - Date.parse(iso)) / 1000);
    if (s < 60) return "just now";
    if (s < 3600) return `${Math.round(s / 60)} min ago`;
    if (s < 86400) return `${Math.round(s / 3600)} h ago`;
    return new Date(iso).toLocaleDateString(undefined, { day: "numeric", month: "short" });
  }
  function span(sec) {
    sec = Math.max(0, Math.round(sec));
    const m = Math.floor(sec / 60);
    return m ? `${m} min ${sec % 60} s` : `${sec} s`;
  }
  function mb(bytes) {
    if (bytes < 1048576) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
    return `${(bytes / 1048576).toFixed(bytes > 10485760 ? 0 : 1)} MB`;
  }
  function toast(text) {
    const t = el("div", "toast", text);
    t.setAttribute("role", "status");
    document.body.append(t);
    setTimeout(() => t.remove(), 2200);
  }
  async function copy(text, what) {
    try {
      await navigator.clipboard.writeText(text);
    } catch (e) {
      const ta = el("textarea");
      ta.value = text;
      document.body.append(ta);
      ta.select();
      try { document.execCommand("copy"); } catch (e2) { /* nothing more to try */ }
      ta.remove();
    }
    toast(`${what} copied`);
  }
  function say(node, text, kind) {
    node.textContent = text || "";
    node.className = "msg" + (kind ? " " + kind : "");
  }

  // ---------- GitHub API ----------
  class ApiError extends Error {
    constructor(status, message) { super(message); this.status = status; }
  }
  async function gh(path, opts = {}) {
    const headers = { Accept: "application/vnd.github+json" };
    if (token) headers.Authorization = `Bearer ${token}`;
    const init = { method: opts.method || "GET", headers, cache: "no-store" };
    if (opts.body !== undefined) {
      headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(opts.body);
    }
    let r;
    try {
      r = await fetch(API + path, init);
    } catch (e) {
      throw new ApiError(0, "Can't reach GitHub. Check the internet connection.");
    }
    const left = r.headers.get("x-ratelimit-remaining");
    if (left !== null) $("#rate").textContent = `GitHub calls left this hour: ${left}`;
    const text = await r.text();
    let data = null;
    if (text) { try { data = JSON.parse(text); } catch (e) { data = text; } }
    if (!r.ok) throw new ApiError(r.status, (data && data.message) || r.statusText || `HTTP ${r.status}`);
    return data;
  }
  function explain(err, doing, perm) {
    const s = err.status;
    if (s === 401) return "GitHub says the token is wrong or has expired. Make a new one (🔑).";
    if (s === 403 && /rate limit/i.test(err.message)) {
      return token ? "GitHub's hourly limit is used up. Try again in a while."
        : "GitHub's hourly limit for visitors without a token is used up. Add a token (🔑) or try later.";
    }
    if (s === 403) return `The token is not allowed to ${doing}. Give it "${perm}" (🔑 has the steps).`;
    if (s === 404) return token ? `GitHub can't find it with this token. Does the token include ${cfg.repo}?` : "Not found. Adding a token (🔑) may help.";
    if (s === 422) return `GitHub refused: ${err.message}`;
    return err.message;
  }

  // ---------- token ----------
  function loadToken() {
    token = readKey(window.sessionStorage, TOKEN_KEY) || readKey(window.localStorage, TOKEN_KEY);
    $("#keyRemember").checked = !!readKey(window.localStorage, TOKEN_KEY);
  }
  function showKeyBox(open, note) {
    $("#keyBox").hidden = !open;
    $("#keyBtn").setAttribute("aria-expanded", String(open));
    if (open) {
      if (note) say($("#keyMsg"), note, "bad");
      $("#keyBox").scrollIntoView({ behavior: "smooth", block: "start" });
      $("#keyInput").focus({ preventScroll: true });
    }
  }
  async function checkToken() {
    const btn = $("#keyBtn");
    document.querySelectorAll(".video .del").forEach((b) => { b.hidden = !token; });
    if (!token) {
      btn.textContent = "🔑 Add token";
      btn.classList.remove("on");
      $("#runsNote").textContent = "Add a token (🔑) to start videos and see runs update by themselves.";
      return false;
    }
    try {
      const me = await gh("/user");
      btn.textContent = `🔑 ${me.login}`;
      btn.classList.add("on");
      $("#runsNote").textContent = "";
      say($("#keyMsg"), `Signed in as ${me.login}.`, "ok");
      return true;
    } catch (e) {
      btn.textContent = "🔑 Token problem";
      btn.classList.remove("on");
      say($("#keyMsg"), explain(e, "read your account", ""), "bad");
      return false;
    }
  }
  async function saveToken(ev) {
    ev.preventDefault();
    const v = $("#keyInput").value.trim();
    if (!v) { say($("#keyMsg"), "Paste the token first.", "bad"); return; }
    const remember = $("#keyRemember").checked;
    writeKey(window.localStorage, TOKEN_KEY, "");
    writeKey(window.sessionStorage, TOKEN_KEY, "");
    writeKey(store(remember), TOKEN_KEY, v);
    token = v;
    $("#keyInput").value = "";
    say($("#keyMsg"), "Checking…");
    if (await checkToken()) {
      setTimeout(() => showKeyBox(false), 900);
      refreshAll(true);
    }
  }
  function forgetToken() {
    writeKey(window.localStorage, TOKEN_KEY, "");
    writeKey(window.sessionStorage, TOKEN_KEY, "");
    token = "";
    $("#keyInput").value = "";
    checkToken();
    say($("#keyMsg"), "Token removed from this browser.", "ok");
  }

  // ---------- the form ----------
  // "chase = text | heli = text | ..." in a description becomes a hint for the chosen option
  function optionHelp(desc, opts) {
    if (!desc || !desc.includes("|")) return null;
    const map = {};
    for (const part of desc.split("|")) {
      const m = /^\s*([\w-]+)\s*=\s*(.+?)\s*$/.exec(part);
      if (m) map[m[1]] = m[2];
    }
    return opts.every((o) => map[o]) ? map : null;
  }
  function field(inp, value) {
    const id = `f_${inp.name}`;
    const label = LABELS[inp.name] || nice(inp.name);
    let v = value !== undefined && value !== null ? String(value) : inp.default || "";
    let box;
    let hint = inp.description;
    if (inp.type === "choice") {
      const opts = inp.options || [];
      if (!opts.includes(v)) v = inp.default;
      const fancy = CHIP_EMOJI.includes(inp.name);
      if (fancy || opts.length <= 4) {
        box = el("fieldset", "field");
        const legend = el("legend", "label", label);
        box.append(legend);
        const chips = el("div", "chips");
        for (const o of opts) {
          const c = el("label", "chip");
          const r = el("input");
          r.type = "radio";
          r.name = inp.name;
          r.value = o;
          r.checked = o === v;
          const s = el("span", "", (fancy && EMOJI[o] ? EMOJI[o] + " " : "") + o);
          c.append(r, s);
          chips.append(c);
        }
        box.append(chips);
        if (fancy) box.classList.add("wide");
        const help = optionHelp(inp.description, opts);
        if (help) {
          const p = el("p", "hint", `${v}: ${help[v]}`);
          chips.addEventListener("change", (ev) => { p.textContent = `${ev.target.value}: ${help[ev.target.value]}`; });
          box.append(p);
          hint = "";
        }
      } else {
        box = el("div", "field");
        const l = el("label", "label", label);
        l.htmlFor = id;
        const sel = el("select");
        sel.id = id;
        sel.name = inp.name;
        for (const o of opts) {
          const op = el("option", "", o);
          op.value = o;
          sel.append(op);
        }
        sel.value = v;
        box.append(l, sel);
      }
    } else if (inp.type === "boolean") {
      box = el("div", "field");
      const l = el("label", "check");
      const c = el("input");
      c.type = "checkbox";
      c.name = inp.name;
      c.value = "true";
      c.checked = v === "true";
      l.append(c, document.createTextNode(" " + label));
      box.append(l);
    } else {
      box = el("div", "field");
      const l = el("label", "label", label);
      l.htmlFor = id;
      const t = inp.name === "idea" ? el("textarea") : el("input");
      if (inp.name !== "idea") t.type = "text";
      t.id = id;
      t.name = inp.name;
      t.value = v;
      t.maxLength = 300;
      if (inp.name === "seed" || inp.name === "duration") t.inputMode = "numeric";
      box.append(l, t);
      if (inp.name === "idea") box.classList.add("wide");
    }
    if (hint) box.append(el("p", "hint", hint));
    return box;
  }
  function formKey(f) { return `${FORM_KEY}.${(f || flow).key}`; }
  function savedForm(f) {
    try { return JSON.parse(readKey(window.localStorage, formKey(f)) || "{}") || {}; } catch (e) { return {}; }
  }
  function saveForm() { writeKey(window.localStorage, formKey(), JSON.stringify(formValues())); }
  function buildForm(values) {
    const main = $("#fields");
    const more = $("#moreFields");
    main.replaceChildren();
    more.replaceChildren();
    const first = MAIN[flow.key] || [];
    for (const inp of flow.inputs) {
      (first.includes(inp.name) ? main : more).append(field(inp, values[inp.name]));
    }
    more.append(field({ name: "_ref", type: "string", default: cfg.branch,
      description: `Branch the workflow runs from (usually ${cfg.branch})` }, values._ref));
  }
  function buildKinds() {
    const box = $("#kinds");
    box.replaceChildren();
    for (const w of cfg.workflows) {
      const b = el("button", "", w.label);
      b.type = "button";
      b.setAttribute("role", "tab");
      b.dataset.key = w.key;
      b.addEventListener("click", () => { if (w !== flow) selectFlow(w.key); });
      box.append(b);
    }
  }
  function selectFlow(key, values) {
    flow = cfg.workflows.find((w) => w.key === key) || cfg.workflows[0];
    writeKey(window.localStorage, KIND_KEY, flow.key);
    for (const b of $("#kinds").children) {
      const on = b.dataset.key === flow.key;
      b.classList.toggle("on", on);
      b.setAttribute("aria-selected", String(on));
    }
    buildForm(values || savedForm());
    $("#runBtn").textContent = flow.key === "chase" ? "🚓 Make chase video" : "🎬 Make story video";
    say($("#runMsg"), "");
  }
  function formValues() {
    const form = $("#runForm");
    const out = {};
    for (const inp of flow.inputs) {
      const e = form.elements[inp.name];
      if (!e) continue;
      if (inp.type === "boolean") out[inp.name] = e.checked ? "true" : "false";
      else out[inp.name] = String(e.value || "").trim();
    }
    out._ref = String(form.elements._ref.value || "").trim() || cfg.branch;
    return out;
  }
  function setValues(values) {
    const form = $("#runForm");
    for (const [k, v] of Object.entries(values)) {
      const e = form.elements[k];
      if (!e || v === undefined || v === null) continue;
      if (e.type === "checkbox") e.checked = String(v) === "true";
      else e.value = String(v);
    }
    // a chip's hint follows its choice
    for (const inp of flow.inputs) {
      const e = form.elements[inp.name];
      if (e && e instanceof RadioNodeList) {
        const r = [...e].find((x) => x.checked);
        if (r) r.dispatchEvent(new Event("change", { bubbles: true }));
      }
    }
    saveForm();
  }

  async function makeVideo(ev) {
    ev.preventDefault();
    const msg = $("#runMsg");
    if (!token) {
      showKeyBox(true, "Add a token first, then press Make video again.");
      return;
    }
    const values = formValues();
    saveForm();
    const ref = values._ref;
    const inputs = {};
    for (const inp of flow.inputs) inputs[inp.name] = values[inp.name] ?? "";
    if (inputs.seed && !/^\d*$/.test(inputs.seed)) {
      say(msg, "The city seed has to be a number (or blank).", "bad");
      return;
    }
    if ("duration" in inputs && !(/^\d+$/.test(inputs.duration) && +inputs.duration >= 15 && +inputs.duration <= 300)) {
      say(msg, "The length has to be a number of seconds between 15 and 300.", "bad");
      return;
    }
    const btn = $("#runBtn");
    btn.disabled = true;
    say(msg, "Starting…");
    try {
      let known = new Set();
      try { known = new Set((await listRuns()).map((r) => r.id)); } catch (e) { /* still start it */ }
      const res = await gh(`/repos/${cfg.repo}/actions/workflows/${flow.file}/dispatches`, {
        method: "POST", body: { ref, inputs },
      });
      pending = { known, since: Date.now() };
      if (res && res.workflow_run_id) newRunId = res.workflow_run_id;
      say(msg, "Started! A video takes about 10 to 25 minutes. Follow it under Runs; it shows up under Videos when it is done. You can start more meanwhile.", "ok");
      $("#runsCard").scrollIntoView({ behavior: "smooth", block: "start" });
      setTimeout(() => tick(), 2500);
    } catch (e) {
      say(msg, explain(e, "start runs", "Actions: Read and write"), "bad");
    } finally {
      btn.disabled = false;
    }
  }

  // ---------- runs ----------
  // the workflow that puts an earlier run's video on this page (no prefix: it makes no videos itself)
  const PUBLISH = { key: "publish", file: "publish.yml", label: "📤 Publish", prefix: "" };
  function flowOfRun(run) {
    const path = String(run.path || "").split("@")[0];
    return [...cfg.workflows, PUBLISH].find((w) => path === `.github/workflows/${w.file}`);
  }
  // a button that publishes a finished run's video (from its uploaded files) to this page
  function publishButton(run) {
    const b = el("button", "", "📤 Put on this page");
    b.type = "button";
    b.addEventListener("click", async () => {
      b.disabled = true;
      try {
        await gh(`/repos/${cfg.repo}/actions/workflows/${PUBLISH.file}/dispatches`, {
          method: "POST", body: { ref: cfg.branch, inputs: { run_id: String(run.id) } },
        });
        toast("Publishing… it shows up under Videos in about a minute");
        pending = { known: new Set([...document.querySelectorAll(".run")].map((x) => +x.dataset.id)), since: Date.now() };
        setTimeout(tick, 3000);
      } catch (e) {
        toast(explain(e, "start runs", "Actions: Read and write"));
        b.disabled = false;
      }
    });
    return b;
  }
  async function listRuns() {
    const data = await gh(`/repos/${cfg.repo}/actions/runs?per_page=40&event=workflow_dispatch`);
    return ((data && data.workflow_runs) || []).filter(flowOfRun).slice(0, 10);
  }
  function icon(run) {
    if (run.status !== "completed") return run.status === "in_progress" ? "🔄" : "⏳";
    return { success: "✅", failure: "❌", cancelled: "⚪", timed_out: "⌛", skipped: "⚪" }[run.conclusion] || "⚠️";
  }
  function runLine(run) {
    const start = Date.parse(run.run_started_at || run.created_at);
    const end = run.status === "completed" ? Date.parse(run.updated_at) : Date.now();
    const bits = [`#${run.run_number}`, ago(run.created_at)];
    if (run.status === "completed") bits.push(`took ${span((end - start) / 1000)}`);
    else bits.push(`running for ${span((end - start) / 1000)}`);
    if (run.head_branch && run.head_branch !== cfg.branch) bits.push(`branch ${run.head_branch}`);
    return bits.join(" · ");
  }
  async function jobsOf(run) {
    const data = await gh(`/repos/${cfg.repo}/actions/runs/${run.id}/jobs?filter=latest`);
    return (data && data.jobs) || [];
  }
  async function showProgress(run, body, row) {
    const detail = el("p", "detail", run.status === "queued" ? "Waiting for a GitHub machine…" : "");
    const bar = el("div", "bar");
    const fill = el("i");
    bar.append(fill);
    body.insertBefore(detail, row);
    body.insertBefore(bar, row);
    try {
      const jobs = await jobsOf(run);
      const steps = jobs.flatMap((j) => j.steps || []);
      if (!steps.length) return;
      const done = steps.filter((s) => s.status === "completed").length;
      fill.style.width = `${Math.round((100 * done) / steps.length)}%`;
      // a chase video records its takes side by side, one job each
      const job = jobs.find((j) => j.status === "in_progress") || jobs.find((j) => j.status !== "completed");
      const js = (job && job.steps) || [];
      const now = js.find((s) => s.status === "in_progress") || js.find((s) => s.status !== "completed");
      const together = jobs.filter((j) => j.status === "in_progress").length;
      if (now) {
        detail.textContent = `${STEPS[now.name] || now.name} ` +
          (together > 1 ? `(${together} takes at once)` : `(step ${Math.min(done + 1, steps.length)} of ${steps.length})`);
      } else if (job) {
        detail.textContent = "Waiting for a GitHub machine…";
      }
    } catch (e) { /* the bar stays empty */ }
  }
  async function showFailure(run, body, btn) {
    btn.disabled = true;
    const p = el("p", "detail bad", "Looking…");
    body.append(p);
    try {
      const jobs = await jobsOf(run);
      const failed = [];
      for (const j of jobs) {
        for (const s of j.steps || []) if (s.conclusion === "failure") failed.push([j, s]);
      }
      if (!failed.length) {
        p.textContent = run.conclusion === "cancelled" ? "It was cancelled." : "GitHub did not say which step failed.";
      } else {
        const [j, s] = failed[0];
        p.textContent = `Stopped at "${s.name}". `;
        p.append(link(j.html_url, "Open the log ↗"));
      }
    } catch (e) {
      p.textContent = explain(e, "read runs", "Actions: Read");
    }
  }
  function renderRun(run) {
    const li = el("li", "run");
    li.dataset.id = String(run.id);
    if (run.id === newRunId) li.classList.add("new");
    const body = el("div", "rbody");
    const fl = flowOfRun(run) || cfg.workflows[0];
    body.append(el("div", "rtitle", `${fl.label.split(" ")[0]} ${run.display_title || run.name}`), el("div", "rmeta", runLine(run)));
    const row = el("div", "row");
    const rel = releases.get(`${fl.prefix}${run.id}`);
    if (run.status !== "completed") {
      if (token) {
        const c = el("button", "", "Cancel");
        c.type = "button";
        c.addEventListener("click", async () => {
          if (!confirm(`Cancel run #${run.run_number}?`)) return;
          c.disabled = true;
          try { await gh(`/repos/${cfg.repo}/actions/runs/${run.id}/cancel`, { method: "POST" }); toast("Cancelling…"); setTimeout(tick, 3000); }
          catch (e) { toast(explain(e, "cancel runs", "Actions: Read and write")); c.disabled = false; }
        });
        row.append(c);
      }
    } else if (rel) {
      // the video is on the page (a failed run may have been published afterwards)
      const w = el("button", "primary", "▶ Watch");
      w.type = "button";
      w.addEventListener("click", () => {
        const card = document.getElementById(`v-${rel.tag_name}`);
        if (card) card.scrollIntoView({ behavior: "smooth", block: "start" });
      });
      row.append(w);
    } else if (run.conclusion === "success") {
      if (fl.prefix) {
        if (token) row.append(publishButton(run));
        row.append(link(`${run.html_url}#artifacts`, "Files on GitHub ↗", "button"));
      }
    } else {
      const why = el("button", "", "Why?");
      why.type = "button";
      why.addEventListener("click", () => showFailure(run, body, why));
      row.append(why);
      // the video may be made even when a later step failed
      if (fl.prefix && !rel && token) row.append(publishButton(run));
      if (token && fl.prefix) {
        const again = el("button", "", "Run again");
        again.type = "button";
        again.addEventListener("click", async () => {
          if (!confirm("Run it again with the same settings? (AI runs use Gemini quota again.)")) return;
          again.disabled = true;
          try { await gh(`/repos/${cfg.repo}/actions/runs/${run.id}/rerun`, { method: "POST" }); toast("Started again"); setTimeout(tick, 3000); }
          catch (e) { toast(explain(e, "re-run runs", "Actions: Read and write")); again.disabled = false; }
        });
        row.append(again);
      }
    }
    row.append(link(run.html_url, "GitHub ↗", "button"));
    body.append(row);
    li.append(el("div", "icon", icon(run)), body);
    if (run.status !== "completed") showProgress(run, body, row);
    return li;
  }
  async function refreshRuns() {
    const runs = await listRuns();
    if (pending) {
      const fresh = runs.find((r) => !pending.known.has(r.id));
      if (fresh) { newRunId = fresh.id; pending = null; }
      else if (Date.now() - pending.since > 120000) pending = null;
    }
    const ul = $("#runs");
    ul.replaceChildren();
    if (!runs.length) ul.append(el("li", "empty", "No runs yet. Make your first video above."));
    const active = new Set();
    for (const run of runs) {
      ul.append(renderRun(run));
      if (run.status !== "completed") active.add(run.id);
    }
    const finished = [...lastActive].some((id) => !active.has(id));
    lastActive = active;
    return { active: active.size > 0, finished };
  }

  // ---------- videos ----------
  function parseData(body) {
    const m = /<!--\s*studio-data\s*([\s\S]*?)-->/.exec(body || "");
    if (!m) return {};
    try { return JSON.parse(m[1]) || {}; } catch (e) { return {}; }
  }
  // which file of a release is the video, the no-music video, the thumbnail ...
  function roles(rel, d) {
    const all = rel.assets || [];
    const by = Object.fromEntries(all.map((a) => [a.name, a]));
    const f = d.files || {};
    const mp4 = all.filter((a) => a.name.endsWith(".mp4"));
    return {
      video: by[f.video] || by["story.mp4"] || mp4.find((a) => !a.name.includes("nomusic")),
      nomusic: by["story_nomusic.mp4"] || mp4.find((a) => a.name.includes("nomusic")),
      thumbnail: by[f.thumbnail] || by["thumbnail.jpg"] || all.find((a) => /\.jpe?g$/.test(a.name)),
      upload: by[f.upload] || by["upload.txt"] || all.find((a) => /upload.*\.txt$/.test(a.name)),
      screenplay: by["screenplay.json"],
    };
  }
  function kindOf(rel, d) {
    if (d.kind) return d.kind;
    const w = cfg.workflows.find((x) => rel.tag_name.startsWith(x.prefix));
    return w ? w.key : "story";
  }
  function renderVideo(rel) {
    const d = parseData(rel.body);
    const kind = kindOf(rel, d);
    const node = $("#videoTpl").content.firstElementChild.cloneNode(true);
    node.id = `v-${rel.tag_name}`;
    const files = roles(rel, d);
    const video = $("video", node);
    const main = files.video;
    const quiet = files.nomusic;
    if (files.thumbnail) video.poster = files.thumbnail.browser_download_url;
    if ((d.settings && d.settings.orientation) === "horizontal") video.classList.add("wide");
    if (main) video.src = main.browser_download_url;
    video.addEventListener("error", () => {
      const box = el("div", "fallback", "This browser can't play it here. ");
      if (main) box.append(link(main.browser_download_url, "Open the video"));
      video.replaceWith(box);
    });
    const sw = $(".switch", node);
    if (!quiet || !main) sw.hidden = true;
    sw.addEventListener("click", (ev) => {
      const b = ev.target.closest("button");
      if (!b || b.classList.contains("on")) return;
      for (const x of sw.querySelectorAll("button")) {
        x.classList.toggle("on", x === b);
        x.setAttribute("aria-pressed", String(x === b));
      }
      const t = video.currentTime;
      const playing = !video.paused;
      video.src = (b.dataset.v === "music" ? main : quiet).browser_download_url;
      video.addEventListener("loadedmetadata", () => { video.currentTime = t; if (playing) video.play().catch(() => {}); }, { once: true });
      if (playing || t > 0) video.load();
    });

    $(".vtitle", node).textContent = d.episode || rel.name || rel.tag_name;
    const meta = [];
    if (kind === "chase") {
      meta.push(d.mode_label || `${EMOJI[d.mood] || ""} ${d.mood || "chase"}`.trim());
      if (d.title) meta.push(`hook "${d.title}"`);
      if (d.seconds) meta.push(`${Math.round(d.seconds)} s`);
      meta.push(ago(rel.created_at));
      for (const [k, v] of d.stats || []) meta.push(`${k} ${v}`);
    } else {
      if (d.mood) meta.push(`${EMOJI[d.mood] || ""} ${d.mood}`.trim());
      if (d.seconds) meta.push(`${Math.round(d.seconds)} s`);
      meta.push(ago(rel.created_at));
      if (d.writer) meta.push(d.writer === "saved episode" ? "saved episode" : `written by ${d.writer}`);
    }
    $(".vmeta", node).textContent = meta.join(" · ");

    const titles = d.titles || [];
    const ol = $(".titles ol", node);
    for (const t of titles) {
      const li = el("li");
      const b = el("button", "", t);
      b.type = "button";
      b.addEventListener("click", () => copy(t, "Title"));
      li.append(b);
      ol.append(li);
    }
    $(".titles", node).hidden = !titles.length;
    const tags = (d.hashtags || []).join(" ");
    $(".dtext", node).textContent = d.description || "";
    $(".tags", node).textContent = tags;
    $(".desc", node).hidden = !d.description && !tags;
    const descText = [d.description || "", tags].filter(Boolean).join("\n\n");
    $(".copyDesc", node).hidden = !descText;
    $(".copyDesc", node).addEventListener("click", () => copy(descText, "Description"));
    const full = d.upload || rel.body || "";
    $(".copyAll", node).addEventListener("click", () => copy(full, "Upload text"));
    const ytTags = $(".copyTags", node);
    ytTags.hidden = !d.yt_tags;
    ytTags.addEventListener("click", () => copy(d.yt_tags, "YouTube tags"));

    const lines = d.lines || [];
    const ul = $(".lines ul", node);
    for (const ln of lines) {
      const li = el("li");
      li.append(el("b", "", ln.who), document.createTextNode(" "), el("em", "", `(${ln.emotion})`), document.createTextNode(` ${ln.text}`));
      ul.append(li);
    }
    $(".lines", node).hidden = !lines.length;

    const dl = $(".downloads", node);
    const shown = new Set();
    for (const [role, label] of ROLES) {
      const a = files[role];
      if (!a || shown.has(a.name)) continue;
      shown.add(a.name);
      dl.append(link(a.browser_download_url, `${label} (${mb(a.size)})`, "button"));
    }
    for (const a of rel.assets || []) {
      if (!shown.has(a.name)) dl.append(link(a.browser_download_url, `⬇ ${a.name}`, "button"));
    }

    $(".gh", node).href = rel.html_url;
    const remix = $(".remix", node);
    if (!d.settings || !Object.keys(d.settings).length) remix.hidden = true;
    remix.addEventListener("click", () => {
      if (!flow || flow.key !== kind) selectFlow(kind);
      const s = Object.assign({}, d.settings, { seed: "" });
      setValues(s);
      $("#more").open = true;
      say($("#runMsg"), `Settings copied from "${d.episode || rel.name}" (with a new city). Change anything, then press Make video.`, "ok");
      $("#newCard").scrollIntoView({ behavior: "smooth", block: "start" });
    });
    const del = $(".del", node);
    del.hidden = !token;
    del.addEventListener("click", async () => {
      if (!confirm(`Delete "${d.episode || rel.name}"? Its video files are removed from GitHub for good.`)) return;
      del.disabled = true;
      try {
        await gh(`/repos/${cfg.repo}/releases/${rel.id}`, { method: "DELETE" });
        try { await gh(`/repos/${cfg.repo}/git/refs/tags/${encodeURIComponent(rel.tag_name)}`, { method: "DELETE" }); } catch (e) { /* tag already gone */ }
        releases.delete(rel.tag_name);
        node.remove();
        toast("Deleted");
        if (!$("#videos").children.length) emptyVideos();
      } catch (e) {
        toast(explain(e, "delete videos", "Contents: Read and write"));
        del.disabled = false;
      }
    });
    return node;
  }
  function emptyVideos() {
    $("#videos").replaceChildren(el("p", "empty", "No videos here yet. Videos made from this page (or from the Actions tab) show up here when their run finishes."));
  }
  async function loadVideos(reset) {
    if (reset) {
      videosPage = 1;
      releases.clear();
    }
    const list = await gh(`/repos/${cfg.repo}/releases?per_page=${PAGE}&page=${videosPage}`);
    const box = $("#videos");
    if (reset) box.replaceChildren();
    if (box.firstElementChild && box.firstElementChild.classList.contains("empty")) box.replaceChildren();
    for (const rel of list || []) {
      const ours = cfg.workflows.some((w) => rel.tag_name.startsWith(w.prefix));
      if (!ours || rel.draft || releases.has(rel.tag_name)) continue;
      releases.set(rel.tag_name, rel);
      box.append(renderVideo(rel));
    }
    $("#moreVideos").hidden = (list || []).length < PAGE;
    videosPage += 1;
    if (!box.children.length) emptyVideos();
  }

  // ---------- refresh loop ----------
  async function refreshAll(videosToo) {
    if (busy) return;
    busy = true;
    const btn = $("#refreshBtn");
    btn.disabled = true;
    try {
      if (videosToo) {
        try { await loadVideos(true); } catch (e) { $("#videos").replaceChildren(el("p", "msg bad", explain(e, "read releases", "Contents: Read"))); }
      }
      await tick(true);
    } finally {
      btn.disabled = false;
      busy = false;
    }
  }
  async function tick(fromRefresh) {
    clearTimeout(pollTimer);
    let state = { active: false, finished: false };
    try {
      state = await refreshRuns();
    } catch (e) {
      $("#runs").replaceChildren(el("li", "empty msg bad", explain(e, "read runs", "Actions: Read")));
    }
    if (state.finished && !fromRefresh) {
      try { await loadVideos(true); await refreshRuns(); } catch (e) { /* next tick */ }
    }
    if (token && (state.active || pending) && !document.hidden) {
      pollTimer = setTimeout(() => tick(), pending ? 5000 : 15000);
    }
  }

  // ---------- start ----------
  async function start() {
    try {
      const r = await fetch("studio.json", { cache: "no-store" });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      cfg = await r.json();
    } catch (e) {
      document.querySelector("main").replaceChildren(el("p", "card msg bad", "studio.json is missing. Build the page with tools/site/build.py."));
      return;
    }
    const repoUrl = `https://github.com/${cfg.repo}`;
    $("#repoLink").href = repoUrl;
    $("#footRepo").href = `${repoUrl}/releases`;
    $("#footRepo").textContent = cfg.repo;
    $("#apkLink").href = `${repoUrl}/releases/tag/latest`;
    $("#repoName").textContent = cfg.repo;

    buildKinds();
    selectFlow(readKey(window.localStorage, KIND_KEY) || cfg.workflows[0].key);
    const form = $("#runForm");
    form.addEventListener("submit", makeVideo);
    form.addEventListener("change", saveForm);
    $("#resetBtn").addEventListener("click", () => {
      writeKey(window.localStorage, formKey(), "");
      buildForm({});
      say($("#runMsg"), "");
    });
    $("#keyBtn").addEventListener("click", () => showKeyBox($("#keyBox").hidden));
    $("#keyForm").addEventListener("submit", saveToken);
    $("#keyForget").addEventListener("click", forgetToken);
    $("#refreshBtn").addEventListener("click", () => refreshAll(true));
    $("#moreVideos").addEventListener("click", async (ev) => {
      ev.target.disabled = true;
      try { await loadVideos(false); } catch (e) { toast(explain(e, "read releases", "Contents: Read")); }
      ev.target.disabled = false;
    });
    document.addEventListener("visibilitychange", () => { if (!document.hidden && token) tick(); });

    loadToken();
    await checkToken();
    refreshAll(true);
  }
  start();
})();
