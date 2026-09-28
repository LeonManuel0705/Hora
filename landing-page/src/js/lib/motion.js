export const reducedMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

export function reveals(root) {
  const items = [...root.querySelectorAll("[data-reveal]")];
  if (!items.length) return () => {};
  if (reducedMotion() || !("IntersectionObserver" in window)) {
    items.forEach((el) => el.classList.add("is-in"));
    return () => {};
  }
  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("is-in");
      io.unobserve(entry.target);
    }
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
  items.forEach((el) => io.observe(el));
  return () => io.disconnect();
}

export function whenVisible(el, fn, rootMargin = "0px") {
  if (!("IntersectionObserver" in window)) {
    fn();
    return () => {};
  }
  const io = new IntersectionObserver((entries) => {
    if (entries.some((entry) => entry.isIntersecting)) {
      io.disconnect();
      fn();
    }
  }, { rootMargin });
  io.observe(el);
  return () => io.disconnect();
}

export function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
