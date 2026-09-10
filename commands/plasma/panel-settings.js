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
        if (typeof value === "string" && value.length > 0) return value.split(",");
        return [];
    }
    function equal(actual, expected) {
        if (Array.isArray(expected)) {
            return asList(actual).join("\u0000") === expected.join("\u0000");
        }
        return String(actual) === String(expected);
    }
    function setOwned(widget, desired) {
        widget.currentConfigGroup = ["General"];
        let changed = false;
        const keys = Object.keys(desired);
        for (let i = 0; i < keys.length; ++i) {
            const key = keys[i];
            if (!equal(widget.readConfig(key, ""), desired[key])) {
                widget.writeConfig(key, desired[key]);
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

        trays[0].currentConfigGroup = ["General"];
        const containmentId = Number(trays[0].readConfig("SystrayContainmentId", -1));
        const systray = containmentId >= 0 ? desktopById(containmentId) : null;
        if (!systray) throw new Error("System Tray inner containment is not available");
        systray.currentConfigGroup = ["General"];
        const shown = asList(systray.readConfig("shownItems", []));
        const hidden = asList(systray.readConfig("hiddenItems", []));
        const desiredShown = shown.slice();
        for (let item = 0; item < alwaysShownItems.length; ++item) {
            if (desiredShown.indexOf(alwaysShownItems[item]) === -1) desiredShown.push(alwaysShownItems[item]);
        }
        const desiredHidden = hidden.filter(function (item) {
            return alwaysShownItems.indexOf(item) === -1;
        });
        let trayChanged = false;
        if (!equal(shown, desiredShown)) {
            systray.writeConfig("shownItems", desiredShown);
            trayChanged = true;
        }
        if (!equal(hidden, desiredHidden)) {
            systray.writeConfig("hiddenItems", desiredHidden);
            trayChanged = true;
        }
        if (trayChanged) systray.reloadConfig();
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
