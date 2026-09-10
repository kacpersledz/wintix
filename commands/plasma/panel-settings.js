// Apply only Wintix-owned settings after structure has been verified in a
// separate evaluateScript call (and therefore after an event-loop boundary).
(function () {
    try {
        const result = (function () {
    const launchers = [
        "applications:brave-browser.desktop",
        "applications:org.kde.dolphin.desktop",
        "applications:org.kde.konsole.desktop",
    ];
    const alwaysShownItems = [
        "org.kde.plasma.notifications",
        "org.kde.plasma.weather",
        "org.kde.plasma.battery",
    ];

    function asList(value) {
        if (Array.isArray(value)) return value.slice();
        if (value && typeof value === "object" &&
            typeof value.length === "number" && isFinite(value.length) &&
            value.length >= 0 && Math.floor(value.length) === value.length) {
            const result = [];
            for (let i = 0; i < value.length; ++i) result.push(String(value[i]));
            return result;
        }
        if (typeof value === "string" && value.length > 0) return value.split(",");
        return [];
    }
    function equal(actual, expected) {
        if (Array.isArray(expected)) {
            return asList(actual).join("\u0000") === expected.join("\u0000");
        }
        return String(actual) === String(expected);
    }
    function hasExactItems(actual, expected) {
        if (actual.length !== expected.length) return false;
        return hasAllItems(actual, expected);
    }
    function hasAllItems(actual, expected) {
        for (let i = 0; i < expected.length; ++i) {
            if (actual.indexOf(expected[i]) === -1) return false;
        }
        return true;
    }
    function hasAdditionalKnownItem(known) {
        for (let i = 0; i < known.length; ++i) {
            if (alwaysShownItems.indexOf(known[i]) === -1) return true;
        }
        return false;
    }
    function setOwned(widget, desired) {
        widget.currentConfigGroup = ["General"];
        let changed = false;
        const keys = Object.keys(desired);
        for (let i = 0; i < keys.length; ++i) {
            const key = keys[i];
            if (!equal(widget.readConfig(key, ""), desired[key])) {
                widget.writeConfig(key, desired[key]);
                if (!equal(widget.readConfig(key, Array.isArray(desired[key]) ? [] : ""), desired[key])) {
                    throw new Error("failed to persist " + key);
                }
                changed = true;
            }
        }
        if (changed) widget.reloadConfig();
        return changed;
    }

    let eligible = 0;
    let changed = false;
    const allPanels = panels();
    for (let i = 0; i < allPanels.length; ++i) {
        const panel = allPanels[i];
        if (panel.location !== "bottom" || Number(panel.screen) < 0) continue;
        ++eligible;
        const tasks = panel.widgets("org.kde.plasma.taskmanager");
        const trays = panel.widgets("org.kde.plasma.systemtray");
        if (tasks.length !== 1 || trays.length !== 1) {
            throw new Error("canonical panel structure is unavailable during settings phase");
        }
        changed = setOwned(tasks[0], {
            groupingStrategy: 0,
            separateLaunchers: false,
            interactiveMute: false,
            launchers: launchers,
        }) || changed;

        const tray = trays[0];
        tray.currentConfigGroup = ["General"];
        const shown = asList(tray.readConfig("shownItems", []));
        const hidden = asList(tray.readConfig("hiddenItems", []));
        const desiredShown = shown.slice();
        for (let item = 0; item < alwaysShownItems.length; ++item) {
            if (desiredShown.indexOf(alwaysShownItems[item]) === -1) desiredShown.push(alwaysShownItems[item]);
        }
        const desiredHidden = hidden.filter(function (item) {
            return alwaysShownItems.indexOf(item) === -1;
        });
        let trayChanged = false;
        if (!equal(shown, desiredShown)) {
            tray.writeConfig("shownItems", desiredShown);
            if (!equal(tray.readConfig("shownItems", []), desiredShown)) {
                throw new Error("failed to persist shownItems");
            }
            trayChanged = true;
        }
        if (!equal(hidden, desiredHidden)) {
            tray.writeConfig("hiddenItems", desiredHidden);
            if (!equal(tray.readConfig("hiddenItems", []), desiredHidden)) {
                throw new Error("failed to persist hiddenItems");
            }
            trayChanged = true;
        }
        const extraItems = asList(tray.readConfig("extraItems", []));
        const knownItems = asList(tray.readConfig("knownItems", []));
        if (hasExactItems(extraItems, alwaysShownItems) &&
            hasAdditionalKnownItem(knownItems) &&
            hasAllItems(knownItems, alwaysShownItems)) {
            tray.writeConfig("extraItems", knownItems);
            if (!equal(tray.readConfig("extraItems", []), knownItems)) {
                throw new Error("failed to persist extraItems");
            }
            trayChanged = true;
        }
        if (trayChanged) tray.reloadConfig();
        changed = trayChanged || changed;
    }
    if (eligible === 0) throw new Error("no usable bottom panel was found");
    return changed ? "changed" : "unchanged";
        }());
        print(result);
    } catch (error) {
        print("WINTIX_ERROR: " + error);
    }
}());
