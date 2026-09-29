import { brandName, brandRepository } from "./i18n.js";

const version = "0.5.2";
const release = `${brandRepository}/releases/download/v${version}`;
const macZip = `${brandName}-macOS.zip`;
const windowsSetup = `${brandName}-Setup-${version}.exe`;
const linuxDeb = `${brandName}-${version}.deb`;
const linuxAppImage = `${brandName}-${version}.AppImage`;
const androidApk = `${brandName}-${version}.apk`;

export const PLATFORMS = {
  macos: { id: "macos", name: "macOS", href: `/downloads/${macZip}`, file: macZip, bytes: 23963502, mark: "apple", kind: "zip" },
  windows: { id: "windows", name: "Windows", href: `${release}/${windowsSetup}`, file: windowsSetup, bytes: 187213513, mark: "windows", kind: "exe" },
  linux: {
    id: "linux", name: "Linux", href: `${release}/${linuxDeb}`, file: linuxDeb, bytes: 172318748, mark: "linux", kind: "deb",
    alt: { href: `${release}/${linuxAppImage}`, file: linuxAppImage, bytes: 206080836 },
  },
  android: { id: "android", name: "Android", href: `${release}/${androidApk}`, file: androidApk, bytes: 105843702, mark: "android", kind: "apk" },
  ios: { id: "ios", name: "iPhone und iPad", nameEn: "iPhone and iPad", href: "/pwa/", file: null, bytes: 0, mark: "apple", kind: "pwa" },
  web: { id: "web", name: "Browser", nameEn: "Browser", href: "/pwa/", file: null, bytes: 0, mark: "globe", kind: "pwa" },
};

export const ORDER = ["macos", "windows", "linux", "android", "ios", "web"];

export function detectPlatform() {
  const ua = navigator.userAgent || "";
  const platform = navigator.userAgentData?.platform || navigator.platform || "";
  if (/iPhone|iPad|iPod/.test(ua) || (/Mac/.test(platform) && navigator.maxTouchPoints > 1)) return "ios";
  if (/Android/i.test(ua)) return "android";
  if (/Mac/i.test(platform) || /Mac OS X/.test(ua)) return "macos";
  if (/Win/i.test(platform) || /Windows/.test(ua)) return "windows";
  if (/Linux|X11/i.test(platform) || /Linux/.test(ua)) return "linux";
  return null;
}

export function megabytes(bytes) {
  return Math.round(bytes / 1e6);
}
