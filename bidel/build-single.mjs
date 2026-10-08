// Builds a single self-contained HTML body (hash routing, inlined CSS/JS) for static hosting.
import { readFileSync, writeFileSync, readdirSync } from 'node:fs'
const dir = 'dist-single/assets'
const files = readdirSync(dir)
const css = readFileSync(`${dir}/${files.find((f) => f.endsWith('.css'))}`, 'utf8')
const js = readFileSync(`${dir}/${files.find((f) => f.endsWith('.js'))}`, 'utf8').replace(/<\/script/gi, '<\\/script')
const out = process.argv[2] ?? 'dist-single/bidel.html'
writeFileSync(out, `<title>Bidel prototyp</title>
<meta name="description" content="Bidel – marknadsplats för begagnade bildelar. Prototyp under utveckling.">
<style>${css}</style>
<div id="root"></div>
<script type="module">${js}</script>
`)
console.log('wrote', out, Math.round((css.length + js.length) / 1024), 'KB')
