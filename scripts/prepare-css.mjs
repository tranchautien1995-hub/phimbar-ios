import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import postcss from 'postcss';
import presetEnv from 'postcss-preset-env';

// Immutable public stylesheet. Hash prevents silently bundling a changed response.
const url = 'https://phimbar.com/_app/immutable/assets/2.bidTnhBZ.css';
const expected = '98c1bb9efe34685abdf884efc2b5d5d1c6631c40e176f828f458907ea465c5a2';
const response = process.env.PHIMBAR_CSS_FILE ? null : await fetch(url);
if (response && !response.ok) throw new Error(`CSS download failed: ${response.status}`);
const source = response ? await response.text() : await fs.readFile(process.env.PHIMBAR_CSS_FILE, 'utf8');
assert.equal(createHash('sha256').update(source).digest('hex'), expected, 'Source CSS changed');
const root = postcss.parse(source, {from:url});
const defaults = postcss.rule({selector:'*,::before,::after'});
root.walkAtRules('property', rule => {
  rule.walkDecls('initial-value', declaration => defaults.append({prop:rule.params, value:declaration.value}));
});
// Safari 15.1 has no @property registration. Initialize non-inherited variables
// separately, without the unsupported ::backdrop selector in Tailwind's fallback.
const propertiesLayer = root.nodes.find(node => node.type==='atrule' && node.name==='layer' && node.params==='properties');
assert.ok(propertiesLayer,'Missing Tailwind property layer');
propertiesLayer.prepend(defaults);
root.walkDecls(declaration => {
  declaration.value = declaration.value.replace(/url\((['"]?)([^)'"\s]+)\1\)/g, (match, quote, path) => {
    if (/^(data:|https?:|#)/.test(path)) return match;
    return `url("${new URL(path,url).href}")`;
  });
});
const result = await postcss([presetEnv({
  browsers:['iOS >= 15.0'], stage:2, preserve:false,
  features:{'cascade-layers':true,'nesting-rules':true}
})]).process(root, {from:url, map:false});
const output = postcss.parse(result.css);
let layerCount = 0;
output.walkAtRules('layer', () => layerCount++);
assert.equal(layerCount,0,'Safari 15.1 cannot parse cascade layers');
for (const selector of ['.fixed','.hidden','.flex','.size-6']) {
  let found=false;
  output.walkRules(rule => {if(rule.selector.includes(selector)) found=true;});
  assert.ok(found, `Missing layout utility ${selector}`);
}
assert.ok(!/@media\s*\([^)]*\bwidth\s*[<>]/.test(result.css),'Media range syntax must be lowered');
// No generic button padding or sizing: the website's own icon styles must win.
await fs.writeFile('Resources/legacy.css', result.css+'\nhtml{-webkit-text-size-adjust:100%}\n');
console.log(`Converted ${source.length} → ${result.css.length} bytes for iOS 15; layers removed; layout assertions passed.`);
for (const warning of result.warnings()) console.warn(warning.toString());