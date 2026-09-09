// Targeted for the Plasma 6.6 scripting API pinned by Wintix.
const alwaysShownItems = [
    "org.kde.plasma.notifications",
    "org.kde.plasma.weather",
    "org.kde.plasma.battery",
];

function asList(value) {
    if (Array.isArray(value)) {
        return value.slice();
    }
    if (typeof value === "string" && value.length > 0) {
        return value.split(",");
    }
    return [];
}

function addUnique(items, additions) {
    const result = items.slice();
    for (let i = 0; i < additions.length; ++i) {
        if (result.indexOf(additions[i]) === -1) {
            result.push(additions[i]);
        }
    }
    return result;
}

function without(items, removals) {
    return items.filter(function (item) {
        return removals.indexOf(item) === -1;
    });
}

function arraysEqual(left, right) {
    if (left.length !== right.length) {
        return false;
    }
    for (let i = 0; i < left.length; ++i) {
        if (left[i] !== right[i]) {
            return false;
        }
    }
    return true;
}

const allPanels = panels();
for (let panelIndex = 0; panelIndex < allPanels.length; ++panelIndex) {
    const trays = allPanels[panelIndex].widgets("org.kde.plasma.systemtray");
    for (let trayIndex = 0; trayIndex < trays.length; ++trayIndex) {
        const tray = trays[trayIndex];
        tray.currentConfigGroup = ["General"];
        const current = {
            shownItems: asList(tray.readConfig("shownItems", [])),
            hiddenItems: asList(tray.readConfig("hiddenItems", [])),
            extraItems: asList(tray.readConfig("extraItems", [])),
        };
        const desired = {
            shownItems: addUnique(current.shownItems, alwaysShownItems),
            hiddenItems: without(current.hiddenItems, alwaysShownItems),
            extraItems: addUnique(current.extraItems, alwaysShownItems),
        };
        const keys = Object.keys(desired);
        let changed = false;

        for (let i = 0; i < keys.length; ++i) {
            const key = keys[i];
            if (!arraysEqual(current[key], desired[key])) {
                tray.writeConfig(key, desired[key]);
                changed = true;
            }
        }
        if (changed) {
            tray.reloadConfig();
        }
    }
}
