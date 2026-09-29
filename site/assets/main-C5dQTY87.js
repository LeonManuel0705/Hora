import{t as E}from"./tinte-DSkvZnf7.js";const B=JSON.parse(document.getElementById("content").textContent),da={de:B.i18n_de||{},en:B.i18n_en||{}},pa=new Set;var ja;const M=((ja=B.company)==null?void 0:ja.name)||"";var Ta;const Q=((Ta=B.company)==null?void 0:Ta.repository)||"";var Fa;(Fa=B.company)!=null&&Fa.website;var Va;const se=((Va=B.company)==null?void 0:Va.websiteHost)||"";var Oa;const G=((Oa=B.company)==null?void 0:Oa.email)||"";function ne(){try{const a=localStorage.getItem("lang");return a==="de"||a==="en"?a:null}catch{return null}}let V=ne()||"de";document.documentElement.lang=V;function Ma(a,e){let t=a;for(const s of e.split("."))t=t==null?void 0:t[s];return t}function P(){return V}function $(a){const e=Ma(da[V],a);return e!==void 0?e:Ma(da.de,a)}function l(a,e){let t=$(a);return typeof t!="string"?t===void 0?a:t:(e&&(t=t.replace(/\{(\w+)\}/g,(s,n)=>e[n]!==void 0?e[n]:s)),t)}const o=a=>String(a).replace(/[&<>"']/g,e=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[e]);function oe(a){if(!(a===V||!da[a])){V=a,document.documentElement.lang=a;try{localStorage.setItem("lang",a)}catch{}pa.forEach(e=>e(a))}}function le(a){return pa.add(a),()=>pa.delete(a)}function Ra(a=document){a.querySelectorAll("[data-i18n]").forEach(e=>{e.textContent=l(e.dataset.i18n)}),a.querySelectorAll("[data-i18n-aria]").forEach(e=>{e.setAttribute("aria-label",l(e.dataset.i18nAria))})}const _=()=>matchMedia("(prefers-reduced-motion: reduce)").matches;function Da(a){const e=[...a.querySelectorAll("[data-reveal]")];if(!e.length)return()=>{};if(_()||!("IntersectionObserver"in window))return e.forEach(s=>s.classList.add("is-in")),()=>{};const t=new IntersectionObserver(s=>{for(const n of s)n.isIntersecting&&(n.target.classList.add("is-in"),t.unobserve(n.target))},{rootMargin:"0px 0px -8% 0px",threshold:.12});return e.forEach(s=>t.observe(s)),()=>t.disconnect()}function re(){const a=(e,t)=>`<li><a href="${e}">${o(l(t))}</a></li>`;return`<div class="footer-sign wrap">
    <a class="brand brand-footer" href="/" aria-label="${o(M)}">
      <svg class="brand-mark" viewBox="14 18 72 66" aria-hidden="true" focusable="false">
        <circle class="bm-sun" cx="40" cy="44" r="26" />
        <rect class="bm-tile" x="44" y="42" width="42" height="42" rx="12" />
        <path class="bm-overlap" d="M44 69.69V54A12 12 0 0 1 56 42H65.92A26 26 0 0 1 44 69.69Z" />
      </svg>
      <span class="brand-word">${o(M)}</span>
    </a>
    <p class="footer-sign-line">${o(l("footer.sign"))} <span data-version="full">${o(l("footer.version"))}</span></p>
    <nav class="footer-sign-nav" aria-label="${o(l("footer.nav_label"))}">
      <ul>
        ${a("/features","nav.features")}
        ${a("/privacy-philosophy","nav.privacy")}
        ${a("/download","nav.download_long")}
        ${a("/about","nav.about")}
        <li><a href="${Q}" rel="noopener" target="_blank">${o(l("footer.source"))}</a></li>
        <li><a href="mailto:${G}">${o(l("footer.contact"))}</a></li>
        ${a("/nutzungsbedingungen","footer.terms")}
        ${a("/datenschutz","footer.privacy_policy")}
      </ul>
      <button class="lang-toggle lang-toggle-wide" type="button" data-lang-toggle>${o(l(`lang.name_${l("lang.other")}`))}</button>
    </nav>
  </div>`}let sa=null;function ce(){return sa||(sa=fetch("/version.json",{cache:"no-cache"}).then(a=>a.ok?a.json():null).catch(()=>null)),sa}function ie(a){const e=a.querySelectorAll("[data-version]");e.length&&ce().then(t=>{t&&e.forEach(s=>{const n=s.dataset.version;n==="full"&&t.versionName&&(s.textContent=`Version ${t.versionName}, Build ${t.buildNumber}.`),n==="short"&&t.version&&(s.textContent=`v${t.version}`)})})}const N="0.5.2",X=`${Q}/releases/download/v${N}`,xa=`${M}-macOS.zip`,ka=`${M}-Setup-${N}.exe`,Sa=`${M}-${N}.deb`,Aa=`${M}-${N}.AppImage`,qa=`${M}-${N}.apk`,Y={macos:{id:"macos",name:"macOS",href:`/downloads/${xa}`,file:xa,bytes:23963502,mark:"apple",kind:"zip"},windows:{id:"windows",name:"Windows",href:`${X}/${ka}`,file:ka,bytes:187213513,mark:"windows",kind:"exe"},linux:{id:"linux",name:"Linux",href:`${X}/${Sa}`,file:Sa,bytes:172318748,mark:"linux",kind:"deb",alt:{href:`${X}/${Aa}`,file:Aa,bytes:206080836}},android:{id:"android",name:"Android",href:`${X}/${qa}`,file:qa,bytes:105843702,mark:"android",kind:"apk"},ios:{id:"ios",name:"iPhone und iPad",nameEn:"iPhone and iPad",href:"/pwa/",file:null,bytes:0,mark:"apple",kind:"pwa"},web:{id:"web",name:"Browser",nameEn:"Browser",href:"/pwa/",file:null,bytes:0,mark:"globe",kind:"pwa"}},Pa=["macos","windows","linux","android","ios","web"];function va(){var t;const a=navigator.userAgent||"",e=((t=navigator.userAgentData)==null?void 0:t.platform)||navigator.platform||"";return/iPhone|iPad|iPod/.test(a)||/Mac/.test(e)&&navigator.maxTouchPoints>1?"ios":/Android/i.test(a)?"android":/Mac/i.test(e)||/Mac OS X/.test(a)?"macos":/Win/i.test(e)||/Windows/.test(a)?"windows":/Linux|X11/i.test(e)||/Linux/.test(a)?"linux":null}function O(a){return Math.round(a/1e6)}const ha=new Set;let ua=0,Ea=!1;function de(){ua=0;const a=innerHeight;for(const e of ha)e.visible&&e.run(a)}function W(){ua||(ua=requestAnimationFrame(de))}function pe(){Ea||(Ea=!0,addEventListener("scroll",W,{passive:!0}),addEventListener("resize",W,{passive:!0}))}const K=(a,e=0,t=1)=>Math.min(t,Math.max(e,a));function Na(a,e,t="25%"){if(!a)return()=>{};pe();const s={visible:!1,run:r=>e(a.getBoundingClientRect(),r)},n=new IntersectionObserver(([r])=>{s.visible=r.isIntersecting,s.visible&&W()},{rootMargin:`${t} 0px ${t} 0px`});return n.observe(a),ha.add(s),W(),()=>{n.disconnect(),ha.delete(s)}}function he(a,e=a){if(!a||!e)return()=>{};const t=[...a.querySelectorAll(".w")];if(_())return a.classList.add("is-lit"),()=>{};const s=4,n=new Array(t.length).fill(-1);return Na(e,(r,c)=>{const p=K((c*.15-r.top)/Math.max(1,r.height-c*1.05))*(t.length+s);for(let d=0;d<t.length;d++){const f=Math.round(K((p-d)/s)*100)/100;f!==n[d]&&(n[d]=f,t[d].style.opacity=(.24+.76*f).toFixed(2))}})}function U(a,e){const t=[...a.querySelectorAll(e)];if(!t.length)return()=>{};if(_()||!("IntersectionObserver"in window))return t.forEach(n=>n.classList.add("is-in")),()=>{};const s=new IntersectionObserver(n=>{for(const r of n)r.isIntersecting&&(r.target.classList.add("is-in"),s.unobserve(r.target))},{rootMargin:"0px 0px -12% 0px",threshold:.15});return t.forEach(n=>s.observe(n)),()=>s.disconnect()}function aa(a,{eager:e=!1}={}){return`<figure class="mac">
    <div class="mac-lid">
      <span class="mac-cam" aria-hidden="true"></span>
      <div class="mac-screen">${a.map((s,n)=>`<img class="mac-shot${n===0?" is-on":""}" data-screen="${s.id}" src="/screens/${s.id}.webp" width="2880" height="1800" alt="${o(s.alt)}"${n===0?"":' aria-hidden="true"'} decoding="async"${e&&n===0?' fetchpriority="high"':' loading="lazy"'}>`).join("")}</div>
    </div>
    <div class="mac-base" aria-hidden="true"><span class="mac-groove"></span></div>
  </figure>`}function na(a,e,{dark:t=!1}={}){return`<figure class="iphone${t?" is-dark":""}">
    <div class="iphone-body">
      <div class="iphone-screen"><img src="${a}" width="1170" height="2532" alt="${o(e)}" loading="lazy" decoding="async"><img class="iphone-tabbar" src="${a}" width="1170" height="2532" alt="" loading="lazy" decoding="async"></div>
      <span class="iphone-island" aria-hidden="true"></span>
    </div>
  </figure>`}function ue(a,e){let t=!1;for(const s of a.querySelectorAll(".mac-shot")){const n=s.dataset.screen===e;t||(t=n),s.classList.toggle("is-on",n),n?s.removeAttribute("aria-hidden"):s.setAttribute("aria-hidden","true")}return t}/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const fe=[["path",{d:"M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.49 12H2"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const me=[["path",{d:"M5 12h14"}],["path",{d:"m12 5 7 7-7 7"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const ge=[["path",{d:"M7 7h10v10"}],["path",{d:"M7 17 17 7"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const ve=[["circle",{cx:"12",cy:"12",r:"10"}],["path",{d:"M4.929 4.929 19.07 19.071"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const ye=[["path",{d:"M10.268 21a2 2 0 0 0 3.464 0"}],["path",{d:"M22 8c0-2.3-.8-4.3-2-6"}],["path",{d:"M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326"}],["path",{d:"M4 2C2.8 3.7 2 5.7 2 8"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const $e=[["path",{d:"M12 5v16"}],["path",{d:"m16 12 2 2 4-4"}],["path",{d:"M22 6V5a2 2 0 00-1.999-2L16 3.002A5 5 0 0012 5a5 5 0 00-4-2H4a2 2 0 00-2 2v12a2 2 0 001.999 2H8a5 5 0 014 2 5 5 0 014-2h4.001A2 2 0 0022 17v-1.344"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const be=[["path",{d:"M17 3a2 2 0 0 1 2 2v15a1 1 0 0 1-1.496.868l-4.512-2.578a2 2 0 0 0-1.984 0l-4.512 2.578A1 1 0 0 1 5 20V5a2 2 0 0 1 2-2z"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const we=[["path",{d:"M8 6v6"}],["path",{d:"M15 6v6"}],["path",{d:"M2 12h19.6"}],["path",{d:"M18 18h3s.5-1.7.8-2.8c.1-.4.2-.8.2-1.2 0-.4-.1-.8-.2-1.2l-1.4-5C20.1 6.8 19.1 6 18 6H4a2 2 0 0 0-2 2v10h3"}],["circle",{cx:"7",cy:"18",r:"2"}],["path",{d:"M9 18h5"}],["circle",{cx:"16",cy:"18",r:"2"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const _e=[["path",{d:"M8 2v3"}],["path",{d:"M16 2v3"}],["rect",{x:"3",y:"3",width:"18",height:"18",rx:"2"}],["path",{d:"M3 9h18"}],["path",{d:"M8 13h.01"}],["path",{d:"M12 13h.01"}],["path",{d:"M16 13h.01"}],["path",{d:"M8 17h.01"}],["path",{d:"M12 17h.01"}],["path",{d:"M16 17h.01"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Me=[["path",{d:"M20 6 9 17l-5-5"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const xe=[["path",{d:"m6 9 6 6 6-6"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const ke=[["path",{d:"M21.801 10A10 10 0 1 1 17 3.335"}],["path",{d:"m9 11 3 3L22 4"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Se=[["rect",{width:"8",height:"4",x:"8",y:"2",rx:"1",ry:"1"}],["path",{d:"M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"}],["path",{d:"M12 11h4"}],["path",{d:"M12 16h4"}],["path",{d:"M8 11h.01"}],["path",{d:"M8 16h.01"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Ae=[["circle",{cx:"12",cy:"12",r:"10"}],["path",{d:"M12 6v6h4"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const qe=[["path",{d:"M10.94 5.274A7 7 0 0 1 15.71 10h1.79a4.5 4.5 0 0 1 4.222 6.057"}],["path",{d:"M18.796 18.81A4.5 4.5 0 0 1 17.5 19H9A7 7 0 0 1 5.79 5.78"}],["path",{d:"m2 2 20 20"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Ee=[["path",{d:"M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242"}],["path",{d:"M16 14v6"}],["path",{d:"M8 14v6"}],["path",{d:"M12 16v6"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Le=[["path",{d:"M12 2v2"}],["path",{d:"m4.93 4.93 1.41 1.41"}],["path",{d:"M20 12h2"}],["path",{d:"m19.07 4.93-1.41 1.41"}],["path",{d:"M15.947 12.65a4 4 0 0 0-5.925-4.128"}],["path",{d:"M13 22H7a5 5 0 1 1 4.9-6H13a3 3 0 0 1 0 6Z"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const ze=[["path",{d:"m18 16 4-4-4-4"}],["path",{d:"m6 8-4 4 4 4"}],["path",{d:"m14.5 4-5 16"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Ce=[["rect",{width:"14",height:"14",x:"8",y:"8",rx:"2",ry:"2"}],["path",{d:"M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const He=[["ellipse",{cx:"12",cy:"5",rx:"9",ry:"3"}],["path",{d:"M3 5V19A9 3 0 0 0 21 19V5"}],["path",{d:"M3 12A9 3 0 0 0 21 12"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Be=[["path",{d:"M12 15V3"}],["path",{d:"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"}],["path",{d:"m7 10 5 5 5-5"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Ie=[["path",{d:"M17.596 12.768a2 2 0 1 0 2.829-2.829l-1.768-1.767a2 2 0 0 0 2.828-2.829l-2.828-2.828a2 2 0 0 0-2.829 2.828l-1.767-1.768a2 2 0 1 0-2.829 2.829z"}],["path",{d:"m2.5 21.5 1.4-1.4"}],["path",{d:"m20.1 3.9 1.4-1.4"}],["path",{d:"M5.343 21.485a2 2 0 1 0 2.829-2.828l1.767 1.768a2 2 0 1 0 2.829-2.829l-6.364-6.364a2 2 0 1 0-2.829 2.829l1.768 1.767a2 2 0 0 0-2.828 2.829z"}],["path",{d:"m9.6 14.4 4.8-4.8"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const je=[["circle",{cx:"12",cy:"12",r:"1"}],["circle",{cx:"19",cy:"12",r:"1"}],["circle",{cx:"5",cy:"12",r:"1"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Te=[["path",{d:"M10.733 5.076a10.744 10.744 0 0 1 11.205 6.575 1 1 0 0 1 0 .696 10.747 10.747 0 0 1-1.444 2.49"}],["path",{d:"M14.084 14.158a3 3 0 0 1-4.242-4.242"}],["path",{d:"M17.479 17.499a10.75 10.75 0 0 1-15.417-5.151 1 1 0 0 1 0-.696 10.75 10.75 0 0 1 4.446-5.143"}],["path",{d:"m2 2 20 20"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Fe=[["path",{d:"M4 12.15V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.706.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2h-3.35"}],["path",{d:"M14 2v5a1 1 0 0 0 1 1h5"}],["path",{d:"m5 16-3 3 3 3"}],["path",{d:"m9 22 3-3-3-3"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Ve=[["path",{d:"M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z"}],["path",{d:"M14 2v5a1 1 0 0 0 1 1h5"}],["path",{d:"M10 9H8"}],["path",{d:"M16 13H8"}],["path",{d:"M16 17H8"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Oe=[["path",{d:"M4 22V4a1 1 0 0 1 .4-.8A6 6 0 0 1 8 2c3 0 5 2 7.333 2q2 0 3.067-.8A1 1 0 0 1 20 4v10a1 1 0 0 1-.4.8A6 6 0 0 1 16 16c-3 0-5-2-8-2a6 6 0 0 0-4 1.528"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Re=[["path",{d:"M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13c0 1.1.9 2 2 2Z"}],["path",{d:"M8 10v4"}],["path",{d:"M12 10v2"}],["path",{d:"M16 10v6"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const De=[["circle",{cx:"12",cy:"12",r:"10"}],["path",{d:"M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"}],["path",{d:"M2 12h20"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Pe=[["path",{d:"M21.42 10.922a1 1 0 0 0-.019-1.838L12.83 5.18a2 2 0 0 0-1.66 0L2.6 9.08a1 1 0 0 0 0 1.832l8.57 3.908a2 2 0 0 0 1.66 0z"}],["path",{d:"M22 10v6"}],["path",{d:"M6 12.5V16a6 3 0 0 0 12 0v-3.5"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Ne=[["path",{d:"M10 16h.01"}],["path",{d:"M2.212 11.577a2 2 0 0 0-.212.896V18a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-5.527a2 2 0 0 0-.212-.896L18.55 5.11A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"}],["path",{d:"M21.946 12.013H2.054"}],["path",{d:"M6 16h.01"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Ye=[["path",{d:"M2 9.5a5.5 5.5 0 0 1 9.591-3.676.56.56 0 0 0 .818 0A5.49 5.49 0 0 1 22 9.5c0 2.29-1.5 4-3 5.5l-5.492 5.313a2 2 0 0 1-3 .019L5 15c-1.5-1.5-3-3.2-3-5.5"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Ue=[["path",{d:"M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"}],["path",{d:"M3 10a2 2 0 0 1 .709-1.528l7-6a2 2 0 0 1 2.582 0l7 6A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Xe=[["circle",{cx:"12",cy:"12",r:"10"}],["path",{d:"M12 16v-4"}],["path",{d:"M12 8h.01"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Ze=[["path",{d:"M2.586 17.414A2 2 0 0 0 2 18.828V21a1 1 0 0 0 1 1h3a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h1a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h.172a2 2 0 0 0 1.414-.586l.814-.814a6.5 6.5 0 1 0-4-4z"}],["circle",{cx:"16.5",cy:"7.5",r:".5",fill:"currentColor"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Ge=[["path",{d:"m5 8 6 6"}],["path",{d:"m4 14 6-6 2-3"}],["path",{d:"M2 5h12"}],["path",{d:"M7 2h1"}],["path",{d:"m22 22-5-10-5 10"}],["path",{d:"M14 18h6"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const We=[["path",{d:"M18 5a2 2 0 0 1 2 2v8.526a2 2 0 0 0 .212.897l1.068 2.127a1 1 0 0 1-.9 1.45H3.62a1 1 0 0 1-.9-1.45l1.068-2.127A2 2 0 0 0 4 15.526V7a2 2 0 0 1 2-2z"}],["path",{d:"M20.054 15.987H3.946"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Ke=[["rect",{width:"7",height:"9",x:"3",y:"3",rx:"1"}],["rect",{width:"7",height:"5",x:"14",y:"3",rx:"1"}],["rect",{width:"7",height:"9",x:"14",y:"12",rx:"1"}],["rect",{width:"7",height:"5",x:"3",y:"16",rx:"1"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Je=[["path",{d:"M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5"}],["path",{d:"M9 18h6"}],["path",{d:"M10 22h4"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Qe=[["path",{d:"M13 5h8"}],["path",{d:"M13 12h8"}],["path",{d:"M13 19h8"}],["path",{d:"m3 17 2 2 4-4"}],["path",{d:"m3 7 2 2 4-4"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const at=[["rect",{width:"18",height:"11",x:"3",y:"11",rx:"2",ry:"2"}],["path",{d:"M7 11V7a5 5 0 0 1 10 0v4"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const et=[["path",{d:"m22 7-8.991 5.727a2 2 0 0 1-2.009 0L2 7"}],["rect",{x:"2",y:"4",width:"20",height:"16",rx:"2"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const tt=[["path",{d:"M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0"}],["circle",{cx:"12",cy:"10",r:"3"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const st=[["path",{d:"M2.992 16.342a2 2 0 0 1 .094 1.167l-1.065 3.29a1 1 0 0 0 1.236 1.168l3.413-.998a2 2 0 0 1 1.099.092 10 10 0 1 0-4.777-4.719"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const nt=[["path",{d:"M16 10a2 2 0 0 1-2 2H6.828a2 2 0 0 0-1.414.586l-2.202 2.202A.71.71 0 0 1 2 14.286V4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"}],["path",{d:"M20 9a2 2 0 0 1 2 2v10.286a.71.71 0 0 1-1.212.502l-2.202-2.202A2 2 0 0 0 17.172 19H10a2 2 0 0 1-2-2v-1"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const ot=[["rect",{width:"20",height:"14",x:"2",y:"3",rx:"2"}],["line",{x1:"8",x2:"16",y1:"21",y2:"21"}],["line",{x1:"12",x2:"12",y1:"17",y2:"21"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const lt=[["path",{d:"M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const rt=[["path",{d:"M13.4 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-7.4"}],["path",{d:"M2 6h4"}],["path",{d:"M2 10h4"}],["path",{d:"M2 14h4"}],["path",{d:"M2 18h4"}],["path",{d:"M21.378 5.626a1 1 0 1 0-3.004-3.004l-5.01 5.012a2 2 0 0 0-.506.854l-.837 2.87a.5.5 0 0 0 .62.62l2.87-.837a2 2 0 0 0 .854-.506z"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const ct=[["path",{d:"M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"}],["path",{d:"m15 5 4 4"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const it=[["path",{d:"M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"}],["path",{d:"M21 3v5h-5"}],["path",{d:"M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"}],["path",{d:"M8 16H3v5"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const dt=[["path",{d:"M12 3v18"}],["path",{d:"m19 8 3 8a5 5 0 0 1-6 0zV7"}],["path",{d:"M3 7h1a17 17 0 0 0 8-2 17 17 0 0 0 8 2h1"}],["path",{d:"m5 8 3 8a5 5 0 0 1-6 0zV7"}],["path",{d:"M7 21h10"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const pt=[["path",{d:"M14 21v-3a2 2 0 0 0-4 0v3"}],["path",{d:"M18 4.933V21"}],["path",{d:"m4 6 7.106-3.79a2 2 0 0 1 1.788 0L20 6"}],["path",{d:"m6 11-3.52 2.147a1 1 0 0 0-.48.854V19a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-5a1 1 0 0 0-.48-.853L18 11"}],["path",{d:"M6 4.933V21"}],["circle",{cx:"12",cy:"9",r:"2"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const ht=[["path",{d:"M7 2h13a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-5"}],["path",{d:"M10 10 2.5 2.5C2 2 2 2.5 2 5v3a2 2 0 0 0 2 2h6z"}],["path",{d:"M22 17v-1a2 2 0 0 0-2-2h-1"}],["path",{d:"M4 14a2 2 0 0 0-2 2v4a2 2 0 0 0 2 2h16.5l1-.5.5.5-8-8H4z"}],["path",{d:"M6 18h.01"}],["path",{d:"m2 2 20 20"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const ut=[["path",{d:"M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915"}],["circle",{cx:"12",cy:"12",r:"3"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const ft=[["path",{d:"M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"}],["path",{d:"m9 12 2 2 4-4"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const mt=[["rect",{width:"14",height:"20",x:"5",y:"2",rx:"2",ry:"2"}],["path",{d:"M12 18h.01"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const gt=[["path",{d:"M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z"}],["path",{d:"M20 2v4"}],["path",{d:"M22 4h-4"}],["circle",{cx:"4",cy:"20",r:"2"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const vt=[["path",{d:"M21 9a2.4 2.4 0 0 0-.706-1.706l-3.588-3.588A2.4 2.4 0 0 0 15 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2z"}],["path",{d:"M15 3v5a1 1 0 0 0 1 1h5"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const yt=[["circle",{cx:"12",cy:"12",r:"4"}],["path",{d:"M12 2v2"}],["path",{d:"M12 20v2"}],["path",{d:"m4.93 4.93 1.41 1.41"}],["path",{d:"m17.66 17.66 1.41 1.41"}],["path",{d:"M2 12h2"}],["path",{d:"M20 12h2"}],["path",{d:"m6.34 17.66-1.41 1.41"}],["path",{d:"m19.07 4.93-1.41 1.41"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const $t=[["path",{d:"M12 2v8"}],["path",{d:"m4.93 10.93 1.41 1.41"}],["path",{d:"M2 18h2"}],["path",{d:"M20 18h2"}],["path",{d:"m19.07 10.93-1.41 1.41"}],["path",{d:"M22 22H2"}],["path",{d:"m8 6 4-4 4 4"}],["path",{d:"M16 18a4 4 0 0 0-8 0"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const bt=[["path",{d:"M12 19h8"}],["path",{d:"m4 17 6-6-6-6"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const wt=[["line",{x1:"10",x2:"14",y1:"2",y2:"2"}],["line",{x1:"12",x2:"15",y1:"14",y2:"11"}],["circle",{cx:"12",cy:"14",r:"8"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const _t=[["path",{d:"M8 3.1V7a4 4 0 0 0 8 0V3.1"}],["path",{d:"m9 15-1-1"}],["path",{d:"m15 15 1-1"}],["path",{d:"M9 19c-2.8 0-5-2.2-5-5v-4a8 8 0 0 1 16 0v4c0 2.8-2.2 5-5 5Z"}],["path",{d:"m8 19-2 3"}],["path",{d:"m16 19 2 3"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const Mt=[["path",{d:"M10 11v6"}],["path",{d:"M14 11v6"}],["path",{d:"M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"}],["path",{d:"M3 6h18"}],["path",{d:"M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const xt=[["path",{d:"M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"}],["circle",{cx:"9",cy:"7",r:"4"}],["line",{x1:"17",x2:"22",y1:"8",y2:"13"}],["line",{x1:"22",x2:"17",y1:"8",y2:"13"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const kt=[["path",{d:"M12 20h.01"}],["path",{d:"M8.5 16.429a5 5 0 0 1 7 0"}],["path",{d:"M5 12.859a10 10 0 0 1 5.17-2.69"}],["path",{d:"M19 12.859a10 10 0 0 0-2.007-1.523"}],["path",{d:"M2 8.82a15 15 0 0 1 4.177-2.643"}],["path",{d:"M22 8.82a15 15 0 0 0-11.288-3.764"}],["path",{d:"m2 2 20 20"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const St=[["path",{d:"M18 6 6 18"}],["path",{d:"m6 6 12 12"}]];/**
 * @license lucide v1.48.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const At=[["path",{d:"M15.914 4a1.5 1.5 0 00-2.474-1.561l-9 9A1.5 1.5 0 005.5 14h4.002a.5.5 0 01.471.666L8.086 20a1.5 1.5 0 002.475 1.56l9-9A1.5 1.5 0 0018.5 10h-3.997a.5.5 0 01-.472-.667z"}]],qt={"arrow-right":me,"arrow-up-right":ge,ban:ve,bell:ye,"book-check":$e,bus:we,calendar:_e,check:Me,"chevron-down":xe,"circle-check":ke,clock:Ae,"cloud-off":qe,copy:Ce,download:Be,dumbbell:Ie,"eye-off":Te,code:Fe,globe:De,school:Pe,"hard-drive":Ne,house:Ue,key:Ze,languages:Ge,tasks:Qe,lock:at,mail:et,pin:tt,monitor:ot,moon:lt,scale:dt,building:pt,"server-off":ht,shield:ft,smartphone:mt,sparkles:gt,sun:yt,sunrise:$t,laptop:We,database:He,flag:Oe,info:Xe,refresh:it,heart:Ye,pencil:ct,"code-xml":ze,terminal:bt,timer:wt,train:_t,"user-x":xt,"wifi-off":kt,x:St,"file-text":Ve,chat:nt,note:vt,clipboard:Se,notebook:rt,activity:fe,bookmark:be,"cloud-rain":Ee,"cloud-sun":Le,projects:Re,idea:Je,"message-circle":st,settings:ut,trash:Mt,zap:At,more:je,dashboard:Ke},Et={apple:"M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701",android:"M18.4395 5.5586c-.675 1.1664-1.352 2.3318-2.0274 3.498-.0366-.0155-.0742-.0286-.1113-.043-1.8249-.6957-3.484-.8-4.42-.787-1.8551.0185-3.3544.4643-4.2597.8203-.084-.1494-1.7526-3.021-2.0215-3.4864a1.1451 1.1451 0 0 0-.1406-.1914c-.3312-.364-.9054-.4859-1.379-.203-.475.282-.7136.9361-.3886 1.5019 1.9466 3.3696-.0966-.2158 1.9473 3.3593.0172.031-.4946.2642-1.3926 1.0177C2.8987 12.176.452 14.772 0 18.9902h24c-.119-1.1108-.3686-2.099-.7461-3.0683-.7438-1.9118-1.8435-3.2928-2.7402-4.1836a12.1048 12.1048 0 0 0-2.1309-1.6875c.6594-1.122 1.312-2.2559 1.9649-3.3848.2077-.3615.1886-.7956-.0079-1.1191a1.1001 1.1001 0 0 0-.8515-.5332c-.5225-.0536-.9392.3128-1.0488.5449zm-.0391 8.461c.3944.5926.324 1.3306-.1563 1.6503-.4799.3197-1.188.0985-1.582-.4941-.3944-.5927-.324-1.3307.1563-1.6504.4727-.315 1.1812-.1086 1.582.4941zM7.207 13.5273c.4803.3197.5506 1.0577.1563 1.6504-.394.5926-1.1038.8138-1.584.4941-.48-.3197-.5503-1.0577-.1563-1.6504.4008-.6021 1.1087-.8106 1.584-.4941z",windows:"M0,0H11.377V11.372H0ZM12.623,0H24V11.372H12.623ZM0,12.623H11.377V24H0Zm12.623,0H24V24H12.623",github:"M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"},ya=a=>String(a).replace(/[&<>"]/g,e=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[e]);function Lt(a){return Object.entries(a).map(([e,t])=>`${e}="${ya(t)}"`).join(" ")}function u(a,{size:e=20,cls:t="",stroke:s=2,label:n}={}){const r=qt[a],c=n?`role="img" aria-label="${ya(n)}"`:'aria-hidden="true" focusable="false"';if(!r)return R(a,{size:e,cls:t,label:n});const i=r.map(([p,d])=>`<${p} ${Lt(d)}/>`).join("");return`<svg class="icon ${t}" width="${e}" height="${e}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${s}" stroke-linecap="round" stroke-linejoin="round" ${c}>${i}</svg>`}function R(a,{size:e=20,cls:t="",label:s}={}){const n=Et[a];if(!n)return"";const r=s?`role="img" aria-label="${ya(s)}"`:'aria-hidden="true" focusable="false"';return`<svg class="icon icon-brand ${t}" width="${e}" height="${e}" viewBox="0 0 24 24" fill="currentColor" ${r}><path d="${n}"/></svg>`}const zt="M12.504 0c-.155 0-.315.008-.48.021-4.226.333-3.105 4.807-3.17 6.298-.076 1.092-.3 1.953-1.05 3.02-.885 1.051-2.127 2.75-2.716 4.521-.278.832-.41 1.684-.287 2.489a.424.424 0 00-.11.135c-.26.268-.45.6-.663.839-.199.199-.485.267-.797.4-.313.136-.658.269-.864.68-.09.189-.136.394-.132.602 0 .199.027.4.055.536.058.399.116.728.04.97-.249.68-.28 1.145-.106 1.484.174.334.535.47.94.601.81.2 1.91.135 2.774.6.926.466 1.866.67 2.616.47.526-.116.97-.464 1.208-.946.587-.003 1.23-.269 2.26-.334.699-.058 1.574.267 2.577.2.025.134.063.198.114.333l.003.003c.391.778 1.113 1.132 1.884 1.071.771-.06 1.592-.536 2.257-1.306.631-.765 1.683-1.084 2.378-1.503.348-.199.629-.469.649-.853.023-.4-.2-.811-.714-1.376v-.097l-.003-.003c-.17-.2-.25-.535-.338-.926-.085-.401-.182-.786-.492-1.046h-.003c-.059-.054-.123-.067-.188-.135a.357.357 0 00-.19-.064c.431-1.278.264-2.55-.173-3.694-.533-1.41-1.465-2.638-2.175-3.483-.796-1.005-1.576-1.957-1.56-3.368.026-2.152.236-6.133-3.544-6.139zm.529 3.405h.013c.213 0 .396.062.584.198.19.135.33.332.438.533.105.259.158.459.166.724 0-.02.006-.04.006-.06v.105a.086.086 0 01-.004-.021l-.004-.024a1.807 1.807 0 01-.15.706.953.953 0 01-.213.335.71.71 0 00-.088-.042c-.104-.045-.198-.064-.284-.133a1.312 1.312 0 00-.22-.066c.05-.06.146-.133.183-.198.053-.128.082-.264.088-.402v-.02a1.21 1.21 0 00-.061-.4c-.045-.134-.101-.2-.183-.333-.084-.066-.167-.132-.267-.132h-.016c-.093 0-.176.03-.262.132a.8.8 0 00-.205.334 1.18 1.18 0 00-.09.4v.019c.002.089.008.179.02.267-.193-.067-.438-.135-.607-.202a1.635 1.635 0 01-.018-.2v-.02a1.772 1.772 0 01.15-.768c.082-.22.232-.406.43-.533a.985.985 0 01.594-.2zm-2.962.059h.036c.142 0 .27.048.399.135.146.129.264.288.344.465.09.199.14.4.153.667v.004c.007.134.006.2-.002.266v.08c-.03.007-.056.018-.083.024-.152.055-.274.135-.393.2.012-.09.013-.18.003-.267v-.015c-.012-.133-.04-.2-.082-.333a.613.613 0 00-.166-.267.248.248 0 00-.183-.064h-.021c-.071.006-.13.04-.186.132a.552.552 0 00-.12.27.944.944 0 00-.023.33v.015c.012.135.037.2.08.334.046.134.098.2.166.268.01.009.02.018.034.024-.07.057-.117.07-.176.136a.304.304 0 01-.131.068 2.62 2.62 0 01-.275-.402 1.772 1.772 0 01-.155-.667 1.759 1.759 0 01.08-.668 1.43 1.43 0 01.283-.535c.128-.133.26-.2.418-.2zm1.37 1.706c.332 0 .733.065 1.216.399.293.2.523.269 1.052.468h.003c.255.136.405.266.478.399v-.131a.571.571 0 01.016.47c-.123.31-.516.643-1.063.842v.002c-.268.135-.501.333-.775.465-.276.135-.588.292-1.012.267a1.139 1.139 0 01-.448-.067 3.566 3.566 0 01-.322-.198c-.195-.135-.363-.332-.612-.465v-.005h-.005c-.4-.246-.616-.512-.686-.71-.07-.268-.005-.47.193-.6.224-.135.38-.271.483-.336.104-.074.143-.102.176-.131h.002v-.003c.169-.202.436-.47.839-.601.139-.036.294-.065.466-.065zm2.8 2.142c.358 1.417 1.196 3.475 1.735 4.473.286.534.855 1.659 1.102 3.024.156-.005.33.018.513.064.646-1.671-.546-3.467-1.089-3.966-.22-.2-.232-.335-.123-.335.59.534 1.365 1.572 1.646 2.757.13.535.16 1.104.021 1.67.067.028.135.06.205.067 1.032.534 1.413.938 1.23 1.537v-.043c-.06-.003-.12 0-.18 0h-.016c.151-.467-.182-.825-1.065-1.224-.915-.4-1.646-.336-1.77.465-.008.043-.013.066-.018.135-.068.023-.139.053-.209.064-.43.268-.662.669-.793 1.187-.13.533-.17 1.156-.205 1.869v.003c-.02.334-.17.838-.319 1.35-1.5 1.072-3.58 1.538-5.348.334a2.645 2.645 0 00-.402-.533 1.45 1.45 0 00-.275-.333c.182 0 .338-.03.465-.067a.615.615 0 00.314-.334c.108-.267 0-.697-.345-1.163-.345-.467-.931-.995-1.788-1.521-.63-.4-.986-.87-1.15-1.396-.165-.534-.143-1.085-.015-1.645.245-1.07.873-2.11 1.274-2.763.107-.065.037.135-.408.974-.396.751-1.14 2.497-.122 3.854a8.123 8.123 0 01.647-2.876c.564-1.278 1.743-3.504 1.836-5.268.048.036.217.135.289.202.218.133.38.333.59.465.21.201.477.335.876.335.039.003.075.006.11.006.412 0 .73-.134.997-.268.29-.134.52-.334.74-.4h.005c.467-.135.835-.402 1.044-.7zm2.185 8.958c.037.6.343 1.245.882 1.377.588.134 1.434-.333 1.791-.765l.211-.01c.315-.007.577.01.847.268l.003.003c.208.199.305.53.391.876.085.4.154.78.409 1.066.486.527.645.906.636 1.14l.003-.007v.018l-.003-.012c-.015.262-.185.396-.498.595-.63.401-1.746.712-2.457 1.57-.618.737-1.37 1.14-2.036 1.191-.664.053-1.237-.2-1.574-.898l-.005-.003c-.21-.4-.12-1.025.056-1.69.176-.668.428-1.344.463-1.897.037-.714.076-1.335.195-1.814.12-.465.308-.797.641-.984l.045-.022zm-10.814.049h.01c.053 0 .105.005.157.014.376.055.706.333 1.023.752l.91 1.664.003.003c.243.533.754 1.064 1.189 1.637.434.598.77 1.131.729 1.57v.006c-.057.744-.48 1.148-1.125 1.294-.645.135-1.52.002-2.395-.464-.968-.536-2.118-.469-2.857-.602-.369-.066-.61-.2-.723-.4-.11-.2-.113-.602.123-1.23v-.004l.002-.003c.117-.334.03-.752-.027-1.118-.055-.401-.083-.71.043-.94.16-.334.396-.4.69-.533.294-.135.64-.202.915-.47h.002v-.002c.256-.268.445-.601.668-.838.19-.201.38-.336.663-.336zm7.159-9.074c-.435.201-.945.535-1.488.535-.542 0-.97-.267-1.28-.466-.154-.134-.28-.268-.373-.335-.164-.134-.144-.333-.074-.333.109.016.129.134.199.2.096.066.215.2.36.333.292.2.68.467 1.167.467.485 0 1.053-.267 1.398-.466.195-.135.445-.334.648-.467.156-.136.149-.267.279-.267.128.016.034.134-.147.332a8.097 8.097 0 01-.69.468zm-1.082-1.583V5.64c-.006-.02.013-.042.029-.05.074-.043.18-.027.26.004.063 0 .16.067.15.135-.006.049-.085.066-.135.066-.055 0-.092-.043-.141-.068-.052-.018-.146-.008-.163-.065zm-.551 0c-.02.058-.113.049-.166.066-.047.025-.086.068-.14.068-.05 0-.13-.02-.136-.068-.01-.066.088-.133.15-.133.08-.031.184-.047.259-.005.019.009.036.03.03.05v.02h.003z";function Ct({size:a=20,cls:e=""}={}){return`<svg class="icon icon-brand ${e}" width="${a}" height="${a}" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" focusable="false"><path d="${zt}"/></svg>`}function Ya(a,e=20){const t=Y[a];return t?t.mark==="linux"?Ct({size:e}):t.mark==="globe"?u("globe",{size:e}):R(t.mark,{size:e}):""}let Z=null,Ua=0;function J(){if(!Z)return;const a=Z;Z=null,clearTimeout(Ua),a.classList.remove("is-open"),setTimeout(()=>a.remove(),_()?0:320)}function Ht(a){J();const e=Y[a],t=$(`steps.${a}`),s=document.createElement("div");s.className="dl-toast",s.setAttribute("role","status"),s.innerHTML=`<div class="dl-toast-tinte">${E("geschafft",104)}</div>
    <div class="dl-toast-body">
      <p class="dl-toast-title">${o(l("home_download.done_title"))}</p>
      <p class="dl-toast-file mono">${o(e.file)}, ${O(e.bytes)} MB</p>
      ${Array.isArray(t)?`<ol>${t.map(n=>`<li>${o(n)}</li>`).join("")}</ol>`:""}
    </div>
    <button type="button" class="dl-toast-close" aria-label="${o(l("home_download.done_close"))}">${u("x",{size:18})}</button>`,document.body.append(s),Z=s,requestAnimationFrame(()=>requestAnimationFrame(()=>s.classList.add("is-open"))),s.querySelector(".dl-toast-close").addEventListener("click",J),Ua=setTimeout(()=>{const n=s.querySelector(".dl-toast-tinte");n&&s.isConnected&&(n.innerHTML=E("ruhe",104,l("home_download.tinte_label")))},4200)}function Xa(a){const e=s=>{var c;const n=s.target.closest("[data-copy]");if(n){(c=navigator.clipboard)==null||c.writeText(n.dataset.copy).then(()=>{const i=n.querySelector("span");i.textContent=l("steps.copied"),n.classList.add("is-done"),setTimeout(()=>{i.textContent=l("steps.copy"),n.classList.remove("is-done")},1800)}).catch(()=>{});return}const r=s.target.closest("[data-download]");r&&Ht(r.dataset.download)},t=s=>{s.key==="Escape"&&J()};return a.addEventListener("click",e),document.addEventListener("keydown",t),()=>{a.removeEventListener("click",e),document.removeEventListener("keydown",t),J()}}const fa={macos:"Mac",windows:"Windows",linux:"Linux",android:"Android",ios:"iPhone",web:"Browser"};function Bt(a){return a.length<2?a.join(""):`${a.slice(0,-1).join(", ")} ${P()==="de"?"und":"and"} ${a.at(-1)}`}function $a(){const a=va(),e=Y[a];if(!e)return{button:`<a class="ap-btn" href="/download">${o(l("start.cta_generic"))}</a>`,note:l("start.cta_note_generic")};if(e.kind==="pwa")return{button:`<a class="ap-btn" href="${e.href}">${o(l("start.cta_web"))}</a>`,note:l("start.cta_note_web")};const t=Pa.filter(n=>n!==a&&n!=="web").map(n=>fa[n]),s=l("start.cta_note",{platform:fa[a],size:O(e.bytes),others:Bt(t)});return{button:`<a class="ap-btn" href="${e.href}" download data-download="${a}">${o(l("start.cta"))}</a>`,note:s}}const La='<svg viewBox="0 0 12 20" aria-hidden="true" focusable="false"><path d="M8.5 3.5 2 10l6.5 6.5"/></svg>';function It({id:a,label:e,cards:t}){const s=t.map((r,c)=>`<li class="hl-card hl-${r.id}" data-card="${c}">
      <p class="hl-caption"><strong>${o(r.lead)}</strong> ${o(r.text)}</p>
      <div class="hl-visual">${r.visual}</div>
    </li>`).join(""),n=t.map((r,c)=>`<button type="button" class="hl-dot" data-go="${c}" aria-label="${o(l("start.high_dot",{n:c+1,total:t.length}))}"${c===0?' aria-current="true"':""}><span></span></button>`).join("");return`<div class="hl" data-gallery="${a}">
    <ul class="hl-track" data-track tabindex="0" aria-label="${o(e)}">${s}</ul>
    <div class="hl-controls">
      <div class="hl-dots" style="--i: 0"><span class="hl-pill" aria-hidden="true"></span>${n}</div>
      <div class="hl-arrows">
        <button type="button" class="hl-arrow" data-step="-1" aria-label="${o(l("start.high_prev"))}" disabled>${La}</button>
        <button type="button" class="hl-arrow hl-arrow-next" data-step="1" aria-label="${o(l("start.high_next"))}">${La}</button>
      </div>
    </div>
  </div>`}function jt(a){const e=a.querySelector("[data-gallery]");if(!e)return()=>{};const t=e.querySelector("[data-track]"),s=[...t.querySelectorAll(".hl-card")],n=[...e.querySelectorAll(".hl-dot")],r=e.querySelector(".hl-dots"),[c,i]=e.querySelectorAll(".hl-arrow");let p=0,d=0;const f=v=>v.offsetLeft-s[0].offsetLeft,x=v=>{const w=Math.max(0,Math.min(s.length-1,v));t.scrollTo({left:f(s[w]),behavior:_()?"auto":"smooth"})},S=()=>{d=0;const v=t.scrollWidth-t.clientWidth;let w=0,z=1/0;s.forEach((A,L)=>{const _a=Math.abs(f(A)-t.scrollLeft);_a<z&&(z=_a,w=L)}),t.scrollLeft>=v-4&&(w=s.length-1),w!==p&&(p=w,n.forEach((A,L)=>L===p?A.setAttribute("aria-current","true"):A.removeAttribute("aria-current")),r.style.setProperty("--i",p)),c.disabled=t.scrollLeft<=4,i.disabled=t.scrollLeft>=v-4},g=()=>{d||(d=requestAnimationFrame(S))},m=v=>{const w=v.target.closest("[data-go]");if(w)return x(Number(w.dataset.go));const z=v.target.closest("[data-step]");z&&x(p+Number(z.dataset.step))};return t.addEventListener("scroll",g,{passive:!0}),e.addEventListener("click",m),S(),()=>{cancelAnimationFrame(d),t.removeEventListener("scroll",g),e.removeEventListener("click",m)}}const ma="cubic-bezier(0.16, 1, 0.3, 1)",k="cubic-bezier(0.34, 1.45, 0.64, 1)",F=[{id:"home",old:0,now:0,glyph:"house"},{id:"tasks",old:1,now:1,glyph:"tasks"},{id:"pomodoro",old:2,glyph:"timer"},{id:"calendar",old:3,now:2,glyph:"calendar"},{id:"transit",old:4,now:4,glyph:"train"},{id:"school",old:5,now:3,glyph:"school"},{id:"training",old:6,glyph:"dumbbell"},{id:"projects",old:7,glyph:"projects"},{id:"knowledge",old:8,glyph:"idea"},{id:"bookmarks",old:9,glyph:"bookmark"},{id:"mail",old:10,now:5,glyph:"mail"},{id:"review",old:11,glyph:"activity"},{id:"mousepad",old:12,glyph:"notebook"},{id:"assistant",old:13,glyph:"message-circle"},{id:"settings",old:14,glyph:"settings"}],Tt=[{hour:13,rain:0,glyph:"sun"},{hour:14,rain:0,glyph:"sun"},{hour:15,rain:10,glyph:"cloud-sun"},{hour:16,rain:30,glyph:"cloud-sun"},{hour:17,rain:60,glyph:"cloud-rain"},{hour:18,rain:70,glyph:"cloud-rain"}],Ft=["login","mail","iserv","assistant","desktop","web"],H={old:19,gone:[2,5,8,11,15]},Vt=[["tasks","tasks"],["calendar","events"],["school","grades"],["key","logins"]],h=a=>o(l(`start.scene.${a}`)),Za=()=>P()==="de"?"de-DE":"en-IE";function Ga(a="sc-mark"){return`<svg class="${a}" viewBox="14 18 72 66" aria-hidden="true" focusable="false"><circle cx="40" cy="44" r="26" fill="#E7C694"/><rect x="44" y="42" width="42" height="42" rx="12" fill="#A3B690"/><path d="M44 69.69V54A12 12 0 0 1 56 42H65.92A26 26 0 0 1 44 69.69Z" fill="#2E3A2F"/></svg>`}function Ot(){const a=$("start.scene.nav")||{},e=F.filter(n=>n.now!==void 0).sort((n,r)=>n.now-r.now),t=F.filter(n=>n.now===void 0),s=n=>{const r=n.id==="home"?l("start.scene.nav_home"):a[n.id],c=n.id==="home"?` data-old-label="${o(l("start.scene.nav_home_old"))}"`:"";return`<li class="sc-nav-row${n.id==="home"?" is-current":""}" data-old="${n.old}"${n.now===void 0?" hidden":""}>${u(n.glyph,{size:17})}<span${c}>${o(r||"")}</span></li>`};return`<div class="sc sc-nav" data-scene="nav" role="img" aria-label="${h("nav_alt")}">
    <div class="sc-app sc-side">
      <p class="sc-side-brand">${Ga()}<span>${o(M)}</span></p>
      <ul class="sc-nav-list">${e.map(s).join("")}${t.map(s).join("")}<li class="sc-nav-row sc-nav-more" data-more>${u("more",{size:17})}<span>${h("nav_more")}</span>${u("chevron-down",{size:15,cls:"sc-nav-chev"})}</li></ul>
    </div>
  </div>`}function Rt(){const a=Tt.map(e=>`<li class="sc-hour${e.rain>=50?" is-wet":""}">
      <span class="sc-hour-rain">${e.rain?`${e.rain} %`:""}</span>
      <span class="sc-hour-bar"><i style="--v:${Math.max(e.rain,6)/100}"></i></span>
      ${u(e.glyph,{size:17,cls:"sc-hour-glyph"})}
      <span class="sc-hour-time">${e.hour}</span>
    </li>`).join("");return`<div class="sc sc-weather" data-scene="weather" role="img" aria-label="${h("weather_alt")}">
    <div class="sc-app sc-today">
      <p class="sc-today-meta">${u("sunrise",{size:15})}${h("weather_meta")}</p>
      <p class="sc-today-line">${h("weather_way")} <span class="sc-line-badge">${h("weather_line")}</span> ${h("weather_time")} <span class="sc-weather-chip" data-pop>${h("weather_dry")}</span></p>
      <ol class="sc-hours">${a}</ol>
      <p class="sc-today-event" data-pop>${u("dumbbell",{size:16})}<span>${h("weather_event")}</span><span class="sc-rain-chip">${h("weather_rain")}</span></p>
    </div>
  </div>`}function Dt(){const a=Array.from({length:12},(e,t)=>`<i${t===0?' class="is-on"':""}></i>`).join("");return`<div class="sc sc-tour" data-scene="tour" role="img" aria-label="${h("tour_alt")}">
    <div class="sc-tour-mascot">${E("ruhe",170,"",{still:!0})}</div>
    <div class="sc-app sc-bubble">
      <p class="sc-bubble-steps"><span class="sc-dots">${a}</span><span>${h("tour_step")}</span></p>
      <p class="sc-bubble-text">${h("tour_text")}</p>
      <p class="sc-bubble-actions"><span class="sc-btn is-primary">${h("tour_go")}</span><span class="sc-btn">${h("tour_later")}</span></p>
    </div>
  </div>`}function Pt(){const a=$("start.scene.security")||{},e=Ft.map(t=>`<li class="sc-check-row"><span class="sc-check">${u("check",{size:14,stroke:3})}</span>${o(a[t]||"")}</li>`).join("");return`<div class="sc sc-shield" data-scene="shield" role="img" aria-label="${h("security_alt")}">
    <div class="sc-app sc-app-night sc-report">
      <div class="sc-report-head">
        <span class="sc-report-glyph">${u("shield",{size:22})}</span>
        <p class="sc-report-title">${h("security_title")}<span>${h("security_version")}</span></p>
        <p class="sc-report-count"><b><i data-tally>30</i>+</b><small>${h("security_fixes")}</small></p>
      </div>
      <ul class="sc-check-list">${e}</ul>
    </div>
  </div>`}function Nt(){const a=new Intl.NumberFormat(Za(),{minimumFractionDigits:1,maximumFractionDigits:1}),e=n=>Array.from({length:H.old},(r,c)=>n||!H.gone.includes(c)?"<i></i>":"<i data-gone hidden></i>").join(""),t=(n,r,c,i)=>`<div class="sc-download-row is-${n}"><span class="sc-download-name">${r}</span>${c}<span class="sc-download-mb">${i}</span></div>`,s=`${o(M)} 0.5`;return`<div class="sc sc-size" data-scene="size" role="img" aria-label="${h("size_alt")}">
    <div class="sc-app sc-download">
      <p class="sc-download-title">${u("laptop",{size:17})}${h("size_title")}</p>
      <p class="sc-download-label">${h("size_weight")}</p>
      ${t("old",h("size_old"),'<span class="sc-download-bar"><i></i></span>',`${a.format(39.4)} MB`)}
      ${t("new",s,'<span class="sc-download-bar"><i></i></span>',`<b data-from="39.4" data-to="24">${a.format(24)}</b> MB`)}
      <p class="sc-download-label">${h("size_libs")}</p>
      ${t("old",h("size_old"),`<span class="sc-libs">${e(!0)}</span>`,H.old)}
      ${t("new",s,`<span class="sc-libs" data-libs>${e(!1)}</span>`,`<b data-libs-count>${H.old-H.gone.length}</b>`)}
    </div>
  </div>`}function Yt(){return`<div class="sc sc-guard" data-scene="guard" role="img" aria-label="${h("guard_alt")}">
    <div class="sc-guard-mascot">${E("geschafft",118,"",{still:!0})}</div>
    <div class="sc-app sc-actions">
      <div class="sc-action is-done"><span class="sc-action-glyph">${u("tasks",{size:18})}</span><p>${h("guard_done")}<span>${h("guard_task")}</span></p><span class="sc-check is-big">${u("check",{size:16,stroke:3})}</span></div>
      <div class="sc-action is-denied"><span class="sc-action-glyph">${u("circle-check",{size:18})}</span><p>${h("guard_check")}<span>${h("guard_yours")}</span></p><span class="sc-deny">${u("ban",{size:18})}</span></div>
      <div class="sc-action is-denied"><span class="sc-action-glyph">${u("trash",{size:18})}</span><p>${h("guard_delete")}<span>${h("guard_never")}</span></p><span class="sc-deny">${u("ban",{size:18})}</span></div>
    </div>
  </div>`}function Ut(){const a=Vt.map(([e,t])=>`<li>${u(e,{size:15})}${h(`move_${t}`)}</li>`).join("");return`<div class="sc sc-move" data-scene="move" role="img" aria-label="${h("move_alt")}">
    <div class="sc-move-from"><span class="sc-move-old">N</span><span class="sc-move-caption">${h("move_from")}</span></div>
    <svg class="sc-move-path" viewBox="0 0 200 60" preserveAspectRatio="none" aria-hidden="true" focusable="false"><path d="M4 56 C 60 -8, 140 -8, 196 56"/></svg>
    <div class="sc-move-to"><span class="sc-move-icon">${Ga("sc-move-mark")}</span><span class="sc-move-caption">${o(M)} 0.5</span></div>
    <ul class="sc-move-chips">${a}</ul>
    <p class="sc-move-done">${u("circle-check",{size:17})}${h("move_done")}</p>
  </div>`}function Xt(){return`<div class="sc sc-phones" data-scene="phones" role="img" aria-label="${o(l("start.card_alt_phones"))}">${na("/screens/phone-aufgaben.webp","")}${na("/screens/phone-heute.webp","")}${na("/screens/phone-abend.webp","",{dark:!0})}</div>`}function Zt(){const a=$("start.scene.days")||[],e=[],s=(new Date(2026,9,1).getDay()+6)%7;for(let n=0;n<35;n++){const r=new Date(2026,9,1-s+n),c=r.getMonth()===9,i=c&&r.getDate()===3;e.push(`<span class="sc-date${c?"":" is-out"}${i?" is-holiday":""}">${r.getDate()}</span>`)}return`<div class="sc sc-cal" data-scene="cal" role="img" aria-label="${h("cal_alt")}">
    <div class="sc-app sc-month">
      <p class="sc-month-head"><b>${h("cal_month")}</b>${h("cal_year")}<span class="sc-month-chip">${u("pin",{size:14})}${h("cal_states")}</span></p>
      <div class="sc-month-dows">${a.map(n=>`<span>${o(n)}</span>`).join("")}</div>
      <div class="sc-month-weeks">
        <div class="sc-month-bands"><span class="sc-band" style="grid-area: 4 / 1 / 5 / 8"></span><span class="sc-band" style="grid-area: 5 / 1 / 6 / 6"></span></div>
        <div class="sc-month-days">${e.join("")}</div>
      </div>
      <p class="sc-month-legend"><i></i>${h("cal_break")}<i class="is-holiday"></i>${h("cal_holiday")}</p>
    </div>
  </div>`}const oa={theme:Ot,weather:Rt,tour:Dt,security:Pt,size:Nt,tinte:Yt,move:Ut,phone:Xt,holidays:Zt};function b(a,e){Object.assign(a.style,e)}function y(a,e,t){for(const s of Object.keys(e))a.style[s]="";return a.animate([e,{}],{fill:"backwards",easing:ma,duration:620,...t})}function za(a,e,t,s,n=0){const r=new Intl.NumberFormat(Za(),{minimumFractionDigits:n,maximumFractionDigits:n}),c=performance.now(),i=p=>{const d=Math.min(1,(p-c)/s);a.textContent=r.format(e+(t-e)*(1-Math.pow(1-d,3))),d<1&&requestAnimationFrame(i)};a.textContent=r.format(e),requestAnimationFrame(i)}const C={opacity:"0",transform:"translateY(18px) scale(0.97)"},T={opacity:"0",transform:"scale(0.6)"},la={opacity:"0",transform:"scale(1.5) rotate(-10deg)"},Gt={nav:{prepare(a){const e=a.querySelector(".sc-nav-list");[...e.querySelectorAll("[data-old]")].sort((n,r)=>n.dataset.old-r.dataset.old).forEach(n=>{n.hidden=!1,e.insertBefore(n,e.querySelector("[data-more]"))});const s=e.querySelector("[data-old-label]");s.dataset.newLabel=s.textContent,s.textContent=s.dataset.oldLabel,e.querySelector("[data-more]").hidden=!0},play(a,e){const t=a.querySelector(".sc-nav-list"),s=[...t.querySelectorAll("[data-old]")],n=s.filter(r=>!F[r.dataset.old].hasOwnProperty("now"));n.forEach((r,c)=>r.animate([{},{opacity:0,transform:"translateX(-14px) scale(0.96)"}],{duration:260,delay:120+c*45,easing:"cubic-bezier(0.5, 0, 0.75, 0)",fill:"forwards"})),e(120+n.length*45+240,()=>{const r=s.filter(d=>!n.includes(d)),c=new Map(r.map(d=>[d,d.getBoundingClientRect().top]));n.forEach(d=>{d.getAnimations().forEach(f=>f.cancel()),d.hidden=!0}),r.sort((d,f)=>F[d.dataset.old].now-F[f.dataset.old].now).forEach(d=>t.insertBefore(d,t.querySelector("[data-more]")));const i=t.querySelector("[data-old-label]");i.textContent=i.dataset.newLabel;const p=t.querySelector("[data-more]");p.hidden=!1,r.forEach((d,f)=>{const x=c.get(d)-d.getBoundingClientRect().top;x&&d.animate([{transform:`translateY(${x}px)`},{}],{duration:620,delay:f*30,easing:k})}),i.animate([{opacity:.2,transform:"translateY(6px)"},{}],{duration:420,easing:ma}),y(p,C,{delay:260,duration:520})})}},weather:{prepare(a){a.querySelectorAll(".sc-hour-bar i").forEach(e=>b(e,{transform:"scaleY(0)"})),a.querySelectorAll(".sc-hour-rain").forEach(e=>b(e,{opacity:"0"})),a.querySelectorAll("[data-pop]").forEach(e=>b(e,T))},play(a){a.querySelectorAll(".sc-hour-bar i").forEach((s,n)=>y(s,{transform:"scaleY(0)"},{delay:150+n*90,duration:760})),a.querySelectorAll(".sc-hour-rain").forEach((s,n)=>y(s,{opacity:"0"},{delay:520+n*90,duration:300}));const[e,t]=a.querySelectorAll("[data-pop]");y(e,T,{delay:820,duration:560,easing:k}),y(t,C,{delay:1080,duration:560})}},tour:{prepare(a){b(a.querySelector(".sc-tour-mascot"),{opacity:"0",transform:"translateY(40px) scale(0.86)"}),b(a.querySelector(".sc-bubble"),T),a.querySelectorAll(".sc-dots i").forEach(e=>b(e,{opacity:"0",transform:"scale(0)"}))},play(a){y(a.querySelector(".sc-tour-mascot"),{opacity:"0",transform:"translateY(40px) scale(0.86)"},{duration:760,easing:k}),y(a.querySelector(".sc-bubble"),T,{delay:260,duration:620,easing:k}),a.querySelectorAll(".sc-dots i").forEach((e,t)=>y(e,{opacity:"0",transform:"scale(0)"},{delay:620+t*40,duration:380,easing:k}))}},shield:{prepare(a){a.querySelectorAll(".sc-check-row").forEach(e=>b(e,{opacity:"0",transform:"translateY(12px)"})),a.querySelectorAll(".sc-check").forEach(e=>b(e,{opacity:"0",transform:"scale(1.4) rotate(-8deg)"})),a.querySelector("[data-tally]").textContent="0"},play(a){const e=a.querySelectorAll(".sc-check-row");e.forEach((t,s)=>{y(t,{opacity:"0",transform:"translateY(12px)"},{delay:120+s*110,duration:520}),y(t.querySelector(".sc-check"),{opacity:"0",transform:"scale(1.4) rotate(-8deg)"},{delay:300+s*110,duration:460,easing:k})}),za(a.querySelector("[data-tally]"),0,30,120+e.length*110+400)}},size:{prepare(a){b(a.querySelector(".is-new .sc-download-bar i"),{transform:"scaleX(1)"}),a.querySelectorAll("[data-gone]").forEach(e=>e.hidden=!1),a.querySelector("[data-libs-count]").textContent=H.old},play(a,e){y(a.querySelector(".is-new .sc-download-bar i"),{transform:"scaleX(1)"},{delay:300,duration:1150});const t=a.querySelector("[data-from]");e(300,()=>za(t,Number(t.dataset.from),Number(t.dataset.to),1150,1));const s=[...a.querySelectorAll("[data-gone]")],n=[...a.querySelectorAll("[data-libs] i:not([data-gone])")];s.forEach((c,i)=>c.animate([{},{opacity:0,transform:`translateY(30px) rotate(${i%2?26:-26}deg) scale(0.7)`}],{delay:1300+i*90,duration:540,easing:"cubic-bezier(0.5, 0, 0.75, 0)",fill:"forwards"}));const r=a.querySelector("[data-libs-count]");s.forEach((c,i)=>e(1300+i*90+260,()=>r.textContent=H.old-i-1)),e(1300+s.length*90+480,()=>{const c=new Map(n.map(i=>[i,i.getBoundingClientRect().left]));s.forEach(i=>{i.getAnimations().forEach(p=>p.cancel()),i.hidden=!0}),n.forEach((i,p)=>{const d=c.get(i)-i.getBoundingClientRect().left;d&&i.animate([{transform:`translateX(${d}px)`},{}],{duration:600,delay:p*16,easing:k})})})}},guard:{prepare(a){b(a.querySelector(".sc-guard-mascot"),{opacity:"0",transform:"translateY(30px) scale(0.9)"}),a.querySelectorAll(".sc-action").forEach(e=>b(e,C)),a.querySelectorAll(".sc-check.is-big, .sc-deny").forEach(e=>b(e,la))},play(a){var n;const[e,...t]=a.querySelectorAll(".sc-action");y(a.querySelector(".sc-guard-mascot"),{opacity:"0",transform:"translateY(30px) scale(0.9)"},{duration:700,easing:k}),y(e,C,{delay:220}),y(a.querySelector(".sc-check.is-big"),la,{delay:620,duration:480,easing:k}),(n=t.map((r,c)=>(y(r,C,{delay:900+c*160}),y(r.querySelector(".sc-deny"),la,{delay:1220+c*160,duration:460,easing:k}))).at(-1))==null||n.finished.then(()=>{t.forEach(r=>r.animate([{},{transform:"translateX(-7px)"},{transform:"translateX(6px)"},{transform:"translateX(-3px)"},{}],{duration:440,easing:"ease-in-out"}))},()=>{})}},move:{prepare(a){a.querySelectorAll(".sc-move-chips li").forEach(e=>b(e,{opacity:"0"})),b(a.querySelector(".sc-move-done"),C)},play(a,e){const t=a.querySelector(".sc-move-old").getBoundingClientRect(),s=[...a.querySelectorAll(".sc-move-chips li")];s.forEach((n,r)=>{n.style.opacity="";const c=n.getBoundingClientRect(),i=t.left+t.width/2-(c.left+c.width/2),p=t.top+t.height/2-(c.top+c.height/2);n.animate([{opacity:0,transform:`translate(${i}px, ${p}px) scale(0.4)`},{opacity:1,transform:`translate(${i*.55}px, ${p*.55-70}px) scale(0.9)`,offset:.5},{opacity:1,transform:"none"}],{delay:200+r*150,duration:900,easing:ma,fill:"backwards"})}),e(200+s.length*150+700,()=>{a.querySelector(".sc-move-icon").animate([{},{transform:"scale(1.12, 0.9)"},{transform:"scale(0.96, 1.05)"},{}],{duration:480,easing:"ease-out"}),y(a.querySelector(".sc-move-done"),C,{delay:180,duration:520})})}},phones:{prepare(a){a.querySelectorAll(".iphone").forEach(e=>b(e,{opacity:"0",translate:"0 90px"}))},play(a){a.querySelectorAll(".iphone").forEach((e,t)=>y(e,{opacity:"0",translate:"0 90px"},{delay:[140,0,280][t],duration:900,easing:k}))}},cal:{prepare(a){a.querySelectorAll(".sc-band").forEach(e=>b(e,{transform:"scaleX(0)"})),a.querySelectorAll(".sc-month-legend, .sc-date.is-holiday").forEach(e=>b(e,{opacity:"0"}))},play(a){a.querySelectorAll(".sc-band").forEach((e,t)=>y(e,{transform:"scaleX(0)"},{delay:250+t*420,duration:700})),y(a.querySelector(".sc-month-legend"),{opacity:"0"},{delay:900,duration:480}),a.querySelectorAll(".sc-date.is-holiday").forEach(e=>y(e,T,{delay:1300,duration:500,easing:k}))}}};function Wt(a){const e=[...a.querySelectorAll("[data-scene]")];if(!e.length||_()||!("IntersectionObserver"in window))return()=>{};const t=[],s=(c,i)=>t.push(setTimeout(i,c)),n=new Map;e.forEach(c=>{const i=Gt[c.dataset.scene],p=c.closest(".hl-card");!i||!p||(i.prepare(c),n.set(p,()=>i.play(c,s)))});const r=new IntersectionObserver(c=>{c.forEach(i=>{var p;i.isIntersecting&&(r.unobserve(i.target),(p=n.get(i.target))==null||p())})},{threshold:.6});return n.forEach((c,i)=>r.observe(i)),()=>{r.disconnect(),t.forEach(clearTimeout)}}const Kt=[["#E7C694",-58,-30],["#A3B690",60,-26],["#B7A6F6",-66,22],["#C1657E",64,26],["#4FBADE",-30,58],["#E88F86",34,60]];function Wa(a,e=""){const t=Kt.map(([s,n,r])=>`<circle class="lk-dot" cx="80" cy="95" r="4.2" fill="${s}" data-x="${n}" data-y="${r}"/>`).join("");return`<div class="lk ${e}" data-lock role="img" aria-label="${o(a)}">
    <svg viewBox="0 0 160 160" focusable="false" aria-hidden="true">
      <defs>
        <linearGradient id="lk-body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FBFBFD"/><stop offset="1" stop-color="#C4C4C9"/></linearGradient>
        <linearGradient id="lk-steel" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#8E8E93"/><stop offset="0.5" stop-color="#EDEDF0"/><stop offset="1" stop-color="#8E8E93"/></linearGradient>
      </defs>
      <circle class="lk-ring" cx="80" cy="97" r="44"/>
      <g class="lk-dots">${t}</g>
      <path class="lk-shackle" d="M61 78V60a19 19 0 0 1 38 0v18"/>
      <g class="lk-body-group">
        <rect class="lk-body" x="48" y="72" width="64" height="52" rx="13"/>
        <rect class="lk-shine" x="52" y="75" width="56" height="10" rx="5"/>
        <circle class="lk-hole" cx="80" cy="95" r="6.5"/>
        <rect class="lk-hole" x="77.2" y="97" width="5.6" height="12" rx="2.8"/>
      </g>
    </svg>
  </div>`}function Jt(a){const e="cubic-bezier(0.28, 0.11, 0.32, 1)";[...a.querySelectorAll(".lk-dot")].forEach((s,n)=>{const r=`translate(${s.dataset.x}px, ${s.dataset.y}px) scale(1)`;s.animate([{transform:r,opacity:0},{transform:r,opacity:1,offset:.2},{transform:"translate(0, 0) scale(0.2)",opacity:0}],{duration:760,delay:80+n*45,easing:"cubic-bezier(0.55, 0, 0.75, 0.3)",fill:"both"})}),a.querySelector(".lk-shackle").animate([{transform:"translate(0, -17px) rotate(-26deg)"},{transform:"translate(0, -17px) rotate(0deg)",offset:.5,easing:"cubic-bezier(0.55, 0, 0.9, 0.55)"},{transform:"translate(0, 3px) rotate(0deg)",offset:.82,easing:e},{transform:"translate(0, 0) rotate(0deg)"}],{duration:720,delay:560,easing:e,fill:"both"}),a.querySelector(".lk-body-group").animate([{transform:"scale(1, 1)"},{transform:"scale(1.045, 0.95)",offset:.35},{transform:"scale(1, 1)"}],{duration:320,delay:1150,easing:e}),a.querySelector(".lk-ring").animate([{transform:"scale(1)",opacity:.55},{transform:"scale(1.75)",opacity:0}],{duration:900,delay:1160,easing:"cubic-bezier(0.2, 0.7, 0.3, 1)",fill:"forwards"});for(const s of a.querySelectorAll(".lk-hole"))s.animate([{fill:"#1D1D1F"},{fill:"#E7C694"}],{duration:420,delay:1180,easing:e,fill:"both"})}function Ka(a){const e=[...a.querySelectorAll("[data-lock]")];if(!e.length)return()=>{};if(_()||!("IntersectionObserver"in window)||!Element.prototype.animate)return e.forEach(s=>s.classList.add("is-closed")),()=>{};e.forEach(s=>s.classList.add("is-armed"));const t=new IntersectionObserver(s=>{for(const n of s)n.isIntersecting&&(t.unobserve(n.target),n.target.classList.replace("is-armed","is-closed"),Jt(n.target))},{threshold:.7});return e.forEach(s=>t.observe(s)),()=>t.disconnect()}const j='<svg class="ap-chev" viewBox="0 0 8 14" aria-hidden="true" focusable="false"><path d="M1.5 1.5 6.5 7l-5 5.5"/></svg>';function ea({eyebrow:a,title:e,lede:t,top:s="",extra:n=""}){return`<header class="ap-page-hero">
    ${s}
    <p class="ap-eyebrow ap-reveal">${o(a)}</p>
    <h1 class="ap-page-title ap-reveal">${o(e)}</h1>
    ${t?`<p class="ap-page-lede ap-reveal">${o(t)}</p>`:""}
    ${n}
  </header>`}function Qt(a,[e,t,s,n],r,{max:c=s*1.2}={}){return`<figure class="ap-zoom ap-reveal" style="--rx: ${e}; --ry: ${t}; --rw: ${s}; --rh: ${n}; --ar: ${s} / ${n}; --max: ${Math.round(c)}px">
    <div class="ap-zoom-frame"><img src="/screens/${a}.webp" width="2880" height="1800" alt="${o(r)}" loading="lazy" decoding="async"></div>
  </figure>`}const as=a=>o(a).replace(/(\S+-\S+)/g,'<span class="nw">$1</span>'),es=a=>o(a).split(/\s+/).map(e=>`<span class="w">${e}</span>`).join(" ");function ts(){const{button:a,note:e}=$a();return`<section class="ap-hero" aria-labelledby="ap-hero-title">
    <div class="ap-hero-copy" data-hero-copy>
      <h1 class="ap-hero-head" id="ap-hero-title"><span class="ap-hero-name">${o(l("start.intro"))}</span><span class="ap-hero-title">${o(l("start.title"))}</span></h1>
      <p class="ap-hero-lede">${o(l("start.lede"))}</p>
      <div class="ap-hero-cta">${a}<a class="ap-link" href="#tag">${o(l("start.more"))}${j}</a></div>
      <p class="ap-hero-note">${o(e)}</p>
    </div>
    <div class="ap-hero-device" data-hero-device>${aa([{id:"heute",alt:l("start.hero_alt")}],{eager:!0})}</div>
  </section>`}function ss(){return`<section class="ap-statement" data-statement aria-label="${o(M)}">
    <div class="ap-statement-pin"><p class="ap-words" data-words>${es(l("start.statement"))}</p></div>
  </section>`}function ns(){const a=$("start.steps")||[],e=a.map((t,s)=>`<li class="ap-step${s===0?" is-active":""}" data-step="${t.id}">
      <p class="ap-step-label">${o(t.label)}</p>
      <h3 class="ap-step-title">${as(t.title)}</h3>
      <p class="ap-step-text">${o(t.text)}</p>
      <img class="ap-step-shot" src="/screens/${t.id}.webp" width="2880" height="1800" alt="" loading="lazy" decoding="async">
    </li>`).join("");return`<section class="ap-show" id="tag" aria-labelledby="ap-show-title">
    <h2 class="ap-h2 ap-show-title ap-reveal" id="ap-show-title">${o(l("start.show_title"))}</h2>
    <div class="ap-show-body">
      <ol class="ap-steps">${e}</ol>
      <div class="ap-show-stage"><div class="ap-show-sticky" data-show-device>${aa(a.map(t=>({id:t.id,alt:t.alt})))}</div></div>
    </div>
  </section>`}function os(){const a=($("start.cards")||[]).map(e=>{var t;return{...e,visual:((t=oa[e.id])==null?void 0:t.call(oa))||""}});return`<section class="ap-high" aria-labelledby="ap-high-title">
    <h2 class="ap-h2 ap-high-title ap-reveal" id="ap-high-title">${o(l("start.high_title"))}</h2>
    ${It({id:"highlights",label:l("start.high_label"),cards:a})}
  </section>`}function ls(){const a=$("start.chat")||[],e=$("start.day")||[],t=a.map((n,r)=>`<li class="ap-msg is-${n.from}" data-msg="${r}"${n.mood?` data-mood="${n.mood}"`:""}><p>${o(n.text)}</p></li>`).join(""),s=e.map(n=>`<li class="ap-moment ap-reveal">
      <div class="ap-moment-tinte">${E(n.mood,132,"",{still:!0})}</div>
      <p class="ap-moment-time">${o(n.time)}</p>
      <p class="ap-moment-text">${o(n.text)}</p>
    </li>`).join("");return`<section class="ap-agent" id="tinte" aria-labelledby="ap-agent-title">
    <div class="ap-agent-head">
      <p class="ap-eyebrow ap-reveal">${o(l("start.agent_eyebrow"))}</p>
      <h2 class="ap-h2 ap-reveal" id="ap-agent-title">${o(l("start.agent_title"))}</h2>
      <p class="ap-sub ap-reveal">${o(l("start.agent_text"))}</p>
    </div>
    <div class="ap-agent-stage ap-reveal">
      <div class="ap-agent-avatar" data-avatar>${E("ruhe",280,l("start.tile_tinte_label"))}</div>
      <div class="ap-chat" data-chat>
        <div class="ap-chat-head">
          <span class="ap-chat-face" aria-hidden="true">${E("ruhe",40,"",{still:!0})}</span>
          <div><p class="ap-chat-name">${o(l("start.agent_name"))}</p><p class="ap-chat-role">${o(l("start.agent_role"))}</p></div>
          <p class="ap-chat-time">${o(l("start.agent_time"))}</p>
        </div>
        <ol class="ap-chat-list" role="log" aria-label="${o(l("start.agent_label"))}">${t}<li class="ap-msg is-tinte is-typing" data-typing aria-hidden="true"><p><i></i><i></i><i></i></p></li></ol>
        <div class="ap-chat-input" aria-hidden="true"><span>${o(l("start.agent_input"))}</span><i></i></div>
      </div>
    </div>
    <h3 class="ap-agent-day-title ap-reveal">${o(l("start.day_title"))}</h3>
    <ol class="ap-moments">${s}</ol>
  </section>`}function rs(){return`<section class="ap-free" aria-labelledby="ap-free-title">
    <p class="ap-free-count" data-count role="img" aria-label="${o(l("start.free_label"))}">0,00 €</p>
    <p class="ap-free-lesson ap-reveal">${o(l("start.free_lesson"))}</p>
    <h2 class="ap-free-title ap-reveal" id="ap-free-title">${o(l("start.free_title"))}</h2>
    <p class="ap-free-text ap-reveal">${o(l("start.free_text"))}</p>
  </section>`}function cs(){return`<section class="ap-privacy" aria-labelledby="ap-privacy-title">
    ${Wa(l("start.lock_label"),"ap-lock")}
    <h2 class="ap-h2 ap-reveal" id="ap-privacy-title">${o(l("start.privacy_title"))}</h2>
    <p class="ap-sub ap-reveal">${o(l("start.privacy_text"))}</p>
    <a class="ap-link ap-reveal" href="/privacy-philosophy">${o(l("start.privacy_link"))}${j}</a>
  </section>`}function is(){const a=va(),e=["macos","windows","linux","android","ios"].map(s=>{const n=Y[s],r=n.kind==="pwa",c=r?l("start.cta_web"):`${O(n.bytes)} MB`,i=r?`href="${n.href}"`:`href="${n.href}" download data-download="${s}"`;return`<li><a class="ap-platform${s===a?" is-yours":""}" ${i}>
      <span class="ap-platform-mark">${Ya(s,30)}</span>
      <span class="ap-platform-name">${o(fa[s])}</span>
      <span class="ap-platform-meta">${o(c)}</span>
    </a></li>`}).join(""),{button:t}=$a();return`<section class="ap-get" id="laden" aria-labelledby="ap-get-title">
    <h2 class="ap-get-title ap-reveal" id="ap-get-title">${o(l("start.get_title"))}</h2>
    <p class="ap-sub ap-reveal">${o(l("start.get_text"))}</p>
    <ul class="ap-platforms ap-reveal">${e}</ul>
    <div class="ap-get-cta ap-reveal">${t}<a class="ap-link" href="/download">${o(l("start.get_all"))}${j}</a></div>
    <p class="ap-fine">${o(l("start.fine"))}</p>
    <p class="ap-fine ap-footnote">${o(l("start.footnote_iserv"))}</p>
    <p class="ap-fine ap-footnote">${o(l("start.footnote_agent"))}</p>
    <p class="ap-fine ap-footnote">${o(l("start.footnote"))}</p>
  </section>`}function ds(a){const e=a.querySelector(".ap-hero"),t=a.querySelector("[data-hero-copy]"),s=a.querySelector("[data-hero-device]");return requestAnimationFrame(()=>requestAnimationFrame(()=>e.classList.add("is-ready"))),_()?()=>{}:Na(e,(n,r)=>{const c=K(-n.top/(r*.75));t.style.opacity=String(K(1-c*1.35)),t.style.translate=`0 ${(-c*70).toFixed(1)}px`,s.style.scale=String((1+c*.07).toFixed(4))},"0%")}function ps(a){const e=[...a.querySelectorAll(".ap-step")],t=a.querySelector("[data-show-device]");if(!e.length||!t)return()=>{};for(const r of t.querySelectorAll(".mac-shot"))r.loading="eager";const s=r=>{for(const c of e)c.classList.toggle("is-active",c===r);ue(t,r.dataset.step)},n=new IntersectionObserver(r=>{for(const c of r)c.isIntersecting&&s(c.target)},{rootMargin:"-48% 0px -48% 0px"});return e.forEach(r=>n.observe(r)),()=>n.disconnect()}function hs(a){const e=a.querySelector("[data-chat]"),t=a.querySelector("[data-avatar]");if(!e||!t)return()=>{};const s=[...e.querySelectorAll("[data-msg]")],n=e.querySelector("[data-typing]"),r=l("start.tile_tinte_label");if(_()||!("IntersectionObserver"in window))return s.forEach(g=>g.classList.add("is-in")),()=>{};const c=[],i=(g,m)=>c.push(setTimeout(m,g)),p=getComputedStyle(t).getPropertyValue("--ap-ease").trim()||"ease",d=g=>{const m=t.querySelector(".tinte:not(.is-leaving)");m!=null&&m.classList.contains(`is-${g}`)||(t.insertAdjacentHTML("beforeend",E(g,280,r)),m&&(m.classList.add("is-leaving"),m.animate([{opacity:1,transform:"none"},{opacity:0,transform:"scale(0.94)"}],{duration:480,easing:p,fill:"forwards"}).finished.catch(()=>{}).then(()=>m.remove()),t.lastElementChild.animate([{opacity:0,transform:"scale(1.06)"},{opacity:1,transform:"none"}],{duration:480,easing:p})))},f=g=>g.classList.add("is-in"),x=()=>{let g=0;s.forEach(m=>{if(m.classList.contains("is-me")){i(g,()=>f(m)),g+=700;return}i(g,()=>{n.classList.add("is-in"),d("laedt")}),g+=1250,i(g,()=>{n.classList.remove("is-in"),f(m),d(m.dataset.mood==="cheer"?"geschafft":"ruhe")}),g+=m.dataset.mood==="cheer"?1900:1300,m.dataset.mood==="cheer"&&i(g-300,()=>d("ruhe"))})},S=new IntersectionObserver(g=>{g.some(m=>m.isIntersecting)&&(S.disconnect(),x())},{threshold:.45});return S.observe(e),()=>{S.disconnect(),c.forEach(clearTimeout)}}function us(a){const e=a.querySelector("[data-count]");if(!e)return()=>{};const t=P()==="de"?"de-DE":"en-IE",s=new Intl.NumberFormat(t,{style:"currency",currency:"EUR"}),n=new Intl.NumberFormat(t,{style:"currency",currency:"EUR",minimumFractionDigits:0,maximumFractionDigits:0}).format(0);e.textContent=s.format(0);const r=()=>{e.textContent=n,e.classList.add("is-zero")};if(_()||!("IntersectionObserver"in window))return r(),()=>{};let c=0;const i=49.99,p=1150,d=160,f=1500,x=v=>v<.5?4*v*v*v:1-Math.pow(-2*v+2,3)/2,S=v=>1-Math.pow(1-v,4),g=v=>{const w=z=>{const A=z-v;let L;if(A<p)L=i*x(A/p);else if(A<p+d)L=i;else if(A<p+d+f)L=i*(1-S((A-p-d)/f));else return r();e.textContent=s.format(Math.round(L*100)/100),e.classList.toggle("is-counting",!0),c=requestAnimationFrame(w)};c=requestAnimationFrame(w)},m=new IntersectionObserver(v=>{v.some(w=>w.isIntersecting)&&(m.disconnect(),g(performance.now()))},{threshold:.6});return m.observe(e),()=>{m.disconnect(),cancelAnimationFrame(c)}}const fs={title:()=>l("meta.home"),render:()=>`<div class="ap">${ts()}${ss()}${ns()}${ls()}${os()}${rs()}${cs()}${is()}</div>`,mount(a){const e=[ds(a),he(a.querySelector("[data-words]"),a.querySelector("[data-statement]")),ps(a),U(a,".ap-reveal, .hl"),jt(a),Wt(a),hs(a),us(a),Ka(a),Xa(a)];return()=>e.forEach(t=>t&&t())}},Ca={sand:"#E7C694",salbei:"#A3B690",slate:"#6295D4",iris:"#B7A6F6",plum:"#AC7DC0",lake:"#4FBADE"},Ha={stundenplan:["plan",[336,84,620,501],700],noten:["noten",[980,28,372,456],420],aufgaben:["aufgaben",[316,14,660,600],700],iserv:["plan",[976,64,380,382],440],fahrplan:["bus",[976,64,380,560],420],kalender:["kalender",[316,220,660,540],700]};function ms(a,e){const[t,s,n]=Ha[a.id]||Ha.stundenplan,r=(a.facts||[]).map(c=>`<li>${o(c)}</li>`).join("");return`<article class="ap-feature${e%2?" is-flipped":""}" style="--hue: ${Ca[a.hue]||Ca.sand}" aria-labelledby="feature-${a.id}">
    <div class="ap-feature-copy">
      <p class="ap-feature-eyebrow ap-reveal">${o(a.title)}</p>
      <h2 class="ap-feature-title ap-reveal" id="feature-${a.id}">${o(l(`features_page.heads.${a.id}`))}</h2>
      <p class="ap-feature-text ap-reveal">${o(a.text)}</p>
      <ul class="ap-facts ap-reveal">${r}</ul>
      <p class="ap-devices ap-reveal">${o(l(`home_features.devices_${a.devices}`))}</p>
    </div>
    ${a.id==="tinte"?`<div class="ap-feature-tinte ap-reveal">${E("ruhe",280,l("start.tile_tinte_label"))}</div>`:Qt(t,s,l(`features_page.shots.${a.id}`),{max:n})}
  </article>`}function ra(a){const e=l(`features_page.${a==="yes"?"yes":a==="partial"?"partial":"no"}`);return a==="yes"?`<span class="ap-state is-yes">${u("check",{size:20,stroke:2.6})}<span class="sr-only">${o(e)}</span></span>`:a==="partial"?`<span class="ap-state is-partial">${o(e)}</span>`:`<span class="ap-state is-no" aria-label="${o(e)}">–</span>`}function gs(){const a=$("features_page.groups")||[],e=`<thead><tr>
    <th scope="col"><span class="sr-only">${o(l("features_page.col_feature"))}</span></th>
    <th scope="col"><span class="ap-col">${u("monitor",{size:28,stroke:1.6})}<span>${o(l("features_page.col_desk"))}</span></span></th>
    <th scope="col"><span class="ap-col">${R("android",{size:28})}<span>${o(l("features_page.col_android"))}</span></span></th>
    <th scope="col"><span class="ap-col">${R("apple",{size:28})}<span>${o(l("features_page.col_ios"))}</span></span></th>
  </tr></thead>`,t=a.map(s=>`<tbody>
    <tr class="ap-table-group"><th colspan="4" scope="colgroup">${o(s.title)}</th></tr>
    ${s.rows.map(n=>`<tr>
      <th scope="row"><span class="ap-table-name">${o(n.name)}</span>${n.note?`<span class="ap-table-note">${o(n.note)}</span>`:""}</th>
      <td>${ra(n.d)}</td><td>${ra(n.a)}</td><td>${ra(n.i)}</td>
    </tr>`).join("")}
  </tbody>`).join("");return`<table class="ap-table ap-reveal"><caption class="sr-only">${o(l("features_page.matrix_title"))}</caption>${e}${t}</table>`}const vs={title:()=>l("meta.features"),render:()=>{const a=$("home_features.areas")||[],e=$("features_page.new_items")||[];return`<div class="ap ap-sub-page">
      ${ea({eyebrow:l("features_page.eyebrow"),title:l("features_page.hero_title"),lede:l("features_page.hero_lede")})}
      <div class="ap-page-device ap-reveal">${aa([{id:"plan",alt:l("features_page.hero_alt")}],{eager:!0})}</div>
      <section class="ap-features" aria-label="${o(l("features_page.eyebrow"))}">${a.map(ms).join("")}</section>
      <section class="ap-matrix" aria-labelledby="matrix-title">
        <h2 class="ap-h2 ap-reveal" id="matrix-title">${o(l("features_page.matrix_title"))}</h2>
        ${gs()}
        <p class="ap-note ap-reveal">${o(l("features_page.ios_note"))}</p>
      </section>
      <section class="ap-news" aria-labelledby="news-title">
        <h2 class="ap-h2 ap-reveal" id="news-title">${o(l("features_page.new_title"))}</h2>
        <p class="ap-sub ap-reveal">${o(l("features_page.new_lede"))}</p>
        <ul class="ap-cards">${e.map(t=>`<li class="ap-card ap-reveal"><h3>${o(t.title)}</h3><p>${o(t.text)}</p></li>`).join("")}</ul>
      </section>
      <section class="ap-cta" aria-labelledby="cta-title">
        <h2 class="ap-cta-title ap-reveal" id="cta-title">${o(l("features_page.cta_title"))}</h2>
        <p class="ap-sub ap-reveal">${o(l("features_page.cta_text"))}</p>
        <div class="ap-cta-row ap-reveal"><a class="ap-btn" href="/download">${o(l("download_page.get"))}</a><a class="ap-link" href="/privacy-philosophy">${o(l("start.privacy_link"))}${j}</a></div>
      </section>
    </div>`},mount:a=>U(a,".ap-reveal")};function ys(a){return`<li class="ap-flow ${a.tone==="cancel"?"is-off":a.tone==="warn"?"is-warn":""} ap-reveal">
    <span class="ap-flow-icon">${u(a.icon,{size:22,stroke:1.8})}</span>
    <span class="ap-flow-to">${o(a.to)}</span>
    <span class="ap-flow-what">${o(a.what)}</span>
    <span class="ap-flow-when">${o(a.when)}</span>
  </li>`}const $s={title:()=>l("meta.privacy"),render:()=>{const a=$("privacy_page.where")||[],e=$("privacy_page.flow")||[],t=$("privacy_page.no")||[];return`<div class="ap ap-sub-page">
      ${ea({eyebrow:l("privacy_page.eyebrow"),title:l("privacy_page.title"),lede:l("privacy_page.lede"),top:Wa(l("privacy_page.lock_label"),"ap-lock")})}
      <section class="ap-sec" aria-labelledby="where-title">
        <h2 class="ap-h2 ap-reveal" id="where-title">${o(l("privacy_page.where_title"))}</h2>
        <ul class="ap-cards">${a.map(s=>`<li class="ap-card ap-reveal"><span class="ap-card-icon">${u(s.icon,{size:30,stroke:1.6})}</span><h3>${o(s.title)}</h3><p>${o(s.text)}</p></li>`).join("")}</ul>
      </section>
      <section class="ap-sec" aria-labelledby="flow-title">
        <h2 class="ap-h2 ap-reveal" id="flow-title">${o(l("privacy_page.flow_title"))}</h2>
        <p class="ap-sub ap-reveal">${o(l("privacy_page.flow_lede"))}</p>
        <ul class="ap-flows">${e.map(ys).join("")}</ul>
      </section>
      <section class="ap-sec ap-big-number" aria-labelledby="lock-title">
        <h2 class="ap-h2 ap-reveal" id="lock-title">${o(l("privacy_page.lock_title"))}</h2>
        <p class="ap-sub ap-reveal">${o(l("privacy_page.lock_text"))}</p>
        <div class="ap-stat ap-reveal">
          <p class="ap-number">${o(l("privacy_page.lock_number"))}</p>
          <p class="ap-number-label">${o(l("privacy_page.lock_number_label"))}</p>
        </div>
      </section>
      <section class="ap-sec" aria-labelledby="no-title">
        <h2 class="ap-h2 ap-reveal" id="no-title">${o(l("privacy_page.no_title"))}</h2>
        <ul class="ap-nolist ap-reveal">${t.map(s=>`<li>${u("ban",{size:22,stroke:1.8})}<span>${o(s)}</span></li>`).join("")}</ul>
      </section>
      <section class="ap-cta" aria-labelledby="open-title">
        <h2 class="ap-cta-title ap-reveal" id="open-title">${o(l("privacy_page.open_title"))}</h2>
        <p class="ap-sub ap-reveal">${o(l("privacy_page.open_text"))}</p>
        <div class="ap-cta-row ap-reveal"><a class="ap-btn" href="${Q}" target="_blank" rel="noopener">${R("github",{size:18})}<span>${o(l("privacy_page.open_link"))}</span></a><a class="ap-link" href="/datenschutz">${o(l("privacy_page.legal_link"))}${j}</a></div>
      </section>
    </div>`},mount(a){const e=[U(a,".ap-reveal"),Ka(a)];return()=>e.forEach(t=>t&&t())}};function bs(a,e){const t=Y[a],s=t.kind==="pwa",n=a===e,r=$(`steps.${a}`)||[],c=`curl -sL https://${se}/install-macos.sh | bash`,i=s?`<a class="ap-btn${n?"":" ap-btn-ghost"}" href="${t.href}">${o(l("download_page.open"))}</a>`:`<a class="ap-btn${n?"":" ap-btn-ghost"}" href="${t.href}" download data-download="${a}">${o(l("download_page.get"))}</a>`;return`<article class="ap-dl${n?" is-yours":""} ap-reveal" id="${a}" aria-labelledby="dl-${a}">
    <div class="ap-dl-top">
      <span class="ap-dl-mark">${Ya(a,34)}</span>
      ${n?`<span class="ap-dl-badge">${o(l("download_page.yours"))}</span>`:""}
    </div>
    <h2 class="ap-dl-name" id="dl-${a}">${o(l(`platforms.${a}.name`))}</h2>
    <p class="ap-dl-note">${o(l(`platforms.${a}.note`))}</p>
    <p class="ap-dl-meta">${s?o(l("start.cta_web")):`${o(t.file)}, ${O(t.bytes)} MB`}</p>
    <div class="ap-dl-action">${i}</div>
    ${t.alt?`<p class="ap-dl-meta">${o(l(`platforms.${a}.alt`))} <a href="${t.alt.href}" download>${o(t.alt.file)}, ${O(t.alt.bytes)}&nbsp;MB</a></p>`:""}
    <ol class="ap-dl-steps">${r.map(p=>`<li>${o(p)}</li>`).join("")}</ol>
    ${a==="macos"?`<div class="ap-cmd"><p>${o(l("steps.macos_terminal"))}</p><div class="ap-cmd-row"><code>${o(c)}</code><button type="button" class="ap-copy" data-copy="${o(c)}">${u("copy",{size:15})}<span>${o(l("steps.copy"))}</span></button></div></div>`:""}
  </article>`}const ws={title:()=>l("meta.download"),render:()=>{const a=va(),e=[...Pa];a&&e.sort((c,i)=>c===a?-1:i===a?1:0);const t=$("download_page.faq")||[],{button:s,note:n}=$a(),r=`<div class="ap-hero-cta ap-reveal">${s}</div>
      <p class="ap-hero-note ap-reveal">${o(n)}</p>
      <p class="ap-page-note ap-reveal">${o(l("download_page.name_note"))}</p>`;return`<div class="ap ap-sub-page">
      ${ea({eyebrow:l("download_page.eyebrow"),title:l("download_page.hero_title"),lede:l("download_page.lede"),extra:r})}
      <section class="ap-sec ap-dls" aria-label="${o(l("download_page.eyebrow"))}">${e.map(c=>bs(c,a)).join("")}</section>
      <section class="ap-sec ap-faqs" aria-labelledby="faq-title">
        <h2 class="ap-h2 ap-reveal" id="faq-title">${o(l("download_page.faq_title"))}</h2>
        <div class="ap-faq-list ap-reveal">${t.map(c=>`<details class="ap-faq"><summary><span>${o(c.q)}</span><i class="ap-faq-plus" aria-hidden="true"></i></summary><p>${o(c.a)}</p></details>`).join("")}</div>
      </section>
    </div>`},mount(a){const e=[U(a,".ap-reveal"),Xa(a)];return()=>e.forEach(t=>t&&t())}},_s={title:()=>l("meta.about"),render:()=>{const a=$("about_page.story")||[],e=$("about_page.open")||[];return`<div class="ap ap-sub-page">
      ${ea({eyebrow:l("about_page.eyebrow"),title:l("about_page.title"),lede:l("about_page.lede")})}
      <div class="ap-page-device ap-reveal">${aa([{id:"heute",alt:l("about_page.shot_alt")}],{eager:!0})}</div>
      <section class="ap-sec ap-story" aria-labelledby="story-title">
        <h2 class="ap-h2 ap-reveal" id="story-title">${o(l("about_page.story_title"))}</h2>
        <div class="ap-story-text">${a.map(t=>`<p class="ap-reveal">${o(t)}</p>`).join("")}</div>
      </section>
      <section class="ap-sec" aria-labelledby="open-title">
        <h2 class="ap-h2 ap-reveal" id="open-title">${o(l("about_page.open_title"))}</h2>
        <ul class="ap-cards">${e.map(t=>`<li class="ap-card ap-reveal"><h3>${o(t.title)}</h3><p>${o(t.text)}</p></li>`).join("")}</ul>
      </section>
      <section class="ap-cta" aria-labelledby="contact-title">
        <h2 class="ap-cta-title ap-reveal" id="contact-title">${o(l("about_page.contact_title"))}</h2>
        <p class="ap-sub ap-reveal">${o(l("about_page.contact_text"))}</p>
        <div class="ap-cta-row ap-reveal"><a class="ap-btn" href="mailto:${G}?subject=${encodeURIComponent(M)}">${o(l("about_page.contact_button"))}</a><a class="ap-link" href="${Q}" target="_blank" rel="noopener">${o(l("about_page.code_button"))}${j}</a></div>
      </section>
    </div>`},mount:a=>U(a,".ap-reveal")},ca=`<a class="prose-link" href="mailto:${G}">${G}</a>`;function Ms(a){const e=$(a)||{},t=new Map;for(const[s,n]of Object.entries(e)){const r=s.match(/^(s\d+)_(.+)$/);r&&(t.has(r[1])||t.set(r[1],[]),t.get(r[1]).push([r[2],n]))}return t}function xs(a,e,t){var i;let s="",n=[];const r=()=>{n.length&&(s+=`<ul>${n.map(p=>`<li>${o(p)}</li>`).join("")}</ul>`),n=[]},c=((i=t.find(([p])=>p==="title"))==null?void 0:i[1])||"";for(let p=0;p<t.length;p++){const[d,f]=t[p];if(d!=="title"){if(/^list\d+$/.test(d)){n.push(f);continue}if(r(),/^sub\d+_title$/.test(d))s+=`<h3>${o(f)}</h3>`;else if(d==="name")s+=`<p class="legal-name"><strong>${o(f)}</strong></p>`;else if(d==="email_label")s+=`<p>${o(f)} ${ca}</p>`;else{if(d==="link")continue;if(/^p\d+$/.test(d)||/^sub\d+_p\d+$/.test(d)){const x=t.find(([S])=>S==="link");x&&d==="p1"&&a==="terms"&&e==="s6"?s+=`<p>${o(f)} <a class="prose-link" href="/datenschutz">${o(x[1])}</a>.</p>`:s+=`<p>${o(f)}</p>`,a==="terms"&&e==="s8"&&d==="p1"&&(s+=`<p>${ca}</p>`),a==="privacy_policy"&&e==="s7"&&d==="p1"&&(s+=`<p class="legal-name"><strong>${o(l("privacy_policy.s1_name"))}</strong></p><p>${ca}</p>`)}}}}return r(),`<section class="legal-section" id="${e}" aria-labelledby="${e}-title"><h2 id="${e}-title">${o(c)}</h2>${s}</section>`}function Ja(a,e){const t=Ms(a),s=[...t.entries()].map(([r,c])=>{var i;return`<li><a href="#${r}">${o(((i=c.find(([p])=>p==="title"))==null?void 0:i[1])||r)}</a></li>`}).join(""),n=[...t.entries()].map(([r,c])=>xs(a,r,c)).join("");return`<article class="legal wrap">
    <header class="legal-head" data-reveal>
      <h1>${o(l(`${a}.hero_title`))}</h1>
      <p class="legal-date mono">${o(l(`${a}.hero_date`))}</p>
    </header>
    <div class="legal-grid">
      <nav class="legal-toc" aria-label="${o(l("legal.toc"))}" data-reveal style="--i:1">
        <p class="legal-toc-title">${o(l("legal.toc"))}</p>
        <ol>${s}</ol>
        <a class="legal-other" href="${e.href}">${u("arrow-right",{size:15})}<span>${o(l(e.key))}</span></a>
      </nav>
      <div class="legal-body" data-reveal="fade" style="--i:1">${n}</div>
    </div>
  </article>`}const ks={theme:"light",title:()=>l("meta.terms"),render:()=>Ja("terms",{href:"/datenschutz",key:"legal.other_privacy"}),mount:a=>Da(a)},Ss={theme:"light",title:()=>l("meta.privacy_policy"),render:()=>Ja("privacy_policy",{href:"/nutzungsbedingungen",key:"legal.other_terms"}),mount:a=>Da(a)},ba={"/":fs,"/features":vs,"/privacy-philosophy":$s,"/download":ws,"/about":_s,"/nutzungsbedingungen":ks,"/datenschutz":Ss},ia=document.getElementById("app"),As=document.getElementById("site-header"),Ba=document.getElementById("site-footer"),q=document.getElementById("mobile-menu"),ta=document.querySelector("[data-menu-open]");let Ia=()=>{},D=null;const Qa=a=>{const e=a.replace(/\/index\.html$/,"/").replace(/\/+$/,"")||"/";return ba[e]?e:"/"};function qs(a){document.querySelectorAll("[data-nav]").forEach(e=>{e.getAttribute("href")===a?e.setAttribute("aria-current","page"):e.removeAttribute("aria-current")})}function ae(){const a=P()==="de"?"en":"de";document.querySelectorAll("[data-lang-toggle]").forEach(e=>{const t=e.classList.contains("lang-toggle-wide");e.textContent=t?l(`lang.name_${a}`):a.toUpperCase(),e.setAttribute("aria-label",l("lang.switch")),e.setAttribute("lang",a)})}function wa(a,{hash:e="",focus:t=!1}={}){const s=ba[a];if(Ia(),document.body.dataset.route=a==="/"?"home":a.slice(1),document.body.dataset.theme=s.theme||"dark",ia.innerHTML=s.render(),Ba.innerHTML=re(),ie(Ba),document.title=s.title?s.title():M,qs(a),Ia=s.mount?s.mount(ia)||(()=>{}):()=>{},D=a,e){const n=document.getElementById(decodeURIComponent(e.slice(1)));n?(requestAnimationFrame(()=>n.scrollIntoView({block:"center"})),n.classList.add("is-target")):scrollTo(0,0)}else scrollTo(0,0);t&&ia.focus({preventScroll:!0})}function ee(a,{push:e=!0}={}){const t=new URL(a,location.href),s=Qa(t.pathname);e&&history.pushState({},"",s+t.hash),I();const n=()=>wa(s,{hash:t.hash,focus:e});document.startViewTransition&&!_()&&D!==s?document.startViewTransition(n):n()}document.addEventListener("click",a=>{var n;const e=a.target.closest("a[href]");if(!e||a.defaultPrevented||a.button!==0||a.metaKey||a.ctrlKey||a.shiftKey||a.altKey||e.target&&e.target!=="_self"||e.hasAttribute("download"))return;const t=new URL(e.href,location.href);if(t.origin!==location.origin)return;const s=t.pathname.replace(/\/+$/,"")||"/";if(ba[s]){if(a.preventDefault(),s===D&&t.hash){history.pushState({},"",s+t.hash),(n=document.getElementById(decodeURIComponent(t.hash.slice(1))))==null||n.scrollIntoView({behavior:_()?"auto":"smooth",block:"start"}),I();return}if(s===D&&!t.hash){I(),scrollTo({top:0,behavior:_()?"auto":"smooth"});return}ee(t.href)}});addEventListener("popstate",()=>ee(location.href,{push:!1}));document.addEventListener("click",a=>{a.target.closest("[data-lang-toggle]")&&oe(P()==="de"?"en":"de")});le(()=>{Ra(),ae();const a=scrollY;wa(D||"/"),scrollTo(0,a)});function Es(){var a;q.hidden=!1,requestAnimationFrame(()=>q.classList.add("is-open")),ta.setAttribute("aria-expanded","true"),document.body.classList.add("menu-open"),(a=q.querySelector("a"))==null||a.focus({preventScroll:!0})}function I(){if(q.hidden)return;q.classList.remove("is-open"),ta.setAttribute("aria-expanded","false"),document.body.classList.remove("menu-open");const a=()=>{q.classList.contains("is-open")||(q.hidden=!0)};_()?a():setTimeout(a,260)}ta.addEventListener("click",()=>q.hidden?Es():I());document.addEventListener("keydown",a=>{a.key==="Escape"&&!q.hidden&&(I(),ta.focus())});matchMedia("(min-width: 900px)").addEventListener("change",a=>{a.matches&&I()});let ga=!1;function te(){ga=!1,As.classList.toggle("is-scrolled",scrollY>8)}addEventListener("scroll",()=>{ga||(ga=!0,requestAnimationFrame(te))},{passive:!0});Ra();ae();wa(Qa(location.pathname),{hash:location.hash});te();
