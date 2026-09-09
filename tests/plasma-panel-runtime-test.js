#!/usr/bin/env node
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const root = process.argv[2] || process.cwd();
const taskScript = fs.readFileSync(`${root}/home/shared/plasma/task-manager.js`, "utf8");
const trayScript = fs.readFileSync(`${root}/home/shared/plasma/system-tray.js`, "utf8");

const canonicalTypes = [
    "org.kde.plasma.kickoff",
    "org.kde.plasma.pager",
    "org.kde.plasma.taskmanager",
    "org.kde.plasma.marginsseparator",
    "org.kde.plasma.systemtray",
    "org.kde.plasma.digitalclock",
    "org.kde.plasma.showdesktop",
];
const defaultTypes = canonicalTypes.map((type) =>
    type === "org.kde.plasma.taskmanager" ? "org.kde.plasma.icontasks" : type
);
const canonicalIds = [3, 4, 25, 6, 7, 20, 21];
const defaultIds = [3, 4, 5, 6, 7, 20, 21];
const launchers = [
    "applications:brave-browser.desktop",
    "applications:org.kde.dolphin.desktop",
    "applications:org.kde.konsole.desktop",
];
const ownedTaskConfig = {
    groupingStrategy: 0,
    separateLaunchers: false,
    interactiveMute: false,
    launchers,
};

function makeWidget(panel, type, id, config = {}) {
    return {
        type,
        id,
        index: -1,
        config: { ...config },
        writes: [],
        reloads: 0,
        removed: false,
        readConfig(key, fallback) { return key in this.config ? this.config[key] : fallback; },
        writeConfig(key, value) { this.config[key] = value; this.writes.push([key, value]); },
        reloadConfig() { this.reloads += 1; },
        remove() {
            panel.removalCalls.push(id);
            if (panel.removeThrowsIds.has(id)) throw new Error(`removal failed for ${id}`);
            this.removed = true;
            const ids = String(panel.config.AppletOrder || "").split(";").filter((value) => value !== String(id));
            panel.config.AppletOrder = ids.join(";");
        },
    };
}

function makePanel(types, ids, options = {}) {
    const initialOrder = Object.hasOwn(options, "appletOrder") ? options.appletOrder : ids.join(";");
    const panel = {
        location: options.location || "bottom",
        screen: options.screen === undefined ? 0 : options.screen,
        config: { AppletOrder: initialOrder },
        writes: [],
        additions: 0,
        removalCalls: [],
        removeThrowsIds: new Set(options.removeThrowsIds || []),
        nextIds: (options.nextIds || [25, 30, 31, 32, 33, 34, 35]).slice(),
        items: [],
        widgets(type) {
            const active = this.items.filter((item) => !item.removed);
            const enumerated = options.enumerationIds
                ? options.enumerationIds.map((id) => active.find((item) => item.id === id)).filter(Boolean)
                    .concat(active.filter((item) => !options.enumerationIds.includes(item.id)))
                : active;
            return type ? enumerated.filter((item) => item.type === type) : enumerated;
        },
        widgetById(id) { return this.items.find((item) => item.id === id && !item.removed); },
        addWidget(type) {
            this.additions += 1;
            const id = this.nextIds.shift();
            const widget = makeWidget(this, type, id);
            this.items.push(widget);
            this.config.AppletOrder = [this.config.AppletOrder, id].filter(Boolean).join(";");
            return widget;
        },
        readConfig(key, fallback) { return key in this.config ? this.config[key] : fallback; },
        writeConfig(key, value) {
            this.writes.push([key, value]);
            if (!(options.rejectOrder && value !== initialOrder)) this.config[key] = value;
        },
    };
    panel.items = types.map((type, index) => makeWidget(panel, type, ids[index], options.configs?.[index]));
    return panel;
}

function run(script, panel) {
    const messages = [];
    vm.runInNewContext(script, { panels: () => [panel], print: (message) => messages.push(message) });
    return messages;
}

function plain(value) {
    return JSON.parse(JSON.stringify(value));
}

function activeWidgets(panel) {
    return panel.items.filter((widget) => !widget.removed);
}

function orderedTypes(panel) {
    if (!panel.config.AppletOrder) return [];
    return panel.config.AppletOrder.split(";").map((id) => panel.widgetById(Number(id)).type);
}

function assertCanonical(panel) {
    assert.deepEqual(orderedTypes(panel), canonicalTypes);
    assert.deepEqual(activeWidgets(panel).map((widget) => widget.type).sort(), canonicalTypes.slice().sort());
}

// Fresh KDE default: replace Icons-Only and ignore widget enumeration order.
{
    const panel = makePanel(defaultTypes, defaultIds, { enumerationIds: [21, 3, 7, 5, 20, 4, 6] });
    run(taskScript, panel);
    assertCanonical(panel);
    assert.equal(panel.items.find((widget) => widget.id === 5).removed, true);
    assert.deepEqual(plain(panel.widgetById(25).config), ownedTaskConfig);
}

// The layout produced by PR #47 converges because it differs from baseline.
{
    const types = [canonicalTypes[0], canonicalTypes[1], ...canonicalTypes.slice(3), canonicalTypes[2]];
    const panel = makePanel(types, [3, 4, 6, 7, 20, 21, 25], {
        configs: [{}, {}, {}, {}, {}, {}, ownedTaskConfig],
    });
    run(taskScript, panel);
    assertCanonical(panel);
    assert.equal(panel.additions, 0);
}

// Any permutation of the canonical composition converges to baseline.
{
    const types = [canonicalTypes[4], canonicalTypes[6], canonicalTypes[2], canonicalTypes[0], canonicalTypes[5], canonicalTypes[1], canonicalTypes[3]];
    const ids = [7, 21, 25, 3, 20, 4, 6];
    const panel = makePanel(types, ids, { configs: [{}, {}, ownedTaskConfig] });
    run(taskScript, panel);
    assertCanonical(panel);
    assert.equal(panel.additions, 0);
}

// Missing canonical widgets are added.
{
    const panel = makePanel(canonicalTypes.slice(0, 6), canonicalIds.slice(0, 6), {
        configs: [{}, {}, ownedTaskConfig],
        nextIds: [40],
    });
    run(taskScript, panel);
    assertCanonical(panel);
    assert.equal(panel.additions, 1);
}

// Duplicate canonical widgets are reduced to one.
{
    const panel = makePanel([...canonicalTypes, canonicalTypes[0]], [...canonicalIds, 40], {
        configs: [{}, {}, ownedTaskConfig],
    });
    run(taskScript, panel);
    assertCanonical(panel);
    assert.equal(panel.widgetById(40), undefined);
}

// Non-baseline widgets are removed without touching canonical widget config.
{
    const clockConfig = { showSeconds: true };
    const panel = makePanel([...canonicalTypes, "org.example.custom"], [...canonicalIds, 40], {
        configs: [{}, {}, ownedTaskConfig, {}, {}, clockConfig],
    });
    run(taskScript, panel);
    assertCanonical(panel);
    assert.equal(panel.widgetById(40), undefined);
    assert.deepEqual(panel.widgetById(20).config, clockConfig);
}

// An already-canonical panel causes no structural or configuration churn.
{
    const panel = makePanel(canonicalTypes, canonicalIds, {
        configs: [{}, {}, ownedTaskConfig],
        enumerationIds: [20, 7, 3, 21, 25, 6, 4],
    });
    run(taskScript, panel);
    assert.deepEqual(panel.writes, []);
    assert.equal(panel.additions, 0);
    assert.deepEqual(panel.removalCalls, []);
    assert.deepEqual(panel.widgetById(25).writes, []);
    assert.equal(panel.widgetById(25).reloads, 0);
}

// Invalid screen, empty/malformed order, and unresolved IDs safely no-op.
for (const options of [
    { screen: -1 },
    { appletOrder: "" },
    { appletOrder: "3;4;bad;6;7;20;21" },
    { appletOrder: "3;4;5;6;7;20;99" },
    { appletOrder: "3;4;5;6;7;20;20" },
]) {
    const panel = makePanel(defaultTypes, defaultIds, options);
    run(taskScript, panel);
    assert.equal(panel.additions, 0);
    assert.deepEqual(panel.writes, []);
    assert.deepEqual(panel.removalCalls, []);
}

// A rejected order restores the original state and removes additions.
{
    const panel = makePanel(defaultTypes, defaultIds, { rejectOrder: true });
    run(taskScript, panel);
    assert.equal(panel.config.AppletOrder, defaultIds.join(";"));
    assert.equal(panel.widgetById(5).removed, false);
    assert.equal(panel.items.find((widget) => widget.id === 25).removed, true);
}

// Icons-Only removal failure also rolls back composition and order.
{
    const panel = makePanel(defaultTypes, defaultIds, { removeThrowsIds: [5] });
    const messages = run(taskScript, panel);
    assert.equal(panel.config.AppletOrder, defaultIds.join(";"));
    assert.equal(panel.widgetById(5).removed, false);
    assert.equal(panel.items.find((widget) => widget.id === 25).removed, true);
    assert.match(messages.join("\n"), /failed and was rolled back/);
}

// Existing Task Manager configuration changes only owned values and reloads once.
{
    const taskConfig = { groupingStrategy: 1, unrelated: "preserved" };
    const panel = makePanel(canonicalTypes, canonicalIds, { configs: [{}, {}, taskConfig] });
    run(taskScript, panel);
    const task = panel.widgetById(25);
    assert.deepEqual(plain(task.config), { ...ownedTaskConfig, unrelated: "preserved" });
    assert.equal(task.reloads, 1);
    assert.deepEqual(task.writes.map(([key]) => key).sort(), Object.keys(ownedTaskConfig).sort());
}

function runTray(config) {
    const panel = { removalCalls: [], removeThrowsIds: new Set(), config: { AppletOrder: "7" } };
    const tray = makeWidget(panel, "org.kde.plasma.systemtray", 7, config);
    panel.widgets = (type) => type === tray.type ? [tray] : [];
    run(trayScript, panel);
    return tray;
}

{
    const tray = runTray({
        shownItems: ["unrelated", "org.kde.plasma.notifications", "org.kde.plasma.weather", "org.kde.plasma.battery"],
        hiddenItems: ["hidden-unrelated"],
        extraItems: ["extra-unrelated", "org.kde.plasma.notifications", "org.kde.plasma.weather", "org.kde.plasma.battery"],
    });
    assert.deepEqual(tray.writes, []);
    assert.equal(tray.reloads, 0);
}

{
    const tray = runTray({
        shownItems: ["unrelated"],
        hiddenItems: ["hidden-unrelated", "org.kde.plasma.weather"],
        extraItems: ["extra-unrelated"],
    });
    assert.equal(tray.reloads, 1);
    assert.deepEqual(plain(tray.config.hiddenItems), ["hidden-unrelated"]);
    assert.deepEqual(plain(tray.config.shownItems.slice(0, 1)), ["unrelated"]);
    assert.deepEqual(plain(tray.config.extraItems.slice(0, 1)), ["extra-unrelated"]);
}

console.log("Plasma panel runtime tests passed");
