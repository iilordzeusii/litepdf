// Run from repo root after `npm run vendor` and `python3 test/make_sample.py`:  node test/engine.test.mjs
import fs from "fs"; import assert from "assert"; import * as E from "../web/engine.js";
const buf = new Uint8Array(fs.readFileSync("test/sample.pdf"));
// redaction really removes the text
const r = E.open(buf); assert.equal(E.redactText(r, "SECRET-1234"), 1); E.applyRedactions(r);
const red = E.save(r); assert(!E.pageText(E.open(red), 0).includes("SECRET")); assert(!Buffer.from(red).includes("SECRET-1234"));
assert(E.pageText(E.open(red), 0).includes("Public sentence"));
// merge / split
assert.equal(E.merge([buf, buf]).countPages(), 6);
assert.deepEqual(E.splitBy(buf, "1,2-3").map(x => E.open(x).countPages()), [1, 2]);
// forms
const f = E.open(buf); E.setWidget(f, 0, 0, "Aryan"); assert.equal(E.listWidgets(E.open(E.save(f)), 0)[0].value, "Aryan");
// password
const prot = E.protect(E.open(buf), { user: "u1", owner: "o1", perms: "print" });
assert.throws(() => E.open(prot)); assert.equal(E.open(prot, "u1").countPages(), 3);
// compression
assert(E.compress(buf, "strong").length < buf.length / 5);
console.log("engine tests passed");
