/* Shared prototype motion. Visual transitions never postpone state changes. */
window.HarukaMotion = ({ s, root }) => {
  const preference = matchMedia("(prefers-reduced-motion: reduce)");
  const reduced = () => s.reduceMotion || preference.matches;
  let identity = "",
    previous,
    ghost,
    lastRoute,
    exitStyles;
  const running = new Set();
  const seenResults = new Set();
  let savedCards = new Set();
  const pendingSaves = new Set();
  function animate(element, frames, duration = 240, delay = 0) {
    if (reduced() || !element?.animate) return;
    const effect = element.animate(frames, {
      duration,
      delay,
      fill: "backwards",
      easing: "cubic-bezier(.2,.75,.25,1)",
    });
    running.add(effect);
    effect.finished.then(
      () => running.delete(effect),
      () => running.delete(effect),
    );
    return effect;
  }
  const modalIdentity = () =>
    s.modal
      ? `${s.route}:${s.modal}:${s.modal === "selectionQuery" ? s.selectionMessage?.id : ""}`
      : "";
  function beforeRender() {
    ghost?.remove();
    ghost = null;
    previous = null;
    const dialog = root.querySelector('[role="dialog"]');
    if (
      dialog &&
      s.signedIn &&
      s.route === lastRoute &&
      identity !== modalIdentity() &&
      !reduced()
    ) {
      const rect = dialog.getBoundingClientRect();
      const copy = dialog.cloneNode(true);
      copy
        .querySelectorAll(".text-selection-toolbar,.selection-player")
        .forEach((el) => el.remove());
      copy.querySelectorAll("[id]").forEach((el) => el.removeAttribute("id"));
      copy.removeAttribute("id");
      copy.removeAttribute("role");
      copy.removeAttribute("aria-modal");
      copy.inert = true;
      copy.setAttribute("aria-hidden", "true");
      Object.assign(copy.style, {
        position: "fixed",
        margin: "0",
        left: `${rect.left}px`,
        top: `${rect.top}px`,
        width: `${rect.width}px`,
        height: `${rect.height}px`,
        maxHeight: "none",
        boxSizing: "border-box",
        overflow: "hidden",
      });
      previous = {
        copy,
        scroll: dialog.scrollTop,
        backdrop: getComputedStyle(dialog.parentElement).backgroundColor,
      };
    }
  }
  function afterRender() {
    const next = modalIdentity();
    if (next !== identity) {
      if (previous) {
        ghost = document.createElement("div");
        ghost.className = "prototype-motion-exit";
        ghost.inert = true;
        ghost.setAttribute("aria-hidden", "true");
        Object.assign(ghost.style, {
          position: "fixed",
          inset: "0",
          pointerEvents: "none",
          zIndex: "49",
          background: next ? "transparent" : previous.backdrop,
        });
        // Keep the noninteractive exit image outside application/locator queries.
        // Shadow-scoped styles preserve the existing layout without duplicate IDs.
        const shadow = ghost.attachShadow({ mode: "closed" });
        const style = document.createElement("style");
        exitStyles ??= [...document.styleSheets]
          .map((sheet) => {
            try {
              return [...sheet.cssRules].map((rule) => rule.cssText).join("\n");
            } catch {
              return "";
            }
          })
          .join("\n");
        style.textContent = exitStyles;
        const surface = document.createElement("div");
        surface.id = root.id;
        surface.append(previous.copy);
        shadow.append(style, surface);
        document.body.append(ghost);
        previous.copy.scrollTop = previous.scroll;
        const leaving = ghost;
        const effect = animate(ghost, [{ opacity: 1 }, { opacity: 0 }], 150);
        animate(
          previous.copy,
          [{ transform: "translateY(0)" }, { transform: "translateY(10px)" }],
          150,
        );
        if (effect)
          effect.finished.then(
            () => leaving.remove(),
            () => leaving.remove(),
          );
        else leaving.remove();
      }
      const dialog = root.querySelector('[role="dialog"]');
      if (dialog) {
        animate(dialog.parentElement, [{ opacity: 0 }, { opacity: 1 }], 180);
        const compact = root.id === "phone-app" || innerWidth < 900;
        animate(dialog, [
          {
            transform: compact
              ? "translateY(22px)"
              : "translateY(10px) scale(.975)",
            opacity: 0.35,
          },
          { transform: "translateY(0) scale(1)", opacity: 1 },
        ]);
      }
    }
    identity = next;
    lastRoute = s.route;
    previous = null;
    resultCards();
    if (reduced()) cancel();
  }
  function resultCards() {
    if (!s.signedIn) {
      seenResults.clear();
      savedCards.clear();
      pendingSaves.clear();
      return;
    }
    const saved = new Set(
      s.words.filter((word) => word.cardId).map((word) => word.cardId),
    );
    saved.forEach((id) => {
      if (!savedCards.has(id)) pendingSaves.add(id);
    });
    savedCards = saved;
    const confirmed = new Set();
    root.querySelectorAll(".learning-card[data-result-id]").forEach((card) => {
      const surface = card.closest('[role="dialog"],[data-reader-panel-body]');
      // Do not animate results hidden behind a collection/other modal.
      if (s.modal && s.modal !== "selectionQuery") return;
      if (s.modal && !surface) return;
      const identity = `${surface ? "selection" : "query"}:${card.dataset.resultId}:${card.dataset.cardId}`;
      if (!seenResults.has(identity)) {
        seenResults.add(identity);
        // The surrounding dialog/panel already moves; only fade its card.
        animate(
          card,
          [
            {
              opacity: 0,
              transform: surface ? "none" : "translateY(18px) scale(.986)",
            },
            {
              opacity: 1,
              transform: surface ? "none" : "translateY(0) scale(1)",
            },
          ],
          surface ? 180 : 320,
        );
        if (!surface) {
          animate(
            card.querySelector(".learning-card-content"),
            [
              { opacity: 0, transform: "translateY(6px)" },
              { opacity: 1, transform: "translateY(0)" },
            ],
            240,
            60,
          );
          animate(
            card.querySelector(".learning-card-footer"),
            [{ opacity: 0 }, { opacity: 1 }],
            200,
            120,
          );
        }
      }
      if (pendingSaves.has(card.dataset.cardId)) {
        const button = card.querySelector(".card-save:disabled");
        if (button) {
          animate(
            button,
            [
              { transform: "scale(.96)" },
              { transform: "scale(1.025)", offset: 0.55 },
              { transform: "scale(1)" },
            ],
            280,
          );
          animate(
            button.querySelector("svg"),
            [
              { opacity: 0.4, transform: "scale(.6)" },
              { opacity: 1, transform: "scale(1.18)", offset: 0.6 },
              { opacity: 1, transform: "scale(1)" },
            ],
            300,
          );
          confirmed.add(card.dataset.cardId);
        }
      }
    });
    confirmed.forEach((id) => pendingSaves.delete(id));
  }
  root.addEventListener(
    "toggle",
    (event) => {
      const details = event.target;
      if (!details.matches(".query-context-detail") || !details.open) return;
      details.querySelectorAll(":scope > :not(summary)").forEach((part) => {
        animate(part, [{ opacity: 0 }, { opacity: 1 }], 180);
      });
    },
    true,
  );
  function sentence(element) {
    animate(element, [
      { opacity: 0, transform: "translateY(8px) scale(.98)" },
      { opacity: 1, transform: "translateY(0) scale(1)" },
    ]);
    element.querySelectorAll(".word-bubble").forEach((word, index) =>
      animate(
        word,
        [
          { opacity: 0, transform: "translateY(4px)" },
          { opacity: 1, transform: "translateY(0)" },
        ],
        160,
        Math.min(index, 5) * 18,
      ),
    );
  }
  function cancel() {
    running.forEach((effect) => effect.cancel());
    running.clear();
    ghost?.remove();
    ghost = null;
  }
  preference.addEventListener("change", () => {
    if (reduced()) cancel();
  });
  window.addEventListener("pagehide", cancel);
  return { beforeRender, afterRender, sentence };
};
