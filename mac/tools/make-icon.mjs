// Emits the app icon as SVG, built from the same blobatar the product renders
// faces with — so the Dock icon is what `<AgentBlob name="Sentrel" />` draws.
//
//   node make-icon.mjs <out.svg> [--source=logo.svg]
//   node make-icon.mjs <out.svg> [--seed=] [--expression=] [--background=]
//                                 [--hue=] [--tone=]
//
// `--source` takes a hand-authored SVG and only fits it to the icon canvas —
// no palette or shading is imposed on artwork someone already designed.
//
// `background` defaults to `none`: a free-form silhouette on transparency, which
// is what the blobatar is designed to read as (see components/agent-blob.tsx).
// Losing the tile also loses the contrast it provided, so the flat body fill is
// promoted to a gradient and given a highlight — depth the tile used to supply.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const pkg = resolve(here, "../../backend/node_modules/blobatar/dist");

const argv = process.argv.slice(2);
const out = argv.find((a) => !a.startsWith("--"));
const flag = (name, fallback) => {
  const hit = argv.find((a) => a.startsWith(`--${name}=`));
  return hit === undefined ? fallback : hit.slice(name.length + 3);
};
if (!out) {
  console.error("usage: make-icon.mjs <out.svg> [--seed=] [--expression=] [--background=] [--hue=] [--tone=]");
  process.exit(2);
}

const seed = flag("seed", "Sentrel");
const expressionName = flag("expression", "happy");
const background = flag("background", "none");
// Empty means "let the seed decide", which is the blobatar default.
const source = flag("source", "");
const hue = flag("hue", "");
const tone = flag("tone", "");


/** Bounding box of a path whose commands emit absolute x/y pairs (M/C). */
function pathBox(d) {
  const nums = d.match(/-?\d+(?:\.\d+)?/g).map(Number);
  const xs = nums.filter((_, i) => i % 2 === 0);
  const ys = nums.filter((_, i) => i % 2 === 1);
  return { x0: Math.min(...xs), x1: Math.max(...xs), y0: Math.min(...ys), y1: Math.max(...ys) };
}

/** Centres artwork on the 100×100 icon canvas at `target` units across. */
function fit(box, target, shiftY = 0) {
  const scale = target / Math.max(box.x1 - box.x0, box.y1 - box.y0);
  return {
    scale,
    tx: 50 - scale * ((box.x0 + box.x1) / 2),
    ty: 49 - scale * ((box.y0 + box.y1) / 2 + shiftY),
  };
}

const wrap = (inner) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="1024" height="1024">${inner}</svg>`;

// --- hand-authored source: fit only, change nothing else --------------------
if (source) {
  const raw = readFileSync(source, "utf8");
  const body = raw.match(/<path[^>]*\sd="([^"]+)"/);
  if (!body) {
    console.error(`no <path> found in ${source}`);
    process.exit(1);
  }
  const { scale, tx, ty } = fit(pathBox(body[1]), 86);
  const inner = raw.replace(/^[\s\S]*?<svg[^>]*>/, "").replace(/<\/svg>\s*$/, "");
  writeFileSync(out, wrap(`<g transform="translate(${tx.toFixed(3)} ${ty.toFixed(3)}) scale(${scale.toFixed(5)})">${inner}</g>`));
  console.log(`${source} (fitted)`);
  process.exit(0);
}

const { blobatar } = await import(`${pkg}/index.js`);
const expressions = await import(`${pkg}/expression.js`);

const expression = expressions[expressionName];
if (!expression) {
  const available = Object.keys(expressions).filter((k) => k !== "heatTint").join(", ");
  console.error(`unknown expression "${expressionName}" — available: ${available}`);
  process.exit(2);
}

const svg = blobatar(seed, {
  background: background === "none" ? false : background,
  expression,
  title: seed,
  // `hue` locks the colour so the seed drives shape only; `tone` picks which
  // swatch of that hue. The vivid swatches sit around tone 0.9.
  ...(hue === "" ? {} : { hue: Number(hue) }),
  ...(tone === "" ? {} : { tone: Number(tone) }),
});

// --- colour helpers -------------------------------------------------------
const toRgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
const toHex = (rgb) =>
  "#" + rgb.map((v) => Math.round(Math.min(255, Math.max(0, v))).toString(16).padStart(2, "0")).join("");
const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);

// --- pull the body out of the generated markup ----------------------------
const inner = svg.replace(/^<svg[^>]*>/, "").replace(/<\/svg>$/, "");

// The body is the first single-path fill group; the eyes follow as a two-path group.
const body = inner.match(/<g fill="(#[0-9a-f]{6})"><path d="([^"]+)"\/><\/g>/i);
if (!body) {
  console.error("could not find the blobatar body path — markup shape changed?");
  process.exit(1);
}
const [bodyGroup, bodyColor, bodyPath] = body;

// Bounding box: every command in the path emits absolute x/y pairs, so the
// numbers alternate and min/max over them is the box.
const box = pathBox(bodyPath);
const cx = (box.x0 + box.x1) / 2;
const cy = (box.y0 + box.y1) / 2;

// Expressions shift the whole face; that offset has to be folded into the fit.
const shift = inner.match(/<g transform="translate\(([-\d.]+) ([-\d.]+)\)"/);
const shiftY = shift ? Number(shift[2]) : 0;

// --- fit the silhouette to the canvas -------------------------------------
// With no tile there is no 824-in-1024 grid to respect, so the body itself
// takes the space a tile would have, minus room for the shadow to fall.
const { scale, tx, ty } = fit(box, background === "none" ? 86 : 76, shiftY);

const uid = `i${Math.abs([...`${seed}${expressionName}${hue}${tone}`].reduce((h, c) => (h * 31 + c.charCodeAt(0)) | 0, 7)).toString(36)}`;

const rgb = toRgb(bodyColor);
const light = toHex(mix(rgb, [255, 255, 255], 0.34));
const deep = toHex(mix(rgb, [0, 0, 0], 0.18));

const w = box.x1 - box.x0;
const h = box.y1 - box.y0;

// A highlight up and to the left, and a shade hugging the opposite edge: one
// light source, which is what makes a flat fill read as a solid.
const gloss = `<ellipse cx="${(cx - w * 0.14).toFixed(2)}" cy="${(box.y0 + h * 0.22).toFixed(2)}" `
  + `rx="${(w * 0.34).toFixed(2)}" ry="${(h * 0.26).toFixed(2)}" `
  + `fill="url(#${uid}-gloss)" clip-path="url(#${uid}-body-clip)"/>`
  + `<ellipse cx="${(cx + w * 0.16).toFixed(2)}" cy="${(box.y1 - h * 0.06).toFixed(2)}" `
  + `rx="${(w * 0.52).toFixed(2)}" ry="${(h * 0.34).toFixed(2)}" `
  + `fill="url(#${uid}-shade)" clip-path="url(#${uid}-body-clip)"/>`;

const shaded = inner.replace(
  bodyGroup,
  `<g fill="url(#${uid}-body)"><path d="${bodyPath}"/></g>${gloss}`,
);

writeFileSync(
  out,
  wrap(
    `<defs>`
    + `<linearGradient id="${uid}-body" x1="0.15" y1="0" x2="0.85" y2="1">`
    + `<stop offset="0" stop-color="${light}"/><stop offset="1" stop-color="${deep}"/>`
    + `</linearGradient>`
    + `<radialGradient id="${uid}-gloss">`
    + `<stop offset="0" stop-color="#fff" stop-opacity="0.38"/>`
    + `<stop offset="1" stop-color="#fff" stop-opacity="0"/>`
    + `</radialGradient>`
    + `<radialGradient id="${uid}-shade">`
    + `<stop offset="0" stop-color="${deep}" stop-opacity="0.45"/>`
    + `<stop offset="1" stop-color="${deep}" stop-opacity="0"/>`
    + `</radialGradient>`
    + `<clipPath id="${uid}-body-clip"><path d="${bodyPath}"/></clipPath>`
    + `</defs>`
      + `<g transform="translate(${tx.toFixed(3)} ${ty.toFixed(3)}) scale(${scale.toFixed(5)})">${shaded}</g>`,
  ),
);
console.log(`${seed} / ${expressionName} / ${background === "none" ? "transparent" : background} / ${bodyColor}`);
