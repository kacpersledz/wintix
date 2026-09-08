// Targeted for the Plasma 6.6 scripting API pinned by Wintix.
const alwaysShownItems = [
    "org.kde.plasma.notifications",
    "org.kde.plasma.weather",
    "org.kde.plasma.battery",
];

function asList(value) {
    if (value instanceof Array) {
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

const allPanels = panels();
for (let panelIndex = 0; panelIndex < allPanels.length; ++panelIndex) {
    const trays = allPanels[panelIndex].widgets("org.kde.plasma.systemtray");
    for (let trayIndex = 0; trayIndex < trays.length; ++trayIndex) {
        // In Plasma 6.6 the System Tray applet is itself a custom embedded
        // containment, so its own General group owns the visibility lists.
        const tray = trays[trayIndex];
        tray.currentConfigGroup = ["General"];
        const shown = asList(tray.readConfig("shownItems", []));
        const hidden = asList(tray.readConfig("hiddenItems", []));
        const extra = asList(tray.readConfig("extraItems", []));

        // Merge only the three owned entries. All unrelated tray state stays intact.
        tray.writeConfig("shownItems", addUnique(shown, alwaysShownItems));
        tray.writeConfig("hiddenItems", without(hidden, alwaysShownItems));
        tray.writeConfig("extraItems", addUnique(extra, alwaysShownItems));
        tray.reloadConfig();
    }
}
