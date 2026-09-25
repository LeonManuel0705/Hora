import fs from 'node:fs';

const BRAND_FILE = new URL('../../brand/brand.json', import.meta.url);

export function applyBrand(text) {
  const { name, repository, website } = JSON.parse(fs.readFileSync(BRAND_FILE, 'utf-8'));
  return text
    .replaceAll('{{BRAND_NAME}}', name)
    .replaceAll('{{BRAND_REPOSITORY}}', repository)
    .replaceAll('{{BRAND_WEBSITE_HOST}}', new URL(website).host)
    .replaceAll('{{BRAND_WEBSITE}}', website);
}

export function brandPlaceholder() {
  return {
    name: 'brand-placeholder',
    transformIndexHtml: applyBrand,
  };
}
