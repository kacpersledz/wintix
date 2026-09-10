#!/usr/bin/env node
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const root = process.argv[2] || process.cwd();
const structure = fs.readFileSync(`${root}/commands/plasma/panel-structure.js`, "utf8");
const order = fs.readFileSync(`${root}/commands/plasma/panel-order.js`, "utf8");
const settings = fs.readFileSync(`${root}/commands/plasma/panel-settings.js`, "utf8");
const types = [
  "org.kde.plasma.kickoff", "org.kde.plasma.pager", "org.kde.plasma.taskmanager",
  "org.kde.plasma.marginsseparator", "org.kde.plasma.systemtray",
  "org.kde.plasma.digitalclock", "org.kde.plasma.showdesktop",
];
const ids = [103, 204, 305, 406, 507, 608, 709];
const launchers = ["applications:brave-browser.desktop", "applications:org.kde.dolphin.desktop", "applications:org.kde.konsole.desktop"];

function makeWidget(panel, type, id, config = {}) {
  return { type, id, config: {...config}, writes: [], reloads: 0, removed: false,
    readConfig(key, fallback) { return Object.hasOwn(this.config, key) ? this.config[key] : fallback; },
    writeConfig(key, value) { this.config[key] = value; this.writes.push([key, value]); },
    reloadConfig() { this.reloads++; },
    remove() {
      this.removed = true;
      panel.removals.push(id);
      panel.visualIds = panel.visualIds.filter(candidate => candidate !== id);
      // Plasma 6.6.6 saves the current live layout during removal. A previous
      // Wintix AppletOrder write would be lost here.
      panel.config.AppletOrder = panel.visualIds.join(";");
    },
  };
}

function makePanel(initialTypes = types, initialIds = ids, options = {}) {
  const panel = {
    location: "bottom", screen: 0, config: {AppletOrder: options.order ?? initialIds.join(";")},
    writes: [], removals: [], items: [], visualIds: (options.visualIds || initialIds).slice(), pendingDeferredSave: false,
    nextId: options.nextId || 900,
    readConfig(key, fallback) { return Object.hasOwn(this.config, key) ? this.config[key] : fallback; },
    writeConfig(key, value) {
      this.writes.push([key, value]);
      if (!options.rejectOrder) this.config[key] = value;
      // Deliberately do not reorder visualIds: Plasma can defer that until restart.
    },
    widgets(type) {
      let active = this.items.filter(item => !item.removed);
      if (options.enumerationIds) {
        active = options.enumerationIds.map(id => active.find(item => item.id === id)).filter(Boolean)
          .concat(active.filter(item => !options.enumerationIds.includes(item.id)));
      }
      return type ? active.filter(item => item.type === type) : active;
    },
    widgetById(id) { return this.items.find(item => item.id === id && !item.removed); },
    addWidget(type) {
      const added = makeWidget(this, type, this.nextId++);
      this.items.push(added);
      this.visualIds.push(added.id);
      this.pendingDeferredSave = true;
      return added;
    },
  };
  panel.items = initialTypes.map((type, index) => makeWidget(panel, type, initialIds[index], options.configs?.[index]));
  return panel;
}
function run(script, panel, desktops = {}) {
  return vm.runInNewContext(script, {panels: () => [panel], desktopById: id => desktops[id]});
}
function flushDeferredSave(panel) {
  if (panel.pendingDeferredSave) {
    panel.config.AppletOrder = panel.visualIds.join(";");
    panel.pendingDeferredSave = false;
  }
}
function persistedIds(panel) { return panel.config.AppletOrder.split(";").map(Number); }
function canonicalIds(panel) { return types.map(type => panel.widgets(type)[0].id); }
function assertPersistedCanonical(panel) {
  assert.deepEqual(persistedIds(panel), canonicalIds(panel));
  assert.equal(panel.widgets().length, types.length);
  for (const type of types) assert.equal(panel.widgets(type).length, 1);
}

// Exact canonical state is a complete structural no-op.
{
  const panel = makePanel(types, ids, {enumerationIds: ids.slice().reverse()});
  assert.equal(run(structure, panel), "unchanged");
  flushDeferredSave(panel);
  assert.equal(run(order, panel), "unchanged");
  assert.deepEqual(panel.writes, []); assert.deepEqual(panel.removals, []);
  assertPersistedCanonical(panel);
}
// A canonical permutation persists canonical IDs without pretending visual order changed.
{
  const permutation = [507, 305, 103, 709, 204, 608, 406];
  const panel = makePanel(types, ids, {order: permutation.join(";"), visualIds: permutation});
  assert.equal(run(structure, panel), "unchanged");
  flushDeferredSave(panel);
  assert.equal(run(order, panel), "changed");
  assert.deepEqual(panel.visualIds, permutation);
  assertPersistedCanonical(panel);
}
// Missing Task Manager is added and persisted in canonical position.
{
  const panel = makePanel(types.filter(type => type !== types[2]), [103,204,406,507,608,709], {nextId: 920});
  assert.equal(run(structure, panel), "changed"); flushDeferredSave(panel);
  assert.equal(run(order, panel), "changed");
  assert.equal(persistedIds(panel)[2], 920); assertPersistedCanonical(panel);
}
// Regression: Icons-Only removal overwrites AppletOrder, then Wintix's final write restores it.
{
  const initialTypes = types.map(type => type === types[2] ? "org.kde.plasma.icontasks" : type);
  const panel = makePanel(initialTypes, ids, {nextId: 925});
  assert.equal(run(structure, panel), "changed");
  flushDeferredSave(panel);
  assert.equal(run(order, panel), "changed");
  assert.deepEqual(panel.removals, [305]);
  assert.equal(panel.widgets(types[2])[0].id, 925);
  assert.equal(panel.writes.at(-1)[0], "AppletOrder");
  assertPersistedCanonical(panel);
}
// Missing tray is added and persisted in canonical slot five.
{
  const panel = makePanel(types.filter(type => type !== types[4]), [103,204,305,406,608,709], {nextId: 950});
  assert.equal(run(structure, panel), "changed");
  assert.equal(panel.pendingDeferredSave, true);
  assert.equal(panel.visualIds.at(-1), 950);
  flushDeferredSave(panel);
  assert.equal(persistedIds(panel).at(-1), 950);
  assert.equal(run(order, panel), "changed");
  assert.equal(persistedIds(panel)[4], 950); assertPersistedCanonical(panel);
}
// Duplicate and extra removals each trigger Plasma's save; final write still wins.
for (const [extraType, extraId] of [[types[0], 810], ["org.example.extra", 811]]) {
  const panel = makePanel([...types, extraType], [...ids, extraId], {visualIds:[204,103,extraId,305,406,507,608,709]});
  run(structure, panel); flushDeferredSave(panel);
  assert.equal(run(order, panel), "changed");
  assert.deepEqual(panel.removals, [extraId]); assertPersistedCanonical(panel);
  assert.equal(panel.writes.at(-1)[0], "AppletOrder");
}
// A rejected final persistence write is a structural error.
{
  const visual = [204,103,305,406,507,608,709];
  const panel = makePanel(types, ids, {order: visual.join(";"), visualIds: visual, rejectOrder: true});
  assert.equal(run(structure, panel), "unchanged");
  assert.match(run(order, panel), /WINTIX_ERROR:.*persistence verification failed/);
}
for (const script of [structure, order]) {
  assert.doesNotMatch(script, /Widget\.index|\.index\s*=/);
  assert.doesNotMatch(script, /(applet|containment)(Id|ID)\s*=\s*[0-9]+/);
}

// Settings retain their narrow ownership model.
{
  const panel = makePanel(types, ids, {configs:[{},{},{groupingStrategy:1,unrelated:"keep"},{},{SystrayContainmentId:42}]});
  const inner = makeWidget(panel, "inner", 42, {shownItems:["shown-other"], hiddenItems:["hidden-other","org.kde.plasma.weather"], extraItems:["composition"], provider:"keep"});
  run(settings, panel, {42:inner});
  const task = panel.widgets(types[2])[0];
  assert.deepEqual(JSON.parse(JSON.stringify(task.config)), {groupingStrategy:0, unrelated:"keep", separateLaunchers:false, interactiveMute:false, launchers});
  assert.deepEqual(JSON.parse(JSON.stringify(inner.config.shownItems)), ["shown-other","org.kde.plasma.notifications","org.kde.plasma.weather","org.kde.plasma.battery"]);
  assert.deepEqual(JSON.parse(JSON.stringify(inner.config.hiddenItems)), ["hidden-other"]);
  assert.deepEqual(inner.config.extraItems, ["composition"]); assert.equal(inner.config.provider, "keep");
  assert.ok(inner.writes.every(([key]) => key !== "extraItems"));
}
// Already-correct owned settings do not write or reload; a missing inner
// containment is reported without a destructive fallback.
{
  const taskConfig = {groupingStrategy:0, separateLaunchers:false, interactiveMute:false, launchers};
  const panel = makePanel(types, ids, {configs:[{},{},taskConfig,{},{SystrayContainmentId:77}]});
  const inner = makeWidget(panel, "inner", 77, {shownItems:["org.kde.plasma.notifications","org.kde.plasma.weather","org.kde.plasma.battery"], hiddenItems:["other"]});
  assert.equal(run(settings, panel, {77:inner}), "unchanged");
  assert.deepEqual(panel.widgets(types[2])[0].writes, []); assert.equal(inner.reloads, 0);
}
{
  const panel = makePanel(types, ids, {configs:[{},{},{},{},{SystrayContainmentId:99}]});
  assert.match(run(settings, panel, {}), /WINTIX_ERROR:.*not available/);
}
console.log("Plasma panel runtime tests passed");
