#!/usr/bin/env node
// Wraps the App Kit design system (~/developer/app-kit) as an installable
// package so the design-sync converter can build it. App Kit ships a classic
// IIFE bundle that reads window.React and assigns window.AppKit; the wrapper
// sets the global from `react` first, then re-exports the ten components as
// ESM. tokens.json becomes CSS variables (light default, dark via media query
// and data-theme). Output goes into node_modules, so it is regenerated, never
// committed.
//
//   node .design-sync/prep-appkit.mjs [<app-kit-dir>] <node_modules-dir>
import { readFileSync, writeFileSync, mkdirSync, rmSync, readdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { homedir } from 'node:os';

const args = process.argv.slice(2);
const NM = resolve(args.pop());
const SRC = resolve(args[0] ?? join(homedir(), 'developer/app-kit'), 'design-system/project');
const COMP = join(SRC, 'components');
const OUT = join(NM, 'app-kit');

rmSync(OUT, { recursive: true, force: true });
mkdirSync(join(OUT, 'component-docs'), { recursive: true });
mkdirSync(join(OUT, 'guides'), { recursive: true });
mkdirSync(join(OUT, 'tokens'), { recursive: true });

const bundle = readFileSync(join(COMP, 'bundle.js'), 'utf8');
const header = /@ds-bundle: (\{.*\}) \*\//.exec(bundle);
const names = JSON.parse(header[1]).components.map((c) => c.name);

writeFileSync(join(OUT, 'package.json'), JSON.stringify({
  name: 'app-kit', version: '1.0.0', type: 'module',
  module: 'index.js', main: 'index.js', types: 'index.d.ts',
  peerDependencies: { react: '>=18', 'react-dom': '>=18' },
}, null, 2) + '\n');
writeFileSync(join(OUT, 'react-global.js'),
  "import React from 'react';\nglobalThis.React = React;\n");
writeFileSync(join(OUT, 'appkit-bundle.js'), bundle);
writeFileSync(join(OUT, 'index.js'),
  "import './react-global.js';\nimport './appkit-bundle.js';\nconst A = globalThis.AppKit;\n"
  + names.map((n) => `export const ${n} = A.${n};`).join('\n') + '\n');
writeFileSync(join(OUT, 'index.d.ts'), readFileSync(join(COMP, 'index.d.ts'), 'utf8'));

// The first rule is the preview harness's page chrome (16px body padding);
// a design owns its own layout, so keep the ground/ink/font and drop the pad.
const css = readFileSync(join(COMP, 'bundle.css'), 'utf8').replace(/(^body \{[^}]*?)padding: 16px; /, '$1');
writeFileSync(join(OUT, 'appkit.css'), css);

// Per-component docs: the README body, grouped by the preview's @dsCard group.
for (const n of names) {
  const card = readFileSync(join(COMP, n, 'preview.html'), 'utf8').split('\n')[0];
  const group = /group="([^"]+)"/.exec(card)?.[1] ?? 'Components';
  const readme = join(COMP, n, 'README.md');
  const body = existsSync(readme) ? readFileSync(readme, 'utf8') : `# ${n}\n`;
  writeFileSync(join(OUT, 'component-docs', `${n}.md`), `---\ncategory: ${group}\n---\n${body}`);
}

// The system-level principles ship as the one guideline page.
writeFileSync(join(OUT, 'guides', 'app-kit.md'), readFileSync(join(SRC, 'README.md'), 'utf8'));

const t = JSON.parse(readFileSync(join(SRC, 'tokens.json'), 'utf8'));
const light = [], dark = [];
for (const c of t.color.tokens) { light.push(`  --${c.name}: ${c.value.light};`); dark.push(`  --${c.name}: ${c.value.dark};`); }
for (const [f, v] of Object.entries(t.type.families)) light.push(`  --font-${f}: ${v};`);
for (const fam of ['spacing', 'radius']) for (const s of t[fam].tokens) light.push(`  --${s.name}: ${s.value};`);
for (const s of t.shadow.tokens) {
  if (typeof s.value === 'string') { light.push(`  --${s.name}: ${s.value};`); continue; }
  light.push(`  --${s.name}: ${s.value.light};`); dark.push(`  --${s.name}: ${s.value.dark};`);
}
const darkBlock = dark.join('\n');
writeFileSync(join(OUT, 'tokens', 'tokens.css'),
  `/* ${t.name} tokens, generated from tokens.json by .design-sync/prep-appkit.mjs. */\n`
  + `:root {\n  color-scheme: light dark;\n${light.join('\n')}\n}\n\n`
  + `@media (prefers-color-scheme: dark) {\n  :root:not([data-theme="light"]) {\n${darkBlock.replace(/^/gm, '  ')}\n  }\n}\n\n`
  + `:root[data-theme="dark"] {\n${darkBlock}\n}\n`);

console.log(`app-kit -> ${OUT}: ${names.length} components (${names.join(', ')}), `
  + `${readdirSync(join(OUT, 'component-docs')).length} docs, ${light.length + dark.length} token lines`);
