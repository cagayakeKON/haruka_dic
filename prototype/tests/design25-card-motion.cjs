/* Render lifecycle regression; no browser, provider or production state. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");
const source = fs.readFileSync(path.join(__dirname, "../motion.js"), "utf8");

function fixture() {
  const records = [],
    listeners = {};
  const state = {
    signedIn: true,
    route: "query",
    words: [],
    modal: "",
    reduceMotion: false,
  };
  const preference = {
    matches: false,
    addEventListener: (_, fn) => {
      preference.change = fn;
    },
  };
  const element = (name) => ({
    animate(frames, options) {
      const record = { name, frames, options, cancelled: false };
      records.push(record);
      return {
        finished: new Promise(() => {}),
        cancel() {
          record.cancelled = true;
        },
      };
    },
  });
  const root = {
    cards: [],
    querySelector: () => null,
    querySelectorAll: () => root.cards,
    addEventListener: (type, fn) => {
      listeners[type] = fn;
    },
  };
  const window = { addEventListener() {} };
  vm.runInNewContext(source, { window, matchMedia: () => preference });
  const motion = window.HarukaMotion({ s: state, root });
  function card(resultId, cardId = resultId, surface = false) {
    const content = element(`${resultId}:content`),
      footer = element(`${resultId}:footer`);
    const icon = element(`${resultId}:check`),
      button = element(`${resultId}:save`);
    button.querySelector = () => icon;
    return {
      ...element(resultId),
      dataset: { resultId, cardId },
      closest: () => surface,
      querySelector(selector) {
        if (selector === ".learning-card-content") return content;
        if (selector === ".learning-card-footer") return footer;
        return state.words.some((w) => w.cardId === cardId) ? button : null;
      },
    };
  }
  return { state, root, motion, records, preference, listeners, card, element };
}
const f = fixture();
const render = () => {
  f.motion.beforeRender();
  f.motion.afterRender();
};
f.root.cards = [f.card("first", "shared")];
render();
assert.equal(f.records.filter((x) => x.name === "first").length, 1);
// Replacing the whole DOM for unrelated state must not restart the entrance.
f.root.cards = [f.card("first", "shared")];
const unchanged = f.records.length;
render();
assert.equal(f.records.length, unchanged);
// A cache hit creates another query occurrence while sharing the same card.
f.root.cards.push(f.card("second", "shared"));
render();
assert.equal(f.records.filter((x) => x.name === "first").length, 1);
assert.equal(f.records.filter((x) => x.name === "second").length, 1);
// Cancelling classification is not a successful save.
f.state.modal = "saveCard";
render();
f.state.modal = "";
render();
assert.equal(f.records.filter((x) => x.name.endsWith(":save")).length, 0);
// A successful save behind the modal is acknowledged once when results return.
f.state.modal = "saveCard";
f.state.words.push({ cardId: "shared" });
render();
assert.equal(f.records.filter((x) => x.name.endsWith(":save")).length, 0);
f.state.modal = "";
render();
assert.equal(f.records.filter((x) => x.name.endsWith(":save")).length, 2);
const confirmed = f.records.length;
render();
assert.equal(f.records.length, confirmed);
// Embedded results fade without duplicating their containing panel's movement.
f.state.route = "novel";
f.state.modal = "selectionQuery";
f.root.cards = [f.card("panel", "panel", true)];
render();
assert.equal(
  f.records.find((x) => x.name === "panel").frames[0].transform,
  "none",
);
// Novel next-sentence replaces the card within the same message.
f.root.cards = [f.card("panel", "next-sentence", true)];
render();
assert.equal(f.records.filter((x) => x.name === "panel").length, 2);
render();
assert.equal(f.records.filter((x) => x.name === "panel").length, 2);
// Both motion preferences suppress motion and cancel active effects.
for (const setting of ["app", "system"]) {
  const g = fixture();
  g.root.cards = [g.card("before")];
  g.motion.afterRender();
  if (setting === "app") g.state.reduceMotion = true;
  else {
    g.preference.matches = true;
    g.preference.change();
  }
  g.root.cards.push(g.card("after"));
  g.state.words.push({ cardId: "after" });
  const count = g.records.length;
  g.motion.afterRender();
  assert.equal(g.records.length, count);
  assert.ok(g.records.every((x) => x.cancelled));
}
// Account exit drops result identity and pending save feedback.
f.state.signedIn = false;
f.state.modal = "";
render();
f.state.signedIn = true;
f.state.words = [];
f.root.cards = [f.card("first")];
render();
assert.equal(f.records.filter((x) => x.name === "first").length, 2);
// Expanding context affects just its content and never changes query state.
const detailPart = f.element("context");
const detail = {
  matches: () => true,
  open: false,
  querySelectorAll: () => [detailPart],
};
const beforeDetail = f.records.length;
f.listeners.toggle({ target: detail });
assert.equal(f.records.length, beforeDetail);
detail.open = true;
f.listeners.toggle({ target: detail });
assert.equal(f.records.at(-1).name, "context");
console.log(
  "PASS: card entrances, cache reuse, rerender, save/cancel, panels, reduced motion, account reset and context disclosure",
);
