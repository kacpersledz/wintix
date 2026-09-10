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

function makeWidget(panel, type, id, config = {}, options = {}) {
  return { type, id, config: {...config}, writes: [], reloads: 0, removed: false,
    readConfig(key, fallback) { return Object.hasOwn(this.config, key) ? this.config[key] : fallback; },
    writeConfig(key, value) {
      this.writes.push([key, value]);
      if (!options.rejectConfigKeys?.includes(key)) this.config[key] = value;
    },
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
      const added = makeWidget(this, type, this.nextId++, {}, options);
      this.items.push(added);
      this.visualIds.push(added.id);
      this.pendingDeferredSave = true;
      return added;
    },
  };
  panel.items = initialTypes.map((type, index) => makeWidget(panel, type, initialIds[index], options.configs?.[index], options));
  return panel;
}
function run(script, panel) {
  const output = [];
  vm.runInNewContext(script, {
    panels: () => [panel],
    print: value => output.push(String(value)),
  });
  assert.equal(output.length, 1);
  return output[0];
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

const managedTrayItems = ["org.kde.plasma.notifications", "org.kde.plasma.weather", "org.kde.plasma.battery"];
const healthyKnownItems = ["org.kde.plasma.clipboard", ...managedTrayItems, "org.kde.plasma.bluetooth"];
function qmlList(values) {
  const proxy = {length: values.length};
  values.forEach((value, index) => { proxy[index] = value; });
  Object.defineProperties(proxy, {
    constructor: {value: Array},
    toJSON: {value: () => values.slice()},
    toString: {value: () => values.join(",")},
  });
  return proxy;
}
function settingsPanel(taskConfig, trayConfig, options = {}) {
  return makePanel(types, ids, {...options, configs:[{},{},taskConfig,{},{...trayConfig}]});
}

// The Plasma 6.6 System Tray top-level widget directly owns tray settings.
// Visibility converges while unrelated composition and discovery settings stay intact.
{
  const panel = settingsPanel(
    {groupingStrategy:1, unrelated:"keep"},
    {
      shownItems:["shown-other"],
      hiddenItems:["hidden-other", "org.kde.plasma.weather"],
      extraItems:["composition-a", "composition-b"],
      knownItems:healthyKnownItems,
    },
  );
  assert.equal(run(settings, panel), "changed");
  const task = panel.widgets(types[2])[0];
  const tray = panel.widgets(types[4])[0];
  assert.deepEqual(JSON.parse(JSON.stringify(task.config)), {groupingStrategy:0, unrelated:"keep", separateLaunchers:false, interactiveMute:false, launchers});
  assert.deepEqual(JSON.parse(JSON.stringify(tray.config.shownItems)), ["shown-other", ...managedTrayItems]);
  assert.deepEqual(JSON.parse(JSON.stringify(tray.config.hiddenItems)), ["hidden-other"]);
  assert.deepEqual(JSON.parse(JSON.stringify(tray.config.extraItems)), ["composition-a", "composition-b"]);
  assert.deepEqual(JSON.parse(JSON.stringify(tray.config.knownItems)), healthyKnownItems);
  assert.ok(tray.writes.every(([key]) => key !== "extraItems"));
}
// Qt/QML list proxies are not native JavaScript arrays, but must still be parsed.
// The precise legacy fingerprint repairs composition once, from knownItems order.
{
  const knownItems = [
    "org.kde.plasma.clipboard",
    "org.kde.plasma.notifications",
    "org.kde.plasma.battery",
    "org.kde.plasma.bluetooth",
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.volume",
    "org.kde.plasma.weather",
  ];
  const panel = settingsPanel(
    {groupingStrategy:0, separateLaunchers:false, interactiveMute:false, launchers},
    {
      shownItems:qmlList(managedTrayItems),
      hiddenItems:qmlList(["other"]),
      extraItems:qmlList(managedTrayItems),
      knownItems:qmlList(knownItems),
    },
  );
  const tray = panel.widgets(types[4])[0];
  for (const key of ["shownItems", "hiddenItems", "extraItems", "knownItems"]) {
    assert.equal(Array.isArray(tray.config[key]), false);
    assert.equal(typeof tray.config[key], "object");
    assert.equal(typeof tray.config[key].length, "number");
  }
  assert.equal(run(settings, panel), "changed");
  assert.deepEqual(JSON.parse(JSON.stringify(tray.config.extraItems)), knownItems);
  assert.deepEqual(JSON.parse(JSON.stringify(tray.writes.filter(([key]) => key === "extraItems"))), [["extraItems", knownItems]]);
  assert.equal(tray.reloads, 1);
  const writes = tray.writes.length;
  assert.equal(run(settings, panel), "unchanged");
  assert.equal(tray.writes.length, writes); assert.equal(tray.reloads, 1);
}
// Every Wintix-owned write must be observable immediately through readConfig.
{
  const healthyTray = {shownItems:managedTrayItems, hiddenItems:["other"], extraItems:["composition"], knownItems:healthyKnownItems};
  for (const [key, value] of [
    ["groupingStrategy", 1],
    ["separateLaunchers", true],
    ["interactiveMute", true],
    ["launchers", []],
  ]) {
    const taskConfig = {groupingStrategy:0, separateLaunchers:false, interactiveMute:false, launchers};
    taskConfig[key] = value;
    const taskWriteFailure = settingsPanel(taskConfig, healthyTray, {rejectConfigKeys:[key]});
    assert.match(run(settings, taskWriteFailure), new RegExp("WINTIX_ERROR:.*failed to persist " + key));
  }

  const shownWriteFailure = settingsPanel(
    {groupingStrategy:0, separateLaunchers:false, interactiveMute:false, launchers},
    {...healthyTray, shownItems:["other"]}, {rejectConfigKeys:["shownItems"]},
  );
  assert.match(run(settings, shownWriteFailure), /WINTIX_ERROR:.*failed to persist shownItems/);

  const hiddenWriteFailure = settingsPanel(
    {groupingStrategy:0, separateLaunchers:false, interactiveMute:false, launchers},
    {...healthyTray, hiddenItems:["other", "org.kde.plasma.weather"]}, {rejectConfigKeys:["hiddenItems"]},
  );
  assert.match(run(settings, hiddenWriteFailure), /WINTIX_ERROR:.*failed to persist hiddenItems/);

  const migrationWriteFailure = settingsPanel(
    {groupingStrategy:0, separateLaunchers:false, interactiveMute:false, launchers},
    {shownItems:managedTrayItems, hiddenItems:["other"], extraItems:managedTrayItems, knownItems:healthyKnownItems},
    {rejectConfigKeys:["extraItems"]},
  );
  assert.match(run(settings, migrationWriteFailure), /WINTIX_ERROR:.*failed to persist extraItems/);
}
// Custom and ambiguous composition states are not Wintix-owned.
for (const [extraItems, knownItems] of [
  [[...managedTrayItems, "org.kde.plasma.clipboard"], healthyKnownItems],
  [["org.example.custom"], healthyKnownItems],
  [[], healthyKnownItems],
  [managedTrayItems, managedTrayItems],
]) {
  const panel = settingsPanel(
    {groupingStrategy:0, separateLaunchers:false, interactiveMute:false, launchers},
    {shownItems:managedTrayItems, hiddenItems:["other"], extraItems, knownItems},
  );
  const tray = panel.widgets(types[4])[0];
  assert.equal(run(settings, panel), "unchanged");
  assert.deepEqual(JSON.parse(JSON.stringify(tray.config.extraItems)), extraItems);
  assert.ok(tray.writes.every(([key]) => key !== "extraItems")); assert.equal(tray.reloads, 0);
}
// Already-correct owned Task Manager and healthy tray state are a full no-op.
{
  const panel = settingsPanel(
    {groupingStrategy:0, separateLaunchers:false, interactiveMute:false, launchers},
    {shownItems:managedTrayItems, hiddenItems:["other"], extraItems:["composition"], knownItems:healthyKnownItems},
  );
  const task = panel.widgets(types[2])[0];
  const tray = panel.widgets(types[4])[0];
  assert.equal(run(settings, panel), "unchanged");
  assert.deepEqual(task.writes, []); assert.deepEqual(tray.writes, []); assert.equal(task.reloads, 0); assert.equal(tray.reloads, 0);
}
console.log("Plasma panel runtime tests passed");
