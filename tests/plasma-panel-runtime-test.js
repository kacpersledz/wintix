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
const defaultIds = [3, 4, 5, 6, 7, 20, 21];
const ownedTaskConfig = {
    groupingStrategy: 0,
    separateLaunchers: false,
    interactiveMute: false,
    launchers: [
        "applications:brave-browser.desktop",
        "applications:org.kde.dolphin.desktop",
        "applications:org.kde.konsole.desktop",
    ],
};

function makeWidget(type, id, config = {}, options = {}) {
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
            if (options.removeThrows) throw new Error(`removal failed for ${id}`);
            this.removed = true;
        },
    };
}

function makePanel(types, ids, options = {}) {
    const panel = {
        location: options.location || "bottom",
        screen: options.screen === undefined ? 0 : options.screen,
        items: types.map((type, index) => makeWidget(type, ids[index], options.configs?.[index], {
            removeThrows: options.removeThrowsId === ids[index],
        })),
        config: { AppletOrder: Object.hasOwn(options, "appletOrder") ? options.appletOrder : ids.join(";") },
        writes: [],
        additions: 0,
        widgets(type) {
            const active = this.items.filter((item) => !item.removed);
            if (type) return active.filter((item) => item.type === type);
            if (!options.enumerationIds) return active;
            const enumerated = options.enumerationIds
                .map((id) => active.find((item) => item.id === id))
                .filter(Boolean);
            return enumerated.concat(active.filter((item) => !options.enumerationIds.includes(item.id)));
        },
        widgetById(id) { return this.items.find((item) => item.id === id && !item.removed); },
        addWidget(type) {
            this.additions += 1;
            const widget = makeWidget(type, options.newId || 25);
            this.items.push(widget);
            return widget;
        },
        readConfig(key, fallback) { return key in this.config ? this.config[key] : fallback; },
        writeConfig(key, value) {
            this.writes.push([key, value]);
            if (!options.rejectOrder) this.config[key] = value;
        },
    };
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

{
    const panel = makePanel(defaultTypes, defaultIds, { enumerationIds: [21, 3, 7, 5, 20, 4, 6] });
    run(taskScript, panel);
    assert.equal(panel.additions, 1);
    assert.equal(panel.items[2].removed, true);
    assert.equal(panel.config.AppletOrder, "3;4;25;6;7;20;21");
    const replacement = panel.items[7];
    assert.deepEqual(plain(replacement.config), ownedTaskConfig);
    assert.equal(replacement.reloads, 1);
    assert.deepEqual(replacement.writes.map(([key]) => key).sort(), Object.keys(ownedTaskConfig).sort());
}

{
    const panel = makePanel(canonicalTypes, [3, 4, 25, 6, 7, 20, 21], {
        configs: [{}, {}, ownedTaskConfig],
        enumerationIds: [20, 7, 3, 21, 25, 6, 4],
    });
    run(taskScript, panel);
    assert.equal(panel.additions, 0);
    assert.deepEqual(panel.writes, []);
    assert.deepEqual(panel.items[2].writes, []);
    assert.equal(panel.items[2].reloads, 0);
}

{
    const brokenTypes = [canonicalTypes[0], canonicalTypes[1], ...canonicalTypes.slice(3), canonicalTypes[2]];
    const panel = makePanel(brokenTypes, [3, 4, 6, 7, 20, 21, 25], {
        configs: [{}, {}, {}, {}, {}, {}, ownedTaskConfig],
    });
    run(taskScript, panel);
    assert.equal(panel.additions, 0);
    assert.equal(panel.config.AppletOrder, "3;4;25;6;7;20;21");
}

{
    const panel = makePanel([...canonicalTypes, "org.example.custom"], [...defaultIds, 30]);
    run(taskScript, panel);
    assert.equal(panel.additions, 0);
    assert.deepEqual(panel.writes, []);
}

{
    const panel = makePanel(defaultTypes, defaultIds, { screen: -1 });
    run(taskScript, panel);
    assert.equal(panel.additions, 0);
    assert.deepEqual(panel.writes, []);
}

{
    const panel = makePanel(defaultTypes, defaultIds, { rejectOrder: true });
    run(taskScript, panel);
    assert.equal(panel.items[2].removed, false);
    assert.equal(panel.items[7].removed, true);
}

{
    const panel = makePanel(defaultTypes, defaultIds, { removeThrowsId: 5 });
    const messages = run(taskScript, panel);
    assert.equal(panel.config.AppletOrder, "3;4;5;6;7;20;21");
    assert.equal(panel.items[2].removed, false);
    assert.equal(panel.items[7].removed, true);
    assert.match(messages.join("\n"), /migration failed and was rolled back/);
}

for (const appletOrder of ["", "3;4;bad;6;7;20;21", "3;4;5;6;7;20;99", "3;4;5;6;7;20;20"]) {
    const panel = makePanel(defaultTypes, defaultIds, { appletOrder });
    run(taskScript, panel);
    assert.equal(panel.additions, 0);
    assert.deepEqual(panel.writes, []);
}

function runTray(config) {
    const tray = makeWidget("org.kde.plasma.systemtray", 7, config);
    const panel = { widgets: (type) => type === tray.type ? [tray] : [] };
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
