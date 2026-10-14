const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const clamp = (value, min = 0, max = 1) => Math.min(max, Math.max(min, value));
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
if (!reducedMotion) document.documentElement.classList.add("motion");

/* ---------- Header: hide on scroll down, menu, current section ---------- */
const header = $("[data-header]");
const menu = $(".nav-menu");
const closeMenu = () => {
  header.classList.remove("is-open");
  menu.setAttribute("aria-expanded", "false");
};
menu.addEventListener("click", () => {
  const open = header.classList.toggle("is-open");
  menu.setAttribute("aria-expanded", String(open));
});
$$(".mobile-nav a, .mobile-nav button").forEach((el) => el.addEventListener("click", closeMenu));
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && header.classList.contains("is-open")) {
    closeMenu();
    menu.focus();
  }
});

const navLinks = $$(".nav-links a");
const sectionObserver = new IntersectionObserver(
  (entries) =>
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      navLinks.forEach((link) => link.classList.toggle("is-current", link.hash === `#${entry.target.id}`));
    }),
  { rootMargin: "-45% 0px -50% 0px" },
);
navLinks.forEach((link) => {
  const target = $(link.hash);
  if (target) sectionObserver.observe(target);
});

/* ---------- Mascot personality: eyes follow the pointer, occasional blink ---------- */
const lookers = $$("[data-look]");
if (!reducedMotion) {
  if (matchMedia("(hover: hover) and (pointer: fine)").matches) {
    let pointer = null;
    let lookFrame = 0;
    const look = () => {
      lookFrame = 0;
      lookers.forEach((face) => {
        const rect = face.getBoundingClientRect();
        if (rect.bottom < 0 || rect.top > innerHeight) return;
        const dx = pointer.x - (rect.left + rect.width / 2);
        const dy = pointer.y - (rect.top + rect.height / 2);
        const dist = Math.hypot(dx, dy) || 1;
        const reach = Math.min(dist / 260, 1) * (rect.width / 22);
        face.style.setProperty("--lx", ((dx / dist) * reach).toFixed(2));
        face.style.setProperty("--ly", ((dy / dist) * reach).toFixed(2));
      });
    };
    addEventListener("pointermove", (event) => {
      pointer = { x: event.clientX, y: event.clientY };
      if (!lookFrame) lookFrame = requestAnimationFrame(look);
    }, { passive: true });
    document.documentElement.addEventListener("pointerleave", () =>
      lookers.forEach((face) => face.style.setProperty("--lx", 0) || face.style.setProperty("--ly", 0)),
    );
  }
  const blink = () => {
    lookers.forEach((face) => {
      const state = face.dataset.faceState;
      if (state !== "idle" && state !== "success" && state !== "listening") return;
      face.classList.add("is-blinking");
      setTimeout(() => face.classList.remove("is-blinking"), 150);
    });
    setTimeout(blink, 3200 + Math.random() * 3200);
  };
  setTimeout(blink, 2600);
}

/* ---------- Word-by-word transcript helper ---------- */
function splitWords(element, sentence) {
  element.replaceChildren(
    ...sentence.split(" ").flatMap((word, i) => {
      const span = document.createElement("span");
      span.className = "w";
      span.textContent = word;
      return i ? [document.createTextNode(" "), span] : [span];
    }),
  );
  return $$(".w", element);
}

/* Small looping timeline that pauses off-screen, on hidden tabs, or when asked. */
function createLoop({ phases, show, target, toggle, autoplay = true }) {
  let index = 0;
  let timer = 0;
  let paused = reducedMotion || !autoplay;
  let visible = false;
  const label = $("[data-toggle-label]", toggle);
  const schedule = () => {
    clearTimeout(timer);
    if (paused || !visible || document.hidden) return;
    timer = setTimeout(() => {
      index = (index + 1) % phases.length;
      show(index);
      schedule();
    }, phases[index].ms);
  };
  const setPaused = (value) => {
    paused = value;
    toggle.setAttribute("aria-pressed", String(value));
    label.textContent = value ? "Play" : "Pause";
    schedule();
  };
  toggle.addEventListener("click", () => setPaused(!paused));
  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    schedule();
  }, { threshold: 0.35 }).observe(target);
  document.addEventListener("visibilitychange", schedule);
  return {
    start(fromIndex = 0) {
      index = fromIndex;
      show(index);
      setPaused(paused);
    },
    get paused() {
      return paused;
    },
  };
}

/* ---------- Hero: Suzzme on iPhone ---------- */
const heroPhone = $("[data-hero-phone]");
const heroWords = splitWords($("[data-hero-question]"), "What does my morning look like?");
const heroFace = $("[data-hero-sheet-face]");
const heroHomeFace = $("[data-hero-face]");
const heroPhases = [
  { phase: "home", ms: 3600, face: "idle" },
  { phase: "press", ms: 380, face: "listening" },
  { phase: "listen", ms: 2700, face: "listening", state: "Listening…", detail: "Suzzme is listening" },
  { phase: "check", ms: 1500, face: "gatheringContext", state: "Checking your context…", detail: "Calendar, Reminders and a watched page" },
  { phase: "answer", ms: 2400, face: "speaking", state: "Here’s your morning", detail: "Speaking" },
  { phase: "answer", ms: 2800, face: "idle", state: "Here’s your morning", detail: "Ask a follow-up any time" },
];
let heroWordTimers = [];
const heroLoop = createLoop({
  phases: heroPhases,
  target: heroPhone,
  toggle: $("[data-hero-toggle]"),
  show(i) {
    const p = heroPhases[i];
    heroPhone.dataset.phase = p.phase;
    heroFace.dataset.faceState = p.face;
    heroHomeFace.dataset.faceState = p.phase === "home" ? "idle" : "listening";
    if (p.state) {
      $("[data-hero-state]").textContent = p.state;
      $("[data-hero-detail]").textContent = p.detail;
    }
    heroWordTimers.forEach(clearTimeout);
    heroWordTimers = [];
    if (p.phase === "listen") {
      heroWords.forEach((w) => w.classList.remove("in"));
      heroWords.forEach((w, n) => heroWordTimers.push(setTimeout(() => w.classList.add("in"), 450 + n * 280)));
    } else if (p.phase !== "home" && p.phase !== "press") {
      heroWords.forEach((w) => w.classList.add("in"));
    }
  },
});
if (reducedMotion) heroLoop.start(4);
else setTimeout(() => heroLoop.start(0), 900);

/* ---------- Mac Presence demo ---------- */
const scaler = $("[data-mac-scaler]");
const mac = $("[data-mac]");
const screen = $("[data-demo]");
const fitScreen = () => {
  const pad = parseFloat(getComputedStyle(scaler).paddingLeft) || 0;
  mac.style.setProperty("--s", ((scaler.clientWidth - pad * 2) / 1200).toFixed(4));
};
new ResizeObserver(fitScreen).observe(scaler);
fitScreen();

const demo = {
  title: $("[data-demo-title]"),
  detail: $("[data-demo-detail]"),
  face: $(".face", screen),
  event: $("[data-demo-event]"),
  confirm: $("[data-demo-confirm]"),
  steps: $$(".demo-steps li"),
};
const macWords = splitWords($("[data-demo-transcript]"), "Move my design catch-up to tomorrow at ten.");
const phases = [
  { phase: "idle", ms: 1000, face: "idle" },
  { phase: "listen", ms: 3400, step: "listen", face: "listening", title: "Listening…", detail: "Suzzme is listening" },
  { phase: "check", ms: 2000, step: "check", face: "gatheringContext", title: "Checking your context…", detail: "Using Calendar you permitted" },
  { phase: "confirm", ms: 2300, step: "confirm", face: "awaitingConfirmation", title: "Waiting for confirmation", detail: "Nothing changes until you confirm" },
  { phase: "press", ms: 450, step: "confirm", face: "awaitingConfirmation" },
  { phase: "act", ms: 1300, step: "act", face: "acting", title: "Moving the event…", detail: "Updating Calendar" },
  { phase: "verify", ms: 1400, step: "verify", face: "reasoning", title: "Checking the result…", detail: "Reading Calendar again" },
  { phase: "done", ms: 3000, step: "verify", face: "success", title: "Moved and verified", detail: "Design catch-up is tomorrow at 10:00" },
];
const stepDurations = phases.reduce((acc, p) => {
  if (p.step) acc[p.step] = (acc[p.step] || 0) + p.ms;
  return acc;
}, {});
const stepOrder = ["listen", "check", "confirm", "act", "verify"];
let macWordTimers = [];

const macLoop = createLoop({
  phases,
  target: scaler,
  toggle: $("[data-demo-toggle]"),
  show(index) {
    const p = phases[index];
    screen.dataset.phase = p.phase;
    demo.face.dataset.faceState = p.face;
    if (p.title) {
      demo.title.textContent = p.title;
      demo.detail.textContent = p.detail;
    }
    demo.confirm.classList.toggle("is-pressed", p.phase === "press");

    macWordTimers.forEach(clearTimeout);
    macWordTimers = [];
    if (p.phase === "listen") {
      macWords.forEach((w) => w.classList.remove("in"));
      macWords.forEach((w, i) => macWordTimers.push(setTimeout(() => w.classList.add("in"), 500 + i * 260)));
    } else {
      macWords.forEach((w) => w.classList.add("in"));
    }

    if (p.phase === "idle") {
      demo.event.classList.add("is-resetting");
      requestAnimationFrame(() => requestAnimationFrame(() => demo.event.classList.remove("is-resetting")));
    }

    const current = stepOrder.indexOf(p.step);
    demo.steps.forEach((li, i) => {
      const active = i === current && p.phase !== "done";
      if (active && !li.classList.contains("is-active")) li.style.setProperty("--dur", `${stepDurations[li.dataset.step]}ms`);
      li.classList.toggle("is-active", active);
      li.classList.toggle("is-done", i < current || (p.phase === "done" && i <= current));
    });
  },
});
$("[data-demo-toggle]").addEventListener("click", () => mac.classList.toggle("is-paused", macLoop.paused));
macLoop.start(reducedMotion ? 3 : 0);
mac.classList.toggle("is-paused", macLoop.paused);

/* ---------- Scroll-linked work, batched per frame ---------- */
const scrollJobs = [];
let ticking = false;
const runScrollJobs = () => {
  ticking = false;
  scrollJobs.forEach((job) => job());
};
addEventListener("scroll", () => {
  if (!ticking) {
    ticking = true;
    requestAnimationFrame(runScrollJobs);
  }
}, { passive: true });
addEventListener("resize", runScrollJobs);

let lastY = scrollY;
scrollJobs.push(() => {
  const y = scrollY;
  const goingDown = y > lastY + 4;
  const goingUp = y < lastY - 4;
  if (goingDown && y > 400 && !header.classList.contains("is-open")) header.classList.add("is-hidden");
  if (goingUp || y < 200) header.classList.remove("is-hidden");
  lastY = y;
});

if (!reducedMotion) {
  scrollJobs.push(() => {
    const rect = scaler.getBoundingClientRect();
    if (rect.top > innerHeight || rect.bottom < 0) return;
    const p = clamp((innerHeight - rect.top) / (innerHeight * 0.75));
    mac.style.setProperty("--tilt", (14 * (1 - p)).toFixed(2));
    mac.style.setProperty("--lift", p.toFixed(3));
  });
}

/* ---------- Flow: sources → understanding → outcomes ---------- */
const flow = $("[data-flow]");
const flowStages = $$("[data-flow-stage]");
const beamsIn = $$(".beams-in .beam");
const beamsOut = $$(".beams-out .beam");
const tracksIn = $$(".beams-in .beam-track");
const tracksOut = $$(".beams-out .beam-track");
const nodesIn = $$(".nodes-in > g");
const nodesOut = $$(".nodes-out > g");
const flowSvg = $("[data-flow-svg]");
const pulseLayer = $("[data-flow-pulses]");
const ns = "http://www.w3.org/2000/svg";
const pulses = [...tracksIn, ...tracksOut.slice(0, 4)].map((track) => {
  const dot = document.createElementNS(ns, "circle");
  dot.setAttribute("r", "3");
  dot.style.opacity = "0";
  pulseLayer.append(dot);
  return { track, dot, length: track.getTotalLength(), on: false };
});

let flowProgress = reducedMotion ? 1 : 0;
function renderFlow() {
  const p = flowProgress;
  const inputs = beamsIn.map((beam, i) => clamp((p - 0.04 - i * 0.035) / 0.22));
  const core = clamp((p - 0.36) / 0.22);
  const outputs = beamsOut.map((beam, i) => clamp((p - 0.66 - i * 0.03) / 0.2));
  beamsIn.forEach((beam, i) => (beam.style.strokeDashoffset = 1 - inputs[i]));
  beamsOut.forEach((beam, i) => (beam.style.strokeDashoffset = 1 - outputs[i]));
  nodesIn.forEach((node, i) => node.classList.toggle("is-lit", inputs[i] > 0.02));
  nodesOut.forEach((node, i) => node.classList.toggle("is-lit", outputs[i] > 0.96));
  flowSvg.style.setProperty("--core", core.toFixed(3));
  pulses.forEach((pulse, i) => (pulse.on = i < 4 ? inputs[i] >= 1 : outputs[i - 4] >= 1));

  const stage = p < 0.34 ? 0 : p < 0.66 ? 1 : 2;
  flowStages.forEach((li, i) => {
    li.classList.toggle("is-active", i === stage);
    li.classList.toggle("is-past", i < stage);
    const local = clamp((p - i / 3) * 3);
    li.style.setProperty("--fill", local.toFixed(3));
  });
}
renderFlow();
if (!reducedMotion) {
  scrollJobs.push(() => {
    const rect = flow.getBoundingClientRect();
    const total = flow.offsetHeight - innerHeight;
    flowProgress = clamp(-rect.top / total);
    renderFlow();
  });

  let flowVisible = false;
  let pulseFrame = 0;
  const animatePulses = (time) => {
    pulses.forEach((pulse, i) => {
      if (!pulse.on) {
        pulse.dot.style.opacity = "0";
        return;
      }
      const t = ((time / 1800) + i * 0.23) % 1;
      const point = pulse.track.getPointAtLength(t * pulse.length);
      pulse.dot.setAttribute("cx", point.x);
      pulse.dot.setAttribute("cy", point.y);
      pulse.dot.style.opacity = String(Math.sin(t * Math.PI));
    });
    if (flowVisible) pulseFrame = requestAnimationFrame(animatePulses);
  };
  new IntersectionObserver(([entry]) => {
    flowVisible = entry.isIntersecting;
    cancelAnimationFrame(pulseFrame);
    if (flowVisible) pulseFrame = requestAnimationFrame(animatePulses);
  }).observe(flow);
}

/* ---------- Request lifecycle: sticky phone ---------- */
const requestSteps = $$(".request-step");
const requestPhone = $("[data-request-phone]");
const requestFace = $(".face", requestPhone);
const requestCopy = {
  ask: ["Listening…", "Suzzme is listening", "listening"],
  understand: ["Checking context…", "Calendar access you permitted", "gatheringContext"],
  confirm: ["Waiting for confirmation", "Nothing changes until you confirm", "awaitingConfirmation"],
  verify: ["Done", "Moved and verified", "success"],
};
let currentRequest = "";
function setRequest(step) {
  if (step === currentRequest) return;
  currentRequest = step;
  requestPhone.dataset.step = step;
  const [state, detail, face] = requestCopy[step];
  $("[data-req-state]").textContent = state;
  $("[data-req-detail]").textContent = detail;
  requestFace.dataset.faceState = face;
  requestSteps.forEach((li) => li.classList.toggle("is-active", li.dataset.step === step));
}
setRequest("ask");
scrollJobs.push(() => {
  const line = innerHeight * (innerWidth <= 980 ? 0.78 : 0.58);
  let active = requestSteps[0];
  requestSteps.forEach((li) => {
    if (li.getBoundingClientRect().top < line) active = li;
  });
  setRequest(active.dataset.step);
});

/* ---------- A day on iPhone ---------- */
const day = $("[data-day]");
const dayTabs = $$(".day-switch [role=tab]");
const dayCopy = $(".day-copy");
const dayContent = {
  morning: ["8:05 am", "8:05", "Start with what matters.", "A short Daily Summary explains the day in plain language before you go looking for it."],
  midday: ["12:48 pm", "12:48", "Ask, and get an answer grounded in your day.", "Answers say where they came from. Anything that would change your data waits for your confirmation."],
  evening: ["9:30 pm", "9:30", "Keep only what helps.", "Review what Suzzme remembers, then correct or delete it. Today’s details fade when the day is over."],
};
function setDay(time, focus = false) {
  if (day.dataset.time === time) return;
  day.dataset.time = time;
  const [kicker, clock, title, body] = dayContent[time];
  $("[data-day-kicker]").textContent = kicker;
  $("[data-day-clock]").textContent = clock;
  $("[data-day-title]").textContent = title;
  $("[data-day-body]").textContent = body;
  dayTabs.forEach((tab) => {
    const selected = tab.dataset.time === time;
    tab.setAttribute("aria-selected", String(selected));
    tab.tabIndex = selected ? 0 : -1;
    if (selected && focus) tab.focus();
  });
  dayCopy.classList.remove("is-swapping");
  void dayCopy.offsetWidth;
  dayCopy.classList.add("is-swapping");
}
dayTabs.forEach((tab, i) => {
  tab.tabIndex = i === 0 ? 0 : -1;
  tab.addEventListener("click", () => setDay(tab.dataset.time));
  tab.addEventListener("keydown", (event) => {
    const dir = { ArrowRight: 1, ArrowLeft: -1 }[event.key];
    if (!dir) return;
    event.preventDefault();
    setDay(dayTabs[(i + dir + dayTabs.length) % dayTabs.length].dataset.time, true);
  });
});

/* ---------- Face states ---------- */
const states = $("[data-states]");
const stateButtons = $$(".states-list button");
const statesFace = $("[data-states-face]");
const stateCaptions = {
  listening: "Listening. Suzzme is hearing your request.",
  transcribing: "Transcribing. Your words are being turned into text.",
  understanding: "Understanding. Working out what you’re asking for.",
  gatheringContext: "Checking context. Looking only at sources you’ve permitted.",
  reasoning: "Reasoning. Putting the answer together from what it found.",
  awaitingConfirmation: "Awaiting confirmation. The face holds still until you decide.",
  acting: "Acting. Carrying out the change you confirmed.",
  speaking: "Speaking. Reading the answer back to you.",
  success: "Done. The result was checked before Suzzme said so.",
  error: "Something went wrong. Suzzme explains what happened and what you can do next.",
};
const quietStates = new Set(["awaitingConfirmation", "success", "error"]);
function setState(state, focus = false) {
  statesFace.dataset.faceState = state;
  states.dataset.active = String(!quietStates.has(state));
  states.dataset.tone = state === "error" ? "error" : state === "success" ? "success" : "";
  $("[data-states-caption]").textContent = stateCaptions[state];
  stateButtons.forEach((button) => {
    const on = button.dataset.state === state;
    button.setAttribute("aria-checked", String(on));
    button.tabIndex = on ? 0 : -1;
    if (on && focus) button.focus();
  });
}
setState("listening");
let statesTimer = 0;
let statesAuto = !reducedMotion;
const stopStatesAuto = () => {
  statesAuto = false;
  clearInterval(statesTimer);
};
stateButtons.forEach((button, i) => {
  button.addEventListener("click", () => {
    stopStatesAuto();
    setState(button.dataset.state);
  });
  button.addEventListener("keydown", (event) => {
    const dir = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key];
    if (!dir) return;
    event.preventDefault();
    stopStatesAuto();
    setState(stateButtons[(i + dir + stateButtons.length) % stateButtons.length].dataset.state, true);
  });
});
new IntersectionObserver(([entry]) => {
  clearInterval(statesTimer);
  if (!entry.isIntersecting || !statesAuto) return;
  statesTimer = setInterval(() => {
    const current = stateButtons.findIndex((b) => b.getAttribute("aria-checked") === "true");
    setState(stateButtons[(current + 1) % stateButtons.length].dataset.state);
  }, 2200);
}, { threshold: 0.4 }).observe(states);

/* ---------- Privacy: things Suzzme never does ---------- */
const never = $("[data-never]").parentElement;
$$("li", never).forEach((li, i) => {
  li.style.setProperty("--i", i);
  const span = document.createElement("span");
  span.textContent = li.textContent;
  li.replaceChildren(span);
});
new IntersectionObserver(([entry], observer) => {
  if (!entry.isIntersecting) return;
  never.classList.add("in-view");
  observer.disconnect();
}, { threshold: 0.35 }).observe(never);

/* ---------- Build: typed terminal ---------- */
const terminalCode = $("[data-terminal-code]");
const script = [
  { kind: "cmd", text: "cd Suzzme" },
  { kind: "cmd", text: "open Suzzme.xcodeproj" },
  { kind: "c", text: "# In Xcode, choose the Suzzme scheme," },
  { kind: "c", text: "# pick an iOS simulator or My Mac, then press ⌘R." },
  { kind: "ok", text: "Build Succeeded" },
];
const line = (kind, text) => {
  const frag = document.createDocumentFragment();
  if (kind === "cmd") {
    const prompt = document.createElement("span");
    prompt.className = "p";
    prompt.textContent = "~ % ";
    frag.append(prompt);
  }
  const body = document.createElement("span");
  if (kind !== "cmd") body.className = kind;
  body.textContent = text;
  frag.append(body);
  return { frag, body };
};
function renderTerminalInstantly() {
  terminalCode.replaceChildren();
  script.forEach(({ kind, text }) => {
    terminalCode.append(line(kind, text).frag, "\n");
  });
}
if (reducedMotion) {
  renderTerminalInstantly();
} else {
  new IntersectionObserver(async ([entry], observer) => {
    if (!entry.isIntersecting) return;
    observer.disconnect();
    const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    for (const { kind, text } of script) {
      const { frag, body } = line(kind, kind === "cmd" ? "" : text);
      terminalCode.append(frag);
      if (kind === "cmd") {
        for (const char of text) {
          body.textContent += char;
          await wait(45 + Math.random() * 50);
        }
        await wait(380);
      } else {
        await wait(kind === "ok" ? 700 : 220);
      }
      terminalCode.append("\n");
    }
  }, { threshold: 0.5 }).observe($("[data-terminal]"));
}

/* ---------- FAQ: one open at a time ---------- */
const faqItems = $$(".faq details");
faqItems.forEach((item) =>
  item.addEventListener("toggle", () => {
    if (item.open) faqItems.forEach((other) => other !== item && (other.open = false));
  }),
);

/* ---------- Waitlist ---------- */
const dialog = $("[data-waitlist]");
const form = $("[data-waitlist-form]");
const done = $("[data-waitlist-done]");
const message = $("[data-waitlist-message]");
const submit = $("button[type=submit]", form);
$$("[data-waitlist-open]").forEach((button) =>
  button.addEventListener("click", () => {
    form.hidden = false;
    done.hidden = true;
    message.textContent = "";
    dialog.showModal();
    $("input[type=email]", form).focus();
  }),
);
$$("[data-waitlist-close]").forEach((button) => button.addEventListener("click", () => dialog.close()));
dialog.addEventListener("click", (event) => {
  if (event.target === dialog) dialog.close();
});
form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const data = new FormData(form);
  const email = String(data.get("email") || "").trim();
  if (!/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(email)) {
    message.textContent = "Enter an email address like name@example.com.";
    $("input[type=email]", form).focus();
    return;
  }
  message.textContent = "";
  submit.disabled = true;
  submit.textContent = "Joining…";
  try {
    const response = await fetch("/api/waitlist", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email,
        platform: data.get("platform") || "not-sure",
        website: data.get("website") || "",
      }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(response.status === 404 ? "unavailable" : body.error || "unavailable");
    }
    form.hidden = true;
    done.hidden = false;
    form.reset();
  } catch (error) {
    message.textContent =
      error.message === "unavailable" || error instanceof TypeError
        ? "The waitlist isn’t available on this copy of the site yet. Try again later."
        : error.message;
  } finally {
    submit.disabled = false;
    submit.textContent = "Join the waitlist";
  }
});

runScrollJobs();
