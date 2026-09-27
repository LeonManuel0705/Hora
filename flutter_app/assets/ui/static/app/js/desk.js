import { animates, travels, token } from "./motion.js";
import { flags } from "./core.js";

const NS = "http://www.w3.org/2000/svg";

const SKY = {
  dawn: { top: "#F1D2AE", bottom: "#F9ECDD", hill: "#D6B690", sun: "#EDBF7E" },
  day: { top: "#D5E0C8", bottom: "#F5F2E8", hill: "#B3C19F", sun: "#EDC98E" },
  dusk: { top: "#E0A083", bottom: "#F3D3B6", hill: "#C28A6C", sun: "#F0A873" },
  night: { top: "#1F2B21", bottom: "#314330", hill: "#263227", sun: "#F3EFE3" },
};

const BOOKS = [
  { x: 20, w: 98, h: 17, fill: "f-salbei", band: "f-salbei-d" },
  { x: 27, w: 88, h: 14, fill: "f-terra", band: "f-terra-d" },
  { x: 18, w: 94, h: 16, fill: "f-tanne2", band: "f-tanne" },
  { x: 30, w: 80, h: 13, fill: "f-sand3", band: "f-sand4" },
];

function windowPart(time) {
  const sky = SKY[time];
  let view;
  if (time === "night") {
    const stars = [[62, 42], [90, 62], [104, 36], [150, 68], [186, 38], [196, 86], [70, 88]]
      .map(([x, y], i) => `<circle class="sc-star" style="--i:${i}" cx="${x}" cy="${y}" r="${i % 3 ? 1.4 : 1.9}" fill="#F8F6EE"/>`)
      .join("");
    view = `${stars}<circle cx="164" cy="54" r="13" fill="${sky.sun}"/><circle cx="159" cy="50" r="2.6" fill="#E2DCCB"/><circle cx="168" cy="59" r="1.9" fill="#E2DCCB"/>`;
  } else {
    const [cx, cy, r] = time === "day" ? [170, 52, 15] : time === "dawn" ? [84, 100, 17] : [166, 100, 18];
    view = `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${sky.sun}"/>
      <g class="sc-cloud"><g opacity=".9"><rect x="58" y="54" width="46" height="13" rx="6.5" fill="#FFFFFF"/><circle cx="77" cy="54" r="9.5" fill="#FFFFFF"/><circle cx="91" cy="57" r="6.5" fill="#FFFFFF"/></g></g>
      <g class="sc-cloud is-slow"><g opacity=".72"><rect x="128" y="82" width="40" height="11" rx="5.5" fill="#FFFFFF"/><circle cx="144" cy="82" r="7.5" fill="#FFFFFF"/></g></g>`;
  }
  return `<g transform="translate(88 0)"><defs>
      <linearGradient id="scSky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${sky.top}"/><stop offset="1" stop-color="${sky.bottom}"/></linearGradient>
      <clipPath id="scGlass"><rect x="46" y="26" width="156" height="108" rx="16"/></clipPath>
    </defs>
    <rect x="36" y="16" width="176" height="128" rx="24" class="f-kreide s-edge"/>
    <g clip-path="url(#scGlass)">
      <rect x="46" y="26" width="156" height="108" fill="url(#scSky)"/>
      ${view}
      <path d="M46 118 C 74 102 100 104 124 112 C 150 121 176 102 202 108 V 134 H 46 Z" fill="${sky.hill}"/>
    </g>
    <rect x="121" y="26" width="6" height="108" class="f-kreide"/>
    <rect x="46" y="77" width="156" height="6" class="f-kreide"/>
    <rect x="26" y="140" width="196" height="11" rx="5.5" class="f-sill"/></g>`;
}

function clockPart(minute) {
  const hour = ((minute / 60) % 12) * 30;
  const min = (minute % 60) * 6;
  const ticks = [0, 90, 180, 270].map((angle) => `<rect x="260.5" y="37" width="3" height="5" rx="1.5" class="f-sand3" transform="rotate(${angle} 262 58)"/>`).join("");
  return `<g transform="translate(90 -4)"><circle cx="262" cy="58" r="27" class="f-tanne"/>
    <circle cx="262" cy="58" r="22" class="f-kreide"/>
    ${ticks}
    <rect x="260.25" y="45" width="3.5" height="15" rx="1.75" class="f-tanne" transform="rotate(${hour.toFixed(1)} 262 58)"/>
    <rect x="261" y="39" width="2" height="21" rx="1" class="f-terra" transform="rotate(${min} 262 58)"/>
    <circle cx="262" cy="58" r="2.6" class="f-tanne"/></g>`;
}

function notesPart(count) {
  const notes = [
    { x: 300, y: 22, turn: -6, fill: "f-gold" },
    { x: 340, y: 36, turn: 5, fill: "f-terra-l" },
    { x: 310, y: 66, turn: 3, fill: "f-sand" },
  ];
  return notes.slice(0, count).map((note, index) => `<g transform="translate(86 -2) rotate(${note.turn} ${note.x + 16} ${note.y})">
      <g class="sc-note${index === 1 ? " is-flutter" : ""}">
        <rect x="${note.x}" y="${note.y}" width="32" height="32" rx="5" class="${note.fill}"/>
        <rect x="${note.x + 7}" y="${note.y + 11}" width="18" height="3" rx="1.5" class="f-scribble"/>
        <rect x="${note.x + 7}" y="${note.y + 18}" width="12" height="3" rx="1.5" class="f-scribble"/>
      </g>
    </g>`).join("");
}

function deskPart() {
  return `<rect x="34" y="240" width="14" height="96" rx="7" class="f-tanne"/>
    <rect x="432" y="240" width="14" height="96" rx="7" class="f-tanne"/>
    <rect x="10" y="230" width="460" height="17" rx="8.5" class="f-desk-edge"/>
    <rect x="10" y="230" width="460" height="9" rx="4.5" class="f-desk"/>`;
}

function lampPart(on) {
  return `${on ? `<path class="sc-glow f-light" d="M62 126 L96 114 L176 230 L30 230 Z"/>` : ""}
    <ellipse cx="62" cy="229" rx="24" ry="6" class="f-tanne"/>
    <path d="M62 226 L80 172 L60 124" class="s-tanne" stroke-width="6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
    <circle cx="80" cy="172" r="5" class="f-tanne2"/>
    <path d="M44 116 L82 100 L96 122 Q 78 138 54 134 Z" class="f-tanne"/>
    ${on ? `<circle cx="76" cy="128" r="5" class="f-gold"/>` : ""}`;
}

function papersPart() {
  return `<rect x="12" y="224" width="72" height="6" rx="2" class="f-kreide s-edge" transform="rotate(-3 48 227)"/>
    <rect x="62" y="225" width="66" height="5" rx="2" class="f-kreide s-edge" transform="rotate(2.5 95 227)"/>`;
}

function bookPart(index) {
  const below = BOOKS.slice(0, index).reduce((sum, book) => sum + book.h, 0);
  const book = BOOKS[index];
  const y = 230 - below - book.h;
  return `<rect x="${book.x}" y="${y}" width="${book.w}" height="${book.h}" rx="4" class="${book.fill}"/>
    <rect x="${book.x + book.w - 11}" y="${y + 3}" width="8" height="${book.h - 6}" rx="2" class="f-kreide"/>
    <rect x="${book.x + 13}" y="${y}" width="6" height="${book.h}" class="${book.band}"/>`;
}

function screenSlides() {
  return `<rect x="165" y="153" width="100" height="9" rx="3" fill="#C96F4F"/>
    <rect x="165" y="168" width="44" height="38" rx="4" fill="#A3B38F"/>
    <rect x="215" y="171" width="50" height="4" rx="2" fill="#CDB999"/>
    <rect x="215" y="181" width="42" height="4" rx="2" fill="#CDB999"/>
    <rect x="215" y="191" width="46" height="4" rx="2" fill="#CDB999"/>`;
}

const SCREEN = {
  slides: `<i class="ss-swap"></i><i class="ss-bar"></i>`,
  text: `<i class="ss-line is-1"></i><i class="ss-line is-2"></i><i class="ss-line is-3"></i><i class="ss-line is-4"></i><i class="ss-cursor"></i>`,
  call: `<i class="ss-tile is-a"><b></b></i><i class="ss-tile is-b"><b></b></i><i class="ss-tile is-c"><b></b></i><i class="ss-tile is-d"><b></b></i><i class="ss-speaker"></i><i class="ss-live"></i>`,
  closed: "",
};

function laptopPart(mode) {
  if (mode === "closed") {
    return `<rect x="146" y="219" width="138" height="12" rx="6" class="f-tanne2"/>
      <rect x="152" y="214" width="126" height="7" rx="3.5" class="f-tanne"/>`;
  }
  return `<g class="sc-lid">
      <rect x="152" y="140" width="126" height="84" rx="10" class="f-tanne"/>
      <rect x="159" y="147" width="112" height="70" rx="5" class="f-screen"/>
      ${mode === "slides" ? screenSlides() : ""}
    </g>
    <rect x="138" y="222" width="154" height="9" rx="4.5" class="f-tanne2"/>
    <rect x="198" y="222" width="34" height="3" rx="1.5" class="f-tanne"/>`;
}

function mugPart() {
  return `<path class="sc-wisp" d="M309 194 q -5 -7 0 -14 t 0 -14"/>
    <path class="sc-wisp is-late" d="M318 194 q 5 -7 0 -14 t 0 -14"/>
    <path class="sc-wisp is-later" d="M314 188 q -4 -6 0 -12 t 0 -12"/>
    <path d="M326 208 h6 a7 7 0 0 1 0 14 h-6" class="s-terra" stroke-width="5" fill="none"/>
    <rect x="300" y="200" width="28" height="30" rx="8" class="f-terra"/>
    <rect x="304" y="207" width="20" height="4" rx="2" class="f-terra-d"/>`;
}

function plantPart() {
  return `<path class="sc-leaf f-salbei" d="M428 192 C 404 178 398 152 408 134 C 424 150 432 172 428 192 Z"/>
    <path class="sc-leaf is-late f-tanne2" d="M431 192 C 446 172 464 164 476 170 C 468 188 450 198 431 192 Z"/>
    <path class="sc-leaf is-later f-salbei-l" d="M429 192 C 420 168 426 142 440 126 C 449 146 443 172 429 192 Z"/>
    <path d="M410 190 H450 L446 226 Q 445 230 441 230 H419 Q 415 230 414 226 Z" class="f-terra"/>
    <rect x="406" y="185" width="48" height="10" rx="5" class="f-terra-d"/>`;
}

function flowerPart() {
  const petals = [0, 72, 144, 216, 288].map((angle) => `<circle cx="440" cy="115" r="5.5" class="f-gold" transform="rotate(${angle} 440 122)"/>`).join("");
  return `${petals}<circle cx="440" cy="122" r="4.5" class="f-terra"/>`;
}

export function sceneParts(model) {
  const parts = [["window", "fade", windowPart(model.time)], ["clock", "fade", clockPart(model.minute)]];
  if (model.notes) parts.push(["notes", "drop", notesPart(model.notes)]);
  parts.push(["desk", "fade", deskPart()]);
  if (model.lamp) parts.push(["lamp", "rise", lampPart(model.lampOn)]);
  if (model.papers) parts.push(["papers", "drop", papersPart()]);
  for (let index = 0; index < model.books; index += 1) parts.push([`book-${index}`, "drop", bookPart(index)]);
  parts.push(["laptop", model.screen === "closed" ? "fade" : "open", laptopPart(model.screen)]);
  parts.push(["mug", "drop", mugPart()]);
  parts.push(["plant", "rise", plantPart()]);
  if (model.bloom) parts.push(["flower", "pop", flowerPart()]);
  return parts;
}

const piece = (box, art, anim = "", pivot = null) => ({ box, art, anim, pivot });
const HOOK = `<rect x="347" y="88" width="10" height="10" rx="5" class="f-sand3"/>`;
const FOOTBALL = `<circle cx="318" cy="297" r="17" class="f-kreide s-edge"/><path d="M318 289 L325 294 L322 302 L314 302 L311 294 Z" class="f-tanne"/><path d="M318 280 V289 M335 294 L325 294 M328 311 L322 302 M308 311 L314 302 M301 294 L311 294" class="s-tanne" stroke-width="1.6" fill="none"/>`;
const BASKETBALL = `<circle cx="318" cy="297" r="17" class="f-terra"/><path d="M301 297 H335 M318 280 V314 M306 285 Q 316 297 306 309 M330 285 Q 320 297 330 309" class="s-tanne" stroke-width="1.5" fill="none"/>`;
const SHADOW = piece([300, 308, 36, 10], `<ellipse cx="318" cy="313" rx="16" ry="3.2" class="f-shadow"/>`, "a-shadow", [318, 313]);

function sneaker(dx) {
  return `<path d="M${290 + dx} 312 H${324 + dx} Q ${330 + dx} 312 ${328 + dx} 306 L ${325 + dx} 303 H ${290 + dx} Z" class="f-kreide s-edge"/>
    <path d="M${292 + dx} 304 Q ${291 + dx} 292 ${299 + dx} 290 L ${305 + dx} 290 Q ${311 + dx} 298 ${321 + dx} 300 Q ${327 + dx} 301 ${326 + dx} 304 Z" class="f-terra"/>
    <path d="M${302 + dx} 293 L${308 + dx} 297 M${305 + dx} 291 L${311 + dx} 295" class="s-kreide" stroke-width="1.5" stroke-linecap="round"/>`;
}

function note(x, y, fill, stroke) {
  return `<ellipse cx="${x}" cy="${y + 18}" rx="4.4" ry="3.2" transform="rotate(-20 ${x} ${y + 18})" class="${fill}"/><rect x="${x + 3.2}" y="${y}" width="2" height="18" rx="1" class="${fill}"/><path d="M${x + 4} ${y} q 7 3 6 10" class="${stroke}" stroke-width="2" fill="none" stroke-linecap="round"/>`;
}

const PROPS = {
  cards: {
    slots: ["desk"],
    box: [340, 186, 68, 48],
    pieces: [
      piece([340, 186, 68, 48], `<g transform="rotate(-10 372 222)"><rect x="350" y="206" width="40" height="26" rx="4" class="f-kreide s-edge"/><rect x="350" y="206" width="40" height="6" rx="3" class="f-terra"/></g>
        <g transform="rotate(7 382 222)"><rect x="360" y="204" width="40" height="26" rx="4" class="f-kreide s-edge"/><rect x="360" y="204" width="40" height="6" rx="3" class="f-salbei"/></g>`),
      piece([348, 196, 54, 38], `<g transform="rotate(-2 376 220)"><rect x="354" y="202" width="42" height="28" rx="4" class="f-kreide s-edge"/><rect x="354" y="202" width="42" height="6" rx="3" class="f-gold"/><rect x="360" y="214" width="26" height="3" rx="1.5" class="f-sand3"/><rect x="360" y="220" width="18" height="3" rx="1.5" class="f-sand3"/></g>`, "a-hop", [375, 231]),
    ],
  },
  book: {
    slots: ["desk"],
    box: [344, 180, 64, 52],
    pieces: [
      piece([344, 180, 64, 52], `<path d="M350 230 L402 230 L396 223 L356 223 Z" class="f-sand4"/>
        <path d="M347 224 L374 221 L401 224 L399 189 L374 185 L349 189 Z" class="f-terra"/>
        <path d="M350 222 L374 219 L374 188 L352 192 Z" class="f-kreide s-edge"/>
        <path d="M374 219 L398 222 L396 192 L374 188 Z" class="f-kreide s-edge"/>
        <path d="M356 197 L370 195 M356 203 L371 201 M356 209 L369 207 M378 196 L392 198 M378 202 L393 204 M378 208 L391 210" class="s-sand3" stroke-width="2" stroke-linecap="round"/>`),
      piece([374, 186, 26, 38], `<path d="M374 219 L398 222 L396 192 L374 188 Z" class="f-kreide s-edge"/><path d="M378 196 L392 198 M378 202 L393 204 M378 208 L391 210" class="s-sand3" stroke-width="2" stroke-linecap="round"/>`, "a-turn", [374, 205]),
    ],
  },
  popcorn: {
    slots: ["desk"],
    box: [344, 150, 64, 84],
    pieces: [
      piece([344, 172, 64, 62], `<path d="M354 196 L398 196 L392 230 L360 230 Z" class="f-kreide s-edge"/>
        <path d="M361 196 L368 196 L367 230 L363 230 Z M374 196 L381 196 L380 230 L375 230 Z M387 196 L394 196 L390 230 L386 230 Z" class="f-terra"/>
        <circle cx="360" cy="191" r="6" class="f-kreide s-edge"/><circle cx="369" cy="186" r="6.5" class="f-kreide s-edge"/><circle cx="378" cy="189" r="6" class="f-gold"/><circle cx="386" cy="185" r="6.5" class="f-kreide s-edge"/><circle cx="394" cy="191" r="5.5" class="f-kreide s-edge"/><circle cx="373" cy="193" r="5" class="f-kreide s-edge"/>
        <rect x="352" y="193" width="48" height="6" rx="3" class="f-terra-d"/>`),
      piece([360, 166, 12, 12], `<circle cx="366" cy="172" r="5" class="f-kreide s-edge"/><circle cx="367" cy="171" r="2" class="f-gold"/>`, "a-pop"),
      piece([382, 162, 12, 12], `<circle cx="388" cy="168" r="5" class="f-kreide s-edge"/><circle cx="389" cy="167" r="2" class="f-gold"/>`, "a-pop is-late"),
    ],
  },
  gift: {
    slots: ["desk", "air"],
    box: [344, 112, 64, 122],
    pieces: [
      piece([344, 184, 64, 50], `<rect x="354" y="200" width="40" height="30" rx="4" class="f-terra"/><rect x="351" y="194" width="46" height="9" rx="3" class="f-terra-d"/><rect x="371" y="194" width="6" height="36" class="f-gold"/>
        <ellipse cx="367" cy="190" rx="7" ry="4.5" class="f-gold" transform="rotate(-18 367 190)"/><ellipse cx="381" cy="190" rx="7" ry="4.5" class="f-gold" transform="rotate(18 381 190)"/><circle cx="374" cy="192" r="3" class="f-gold-d"/>`),
      piece([366, 114, 40, 80], `<path d="M374 192 C 377 176 384 166 388 152" class="s-tanne" stroke-width="1.3" fill="none"/><ellipse cx="389" cy="134" rx="13" ry="16" class="f-gold"/><path d="M386 149.5 L392 149.5 L389 154 Z" class="f-gold-d"/><ellipse cx="384" cy="128" rx="3" ry="5" class="f-kreide" opacity=".7"/>`, "a-sway", [374, 192]),
    ],
  },
  speaker: {
    slots: ["desk"],
    box: [344, 150, 64, 84],
    pieces: [
      piece([350, 186, 42, 46], `<rect x="356" y="190" width="30" height="40" rx="6" class="f-tanne"/><circle cx="371" cy="199" r="3.5" class="f-tanne2"/>`),
      piece([361, 206, 20, 20], `<circle cx="371" cy="216" r="8" class="f-tanne2"/><circle cx="371" cy="216" r="3.5" class="f-sand3"/>`, "a-thump", [371, 216]),
      piece([384, 166, 18, 26], note(388, 168, "f-terra", "s-terra"), "a-note"),
      piece([374, 162, 18, 26], note(378, 164, "f-salbei", "s-salbei"), "a-note is-late"),
    ],
  },
  bubbles: {
    slots: ["air"],
    box: [344, 136, 64, 44],
    pieces: [
      piece([344, 148, 38, 30], `<path d="M350 150 H376 Q 380 150 380 154 V166 Q 380 170 376 170 H360 L354 176 L355 170 H350 Q 346 170 346 166 V154 Q 346 150 350 150 Z" class="f-kreide s-edge"/><circle cx="356" cy="160" r="2" class="f-sand3"/><circle cx="363" cy="160" r="2" class="f-sand3"/><circle cx="370" cy="160" r="2" class="f-sand3"/>`, "a-talk", [354, 176]),
      piece([370, 136, 38, 30], `<path d="M376 138 H402 Q 406 138 406 142 V154 Q 406 158 402 158 H396 L397 164 L390 158 H376 Q 372 158 372 154 V142 Q 372 138 376 138 Z" class="f-gold"/><circle cx="382" cy="148" r="2" class="f-kreide"/><circle cx="389" cy="148" r="2" class="f-kreide"/><circle cx="396" cy="148" r="2" class="f-kreide"/>`, "a-talk is-late", [397, 164]),
    ],
  },
  phones: {
    slots: ["wall"],
    box: [322, 86, 60, 60],
    pieces: [
      piece([322, 86, 60, 60], `${HOOK}<path d="M334 128 Q 334 99 352 99 Q 370 99 370 128" class="s-tanne" stroke-width="5" fill="none" stroke-linecap="round"/><rect x="326" y="120" width="14" height="22" rx="6" class="f-terra"/><rect x="364" y="120" width="14" height="22" rx="6" class="f-terra"/>`),
    ],
  },
  towel: {
    slots: ["wall"],
    box: [326, 86, 60, 104],
    pieces: [
      piece([326, 86, 60, 70], `<path d="M346 99 Q 352 94 358 99 L 369 146 Q 352 153 335 146 Z" class="f-salbei-l"/><path d="M352 99 L 350 148" class="s-salbei" stroke-width="1.2" opacity=".5"/>
        <path d="M337 136 Q 352 141 367 136 L 368 141 Q 352 146 336 141 Z" class="f-kreide"/><path d="M336 143 Q 352 148 368 143" class="s-salbei" stroke-width="2" fill="none"/>
        <path d="M355 96 Q 374 101 374 119" class="s-terra" stroke-width="2.4" fill="none" stroke-linecap="round"/>
        <g transform="rotate(62 374 125)"><rect x="364" y="121" width="9" height="7" rx="3.5" class="f-tanne2"/><rect x="375" y="121" width="9" height="7" rx="3.5" class="f-tanne2"/><rect x="372" y="123.5" width="4" height="2" rx="1" class="f-tanne2"/><rect x="366" y="122.5" width="3" height="1.8" rx=".9" class="f-kreide"/></g>
        ${HOOK}`),
      piece([342, 150, 8, 12], `<path d="M346 152 Q 350 158 346 161 Q 342 158 346 152 Z" class="f-water"/>`, "a-drip"),
      piece([357, 151, 8, 12], `<path d="M361 153 Q 365 159 361 162 Q 357 159 361 153 Z" class="f-water"/>`, "a-drip is-late"),
    ],
  },
  key: {
    slots: ["wall"],
    box: [328, 86, 48, 76],
    pieces: [
      piece([346, 86, 12, 12], HOOK),
      piece([334, 92, 40, 66], `<circle cx="352" cy="103" r="7" class="s-sand4" fill="none" stroke-width="2.5"/><circle cx="352" cy="118" r="7" class="f-sand3"/><circle cx="352" cy="118" r="2.4" class="f-kreide"/><path d="M350 124 H354 V142 L357 144 L354 147 V151 H350 Z" class="f-sand3"/>
        <rect x="356" y="104" width="16" height="18" rx="3" class="f-kreide s-edge"/><path d="M361 108 V118 H367" class="s-terra" stroke-width="2.5" fill="none" stroke-linecap="round"/>`, "a-swing", [352, 96]),
    ],
  },
  dumbbell: {
    slots: ["floor"],
    box: [288, 272, 84, 46],
    pieces: [
      piece([292, 308, 76, 10], `<ellipse cx="330" cy="313" rx="34" ry="3" class="f-shadow"/>`),
      piece([292, 276, 76, 40], `<rect x="306" y="291" width="48" height="6" rx="3" class="f-sand4"/><rect x="296" y="279" width="12" height="32" rx="4" class="f-tanne"/><rect x="307" y="283" width="7" height="24" rx="3" class="f-tanne2"/><rect x="352" y="279" width="12" height="32" rx="4" class="f-tanne"/><rect x="346" y="283" width="7" height="24" rx="3" class="f-tanne2"/>`, "a-wobble", [330, 313]),
    ],
  },
  football: {
    slots: ["floor"],
    box: [296, 244, 44, 74],
    pieces: [SHADOW, piece([300, 279, 36, 36], FOOTBALL, "a-bounce", [318, 315])],
  },
  basketball: {
    slots: ["floor"],
    box: [296, 244, 44, 74],
    pieces: [SHADOW, piece([300, 279, 36, 36], BASKETBALL, "a-bounce", [318, 315])],
  },
  tennis: {
    slots: ["floor"],
    box: [300, 236, 128, 82],
    pieces: [
      piece([392, 236, 34, 80], `<g transform="rotate(12 414 280)"><ellipse cx="414" cy="256" rx="12" ry="17" class="f-kreide s-tanne" stroke-width="3"/><path d="M406 246 V266 M414 240 V272 M422 246 V266 M403 252 H425 M402 260 H426" class="s-sand3" stroke-width="1"/><rect x="411" y="272" width="6" height="40" rx="3" class="f-tanne"/></g>`),
      piece([334, 306, 20, 8], `<ellipse cx="344" cy="312" rx="7" ry="1.8" class="f-shadow"/>`, "a-shadow", [344, 312]),
      piece([336, 296, 16, 16], `<circle cx="344" cy="304" r="7" class="f-ball"/><path d="M338 300 Q 344 304 338 309 M350 299 Q 344 304 350 309" class="s-kreide" stroke-width="1.2" fill="none"/>`, "a-bounce", [344, 312]),
    ],
  },
  shoes: {
    slots: ["floor"],
    box: [286, 280, 92, 38],
    pieces: [
      piece([288, 288, 42, 26], sneaker(0), "a-step", [292, 312]),
      piece([332, 288, 42, 26], sneaker(44), "a-step is-late", [336, 312]),
    ],
  },
  backpack: {
    slots: ["floor"],
    box: [290, 250, 74, 68],
    pieces: [
      piece([292, 252, 60, 66], `<path d="M314 262 Q 322 252 330 262" class="s-tanne" stroke-width="3.5" fill="none" stroke-linecap="round"/><rect x="296" y="262" width="52" height="54" rx="16" class="f-salbei"/><path d="M300 274 Q 322 258 344 274 V 280 H 300 Z" class="f-salbei-d"/><rect x="305" y="290" width="34" height="20" rx="7" class="f-salbei-d"/><rect x="319" y="283" width="6" height="7" rx="2" class="f-sand3"/>`),
      piece([338, 276, 18, 30], `<path d="M346 278 V285" class="s-tanne" stroke-width="2" stroke-linecap="round"/><circle cx="346" cy="293" r="7" class="f-kreide s-edge"/><path d="M346 288 L348 293 L346 298 L344 293 Z" class="f-terra"/>`, "a-swing is-quick", [346, 278]),
    ],
  },
  bag: {
    slots: ["floor"],
    box: [272, 248, 100, 70],
    pieces: [
      piece([272, 250, 100, 68], `<path d="M296 280 Q 322 252 348 280" class="s-tanne" stroke-width="5" fill="none" stroke-linecap="round"/><rect x="274" y="274" width="96" height="42" rx="19" class="f-salbei"/><rect x="290" y="285" width="64" height="4" rx="2" class="f-salbei-d"/><circle cx="352" cy="302" r="5" class="f-kreide"/>`),
    ],
  },
};

const CATEGORIES = [
  ["phones", (text, place) => /discord|zoom|teams|meet|online|skype|video/i.test(place)],
  ["towel", (text) => /schwimm|freibad|hallenbad|wasserball/i.test(text)],
  ["football", (text) => /fu(ß|ss)ball|kicken|bolzen|handball|volleyball/i.test(text)],
  ["basketball", (text) => /basketball|korbball/i.test(text)],
  ["tennis", (text) => /tennis|badminton|squash/i.test(text)],
  ["shoes", (text) => /\blauf|jogg|marathon|leichtathletik|sprint/i.test(text)],
  ["speaker", (text) => /tanz|dance|ballett|garde|konzert|chor|band|orchester|musik|gitarre|klavier/i.test(text)],
  ["dumbbell", (text) => /gym|fitness|kraft|workout|hantel|studio/i.test(text)],
  ["popcorn", (text) => /kino|film/i.test(text)],
  ["key", (text) => /fahrstunde|fahrschule|führerschein/i.test(text)],
  ["backpack", (text) => /wander|ausflug|exkursion|klassenfahrt/i.test(text)],
  ["gift", (text) => /geburtstag|party|feier/i.test(text)],
  ["bubbles", (text) => /treffen|meeting|besprechung|sitzung|konferenz|\bag\b|sprechstunde/i.test(text)],
];

export function classifyEvent(event) {
  const text = `${event.title || ""} ${event.place || ""}`;
  const hit = CATEGORIES.find(([, test]) => test(text, event.place || ""));
  if (hit) return hit[0];
  return event.kind === "training" ? "bag" : null;
}

export function pickProps(candidates) {
  const taken = new Set();
  const picked = [];
  [...candidates]
    .sort((a, b) => a.rank - b.rank || a.order - b.order)
    .forEach((item) => {
      const prop = PROPS[item.key];
      if (!prop || picked.some((entry) => entry.key === item.key)) return;
      if (prop.slots.some((slot) => taken.has(slot))) return;
      prop.slots.forEach((slot) => taken.add(slot));
      picked.push({ key: item.key, tip: item.tip });
    });
  return picked;
}

const pct = (value, total) => `${((value / total) * 100).toFixed(3)}%`;
const place = ([x, y, w, h], [bx, by, bw, bh]) => `left:${pct(x - bx, bw)};top:${pct(y - by, bh)};width:${pct(w, bw)};height:${pct(h, bh)}`;
const escAttr = (text) => String(text).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");

function propMarkup(key, tip) {
  const prop = PROPS[key];
  const pieces = prop.pieces.map(({ box, art, anim, pivot }) => {
    const origin = pivot ? `;transform-origin:${pct(pivot[0] - box[0], box[2])} ${pct(pivot[1] - box[1], box[3])}` : "";
    return `<div class="piece${anim ? ` ${anim}` : ""}" style="${place(box, prop.box)}${origin}"><svg viewBox="${box.join(" ")}" aria-hidden="true" focusable="false">${art}</svg></div>`;
  }).join("");
  return `<div class="prop" data-prop="${key}"${tip ? ` data-tip="${escAttr(tip)}"` : ""} style="${place(prop.box, [0, 0, 480, 320])}">${pieces}</div>`;
}

function hash(text) {
  let value = 5381;
  for (let index = 0; index < text.length; index += 1) value = ((value << 5) + value + text.charCodeAt(index)) | 0;
  return (value >>> 0).toString(36);
}

const wrap = ([key, enter, markup]) => `<g data-part="${key}" data-enter="${enter}" data-sig="${hash(markup)}">${markup}</g>`;

const FRAMES = {
  fade: [{ opacity: 0 }, { opacity: 1 }],
  drop: [{ opacity: 0, translate: "0 -24px" }, { opacity: 1, translate: "0 0" }],
  rise: [{ opacity: 0, scale: "0.86" }, { opacity: 1, scale: "1" }],
  open: [{ opacity: 0 }, { opacity: 1 }],
  pop: [{ scale: "0" }, { scale: "1" }],
  arrive: [{ opacity: 0, transform: "translateY(-10%) scale(0.94)" }, { opacity: 1, transform: "none" }],
};

function enter(node, delay = 0) {
  if (!animates()) return;
  const kind = node.dataset.enter;
  if (!travels()) {
    node.animate(FRAMES.fade, { duration: 150, delay, easing: "ease-out", fill: "backwards" });
    return;
  }
  const spring = kind === "pop" ? token("--spring-delight") : token("--spring-tactile");
  const duration = kind === "fade" ? 380 : kind === "pop" ? 640 : 560;
  node.animate(FRAMES[kind] || FRAMES.fade, { duration, delay, easing: kind === "fade" ? token("--ease-out") : spring, fill: "backwards" });
  const lid = kind === "open" && node.querySelector(".sc-lid");
  if (!lid) return;
  lid.animate([{ scale: "1 0.08" }, { scale: "1 1" }], { duration: 620, delay: delay + 60, easing: token("--spring-tactile"), fill: "backwards" });
  node.closest(".scene")?.querySelector(".scene-screen")?.animate(FRAMES.fade, { duration: 260, delay: delay + 520, easing: "ease-out", fill: "backwards" });
}

function arrive(node, delay = 0) {
  if (!animates()) return;
  const frames = travels() ? FRAMES.arrive : FRAMES.fade;
  node.animate(frames, { duration: travels() ? 520 : 150, delay, easing: travels() ? token("--spring-tactile") : "ease-out", fill: "backwards" });
}

function leave(node) {
  if (!animates()) {
    node.remove();
    return;
  }
  const frames = travels() ? [{ opacity: 1, translate: "0 0" }, { opacity: 0, translate: "0 -18px" }] : [{ opacity: 1 }, { opacity: 0 }];
  node.animate(frames, { duration: 300, easing: token("--ease-out"), fill: "forwards" }).finished.then(() => node.remove(), () => node.remove());
}

function depart(node) {
  if (!animates()) {
    node.remove();
    return;
  }
  node.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: "translateY(-8%) scale(0.96)" }], { duration: 260, easing: token("--ease-out"), fill: "forwards" })
    .finished.then(() => node.remove(), () => node.remove());
}

function syncScreen(host, mode) {
  let screen = host.querySelector(".scene-screen");
  if (!screen) {
    screen = document.createElement("div");
    screen.className = "scene-screen";
    screen.setAttribute("aria-hidden", "true");
    host.append(screen);
  }
  if (screen.dataset.mode === mode) return;
  const changed = screen.dataset.mode != null;
  screen.dataset.mode = mode;
  screen.innerHTML = SCREEN[mode] || "";
  if (changed && animates()) screen.animate(FRAMES.fade, { duration: 200, easing: "ease-out" });
}

function syncProps(host, props) {
  let layer = host.querySelector(".scene-props");
  if (!layer) {
    layer = document.createElement("div");
    layer.className = "scene-props";
    host.append(layer);
  }
  const current = new Map([...layer.children].filter((node) => !node.dataset.leaving).map((node) => [node.dataset.prop, node]));
  const wanted = new Set(props.map((prop) => prop.key));
  current.forEach((node, key) => {
    if (wanted.has(key)) return;
    node.dataset.leaving = "1";
    depart(node);
  });
  props.forEach(({ key, tip }) => {
    const old = current.get(key);
    if (old) {
      if (tip) old.dataset.tip = tip;
      else delete old.dataset.tip;
      return;
    }
    const holder = document.createElement("div");
    holder.innerHTML = propMarkup(key, tip);
    const node = holder.firstElementChild;
    layer.append(node);
    if (layer.dataset.ready) arrive(node);
  });
  layer.dataset.ready = "1";
}

function poke(event) {
  const prop = event.target.closest(".prop");
  if (!prop || !travels()) return;
  prop.classList.remove("is-poke");
  void prop.offsetWidth;
  prop.classList.add("is-poke");
  prop.addEventListener("animationend", () => prop.classList.remove("is-poke"), { once: true });
}

const FPS = 12;

export const liteDevice = () => flags.lite
  || matchMedia("(pointer: coarse)").matches
  || (navigator.hardwareConcurrency || 8) <= 4
  || (navigator.deviceMemory || 8) <= 4
  || !!navigator.connection?.saveData;

function watch(host) {
  if (host.dataset.watched) return;
  host.dataset.watched = "1";
  const lite = liteDevice();
  host.classList.toggle("is-lite", lite);
  host.addEventListener("click", poke);
  let time = 4;
  let last = 0;
  let timer = 0;
  const tick = () => {
    const now = performance.now();
    time += Math.min(0.25, (now - last) / 1000);
    last = now;
    host.style.setProperty("--t", time.toFixed(3));
  };
  const sync = () => {
    const live = travels() && !document.hidden && document.hasFocus() && host.dataset.visible !== "0";
    host.classList.toggle("is-still", !live);
    host.classList.toggle("is-static", !travels());
    const ambient = live && !lite;
    if (ambient && !timer) {
      last = performance.now();
      timer = setInterval(tick, 1000 / FPS);
    } else if (!ambient && timer) {
      clearInterval(timer);
      timer = 0;
    }
  };
  new IntersectionObserver(([entry]) => {
    host.dataset.visible = entry.isIntersecting ? "1" : "0";
    sync();
  }).observe(host);
  document.addEventListener("visibilitychange", sync);
  addEventListener("focus", sync);
  addEventListener("blur", sync);
  matchMedia("(prefers-reduced-motion: reduce)").addEventListener("change", sync);
}

export function renderScene(host, model) {
  if (!host) return;
  watch(host);
  host.setAttribute("aria-label", model.label);
  const parts = sceneParts(model);
  const svg = host.querySelector("svg");
  if (!svg) {
    host.insertAdjacentHTML("afterbegin", `<svg viewBox="0 0 480 320" aria-hidden="true" focusable="false">${parts.map(wrap).join("")}</svg>`);
    syncScreen(host, model.screen);
    syncProps(host, model.props);
    return;
  }
  syncScreen(host, model.screen);
  syncProps(host, model.props);
  const holder = document.createElementNS(NS, "svg");
  holder.innerHTML = parts.map(wrap).join("");
  const current = new Map([...svg.children].map((node) => [node.dataset.part, node]));
  const wanted = new Set();
  let anchor = null;
  [...holder.children].forEach((node) => {
    const key = node.dataset.part;
    wanted.add(key);
    const old = current.get(key);
    if (old && old.dataset.sig === node.dataset.sig) {
      anchor = old;
      return;
    }
    if (anchor) anchor.after(node);
    else svg.prepend(node);
    if (old) {
      old.remove();
      if (animates()) node.animate(FRAMES.fade, { duration: 200, easing: "ease-out" });
    } else {
      enter(node);
    }
    anchor = node;
  });
  current.forEach((node, key) => {
    if (!wanted.has(key)) leave(node);
  });
}

export function playIntro(host) {
  if (!host || host.classList.contains("is-lite")) return;
  const parts = [...host.querySelectorAll("[data-part]")];
  parts.forEach((node, index) => enter(node, 120 + index * 65));
  [...host.querySelectorAll(".prop")].forEach((node, index) => arrive(node, 120 + (parts.length + index) * 65));
}
