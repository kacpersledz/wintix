#!/usr/bin/env node
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const root = process.argv[2] || process.cwd();
const structure = fs.readFileSync(`${root}/commands/plasma/panel-structure.js`, "utf8");
const settings = fs.readFileSync(`${root}/commands/plasma/panel-settings.js`, "utf8");
const types = ["org.kde.plasma.kickoff", "org.kde.plasma.pager", "org.kde.plasma.taskmanager", "org.kde.plasma.marginsseparator", "org.kde.plasma.systemtray", "org.kde.plasma.digitalclock", "org.kde.plasma.showdesktop"];
const launchers = ["applications:brave-browser.desktop", "applications:org.kde.dolphin.desktop", "applications:org.kde.konsole.desktop"];
let nextId;
function widget(panel, type, id, config = {}) { return { type, id, config: {...config}, writes: [], reloads: 0, removed: false,
  readConfig(k,d) { return Object.hasOwn(this.config,k) ? this.config[k] : d; },
  writeConfig(k,v) { this.config[k]=v; this.writes.push([k,v]); }, reloadConfig() { this.reloads++; },
  remove() { this.removed=true; panel.config.AppletOrder=panel.config.AppletOrder.split(";").filter(x=>x!==String(id)).join(";"); }
}; }
function panel(initialTypes=types, ids=[103,204,305,406,507,608,709], options={}) {
  nextId=options.nextId || 900; const p={location:"bottom",screen:0,config:{AppletOrder: options.order ?? ids.join(";")},writes:[],items:[],
    readConfig(k,d){return Object.hasOwn(this.config,k)?this.config[k]:d}, writeConfig(k,v){this.config[k]=v;this.writes.push([k,v])},
    widgets(t){let a=this.items.filter(x=>!x.removed); if(options.enumeration) a=options.enumeration.map(id=>a.find(x=>x.id===id)).filter(Boolean).concat(a.filter(x=>!options.enumeration.includes(x.id))); return t?a.filter(x=>x.type===t):a},
    widgetById(id){return this.items.find(x=>x.id===id&&!x.removed)}, addWidget(t){const w=widget(this,t,nextId++);this.items.push(w);this.config.AppletOrder=[this.config.AppletOrder,w.id].filter(Boolean).join(";");return w}
  }; p.items=initialTypes.map((t,i)=>widget(p,t,ids[i],options.configs?.[i])); return p;
}
function run(script,p,desktops={}) { return vm.runInNewContext(script,{panels:()=>[p],desktopById:id=>desktops[id]}); }
function ordered(p){return p.config.AppletOrder.split(";").map(id=>p.widgetById(Number(id)).type)}
function canonical(p){assert.deepEqual(ordered(p),types);assert.deepEqual(p.widgets().map(x=>x.type).sort(),types.slice().sort())}
// Exact state is a structural no-op, regardless of enumeration order.
{const p=panel(types,undefined,{enumeration:[608,103,507,709,305,204,406]});assert.equal(run(structure,p),"unchanged");assert.deepEqual(p.writes,[]);canonical(p)}
// Permutation converges semantically, without trusting enumeration order.
{const ts=[types[4],types[2],types[0],types[6],types[1],types[5],types[3]], ids=[507,305,103,709,204,608,406];const p=panel(ts,ids,{enumeration:ids.slice().reverse()});run(structure,p);canonical(p)}
// Icons-only, every missing kind (including task manager and tray), duplicates,
// and arbitrary extras all converge to exactly one canonical set.
{const p=panel(types.map(t=>t===types[2]?"org.kde.plasma.icontasks":t));run(structure,p);canonical(p)}
for(let missing=0;missing<types.length;missing++){const ts=types.filter((_,i)=>i!==missing),ids=[103,204,305,406,507,608].map((x,i)=>x+missing*20);const p=panel(ts,ids,{order:ids.join(";"),nextId:800+missing});run(structure,p);canonical(p)}
{const p=panel([...types,types[0],"org.example.extra"],[103,204,305,406,507,608,709,810,811]);run(structure,p);canonical(p)}
// Verification failure is surfaced.
{const p=panel(types,[103,204,305,406,507,608,709],{order:"204;103;305;406;507;608;709"});p.writeConfig=function(){};assert.match(run(structure,p),/WINTIX_ERROR:.*rejected|WINTIX_ERROR:.*verification/)}
assert.doesNotMatch(structure,/Widget\.index|\.index\s*=/);assert.doesNotMatch(structure,/(applet|containment)(Id|ID)\s*=\s*[0-9]+/);
// Settings touch only owned Task Manager values and inner-tray visibility.
{const p=panel(types,undefined,{configs:[{},{},{groupingStrategy:1,unrelated:"keep"},{},{SystrayContainmentId:42}]});const inner=widget(p,"inner",42,{shownItems:["shown-other"],hiddenItems:["hidden-other","org.kde.plasma.weather"],extraItems:["composition"],provider:"keep"});run(settings,p,{42:inner});const task=p.widgets(types[2])[0];assert.deepEqual(JSON.parse(JSON.stringify(task.config)),{groupingStrategy:0,unrelated:"keep",separateLaunchers:false,interactiveMute:false,launchers});assert.equal(task.reloads,1);assert.deepEqual(JSON.parse(JSON.stringify(inner.config.shownItems)),["shown-other","org.kde.plasma.notifications","org.kde.plasma.weather","org.kde.plasma.battery"]);assert.deepEqual(JSON.parse(JSON.stringify(inner.config.hiddenItems)),["hidden-other"]);assert.deepEqual(inner.config.extraItems,["composition"]);assert.equal(inner.config.provider,"keep");assert.equal(inner.reloads,1);assert.ok(inner.writes.every(([k])=>k!=="extraItems"))}
// Correct settings are write/reload-free.
{const cfg={groupingStrategy:0,separateLaunchers:false,interactiveMute:false,launchers};const p=panel(types,undefined,{configs:[{},{},cfg,{},{SystrayContainmentId:77}]});const shown=["other","org.kde.plasma.notifications","org.kde.plasma.weather","org.kde.plasma.battery"],inner=widget(p,"inner",77,{shownItems:shown,hiddenItems:["other-hidden"]});assert.equal(run(settings,p,{77:inner}),"unchanged");assert.deepEqual(p.widgets(types[2])[0].writes,[]);assert.equal(inner.reloads,0)}
// A newly added tray is usable in phase two, while unavailable containment fails safely.
{const p=panel(types.filter(t=>t!==types[4]),[103,204,305,406,608,709],{nextId:950});run(structure,p);const tray=p.widgets(types[4])[0];tray.config.SystrayContainmentId=88;const inner=widget(p,"inner",88,{});run(settings,p,{88:inner});assert.equal(inner.writes.length,1)}
{const p=panel(types,undefined,{configs:[{},{},{},{},{SystrayContainmentId:99}]});assert.match(run(settings,p,{}),/WINTIX_ERROR:.*not available/);assert.doesNotMatch(settings,/writeConfig\("extraItems"/)}
console.log("Plasma panel runtime tests passed");
