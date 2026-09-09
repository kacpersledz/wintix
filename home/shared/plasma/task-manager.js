// Targeted for the Plasma 6.6 scripting API pinned by Wintix.
const iconsOnlyTaskManager = "org.kde.plasma.icontasks";
const taskManager = "org.kde.plasma.taskmanager";
const canonicalWidgetTypes = [
    "org.kde.plasma.kickoff",
    "org.kde.plasma.pager",
    taskManager,
    "org.kde.plasma.marginsseparator",
    "org.kde.plasma.systemtray",
    "org.kde.plasma.digitalclock",
    "org.kde.plasma.showdesktop",
];
const defaultWidgetTypes = canonicalWidgetTypes.map(function (type) {
    return type === taskManager ? iconsOnlyTaskManager : type;
});
const launchers = [
    "applications:brave-browser.desktop",
    "applications:org.kde.dolphin.desktop",
    "applications:org.kde.konsole.desktop",
];

function arraysEqual(left, right) {
    if (left.length !== right.length) {
        return false;
    }
    for (let i = 0; i < left.length; ++i) {
        if (String(left[i]) !== String(right[i])) {
            return false;
        }
    }
    return true;
}

function configValueEquals(actual, expected) {
    if (Array.isArray(expected)) {
        return Array.isArray(actual)
            ? arraysEqual(actual, expected)
            : String(actual) === expected.join(",");
    }
    return String(actual) === String(expected);
}

function configureTaskManager(widget) {
    const desired = {
        groupingStrategy: 0,
        separateLaunchers: false,
        interactiveMute: false,
        launchers: launchers,
    };
    let changed = false;

    widget.currentConfigGroup = ["General"];
    const keys = Object.keys(desired);
    for (let i = 0; i < keys.length; ++i) {
        const key = keys[i];
        if (!configValueEquals(widget.readConfig(key, ""), desired[key])) {
            widget.writeConfig(key, desired[key]);
            changed = true;
        }
    }
    if (changed) {
        widget.reloadConfig();
    }
}

function widgetTypes(widgets) {
    return widgets.map(function (widget) { return widget.type; });
}

function discoverCanonicalWidgets(widgets) {
    if (widgets.length !== canonicalWidgetTypes.length) {
        return null;
    }

    const byType = {};
    for (let i = 0; i < widgets.length; ++i) {
        const type = widgets[i].type;
        if (canonicalWidgetTypes.indexOf(type) === -1 || byType[type]) {
            return null;
        }
        byType[type] = widgets[i];
    }

    return canonicalWidgetTypes.map(function (type) { return byType[type]; });
}

function appletOrder(widgets) {
    return widgets.map(function (widget) { return String(widget.id); }).join(";");
}

const allPanels = panels();
for (let panelIndex = 0; panelIndex < allPanels.length; ++panelIndex) {
    const panel = allPanels[panelIndex];

    // A fresh panel can be exposed before its screen and complete default
    // layout are ready. Defer structural work to a later login then.
    if (panel.location !== "bottom" || Number(panel.screen) < 0) {
        continue;
    }

    const widgets = panel.widgets();
    const types = widgetTypes(widgets);

    if (arraysEqual(types, defaultWidgetTypes)) {
        const oldWidget = widgets[2];
        const replacement = panel.addWidget(taskManager);
        if (!replacement || replacement.type !== taskManager) {
            if (replacement) {
                replacement.remove();
            }
            print("Wintix: Task Manager migration skipped: replacement could not be created safely");
            continue;
        }

        const desiredWidgets = widgets.slice();
        desiredWidgets[2] = replacement;
        const desiredOrder = appletOrder(desiredWidgets);

        try {
            configureTaskManager(replacement);
        } catch (error) {
            replacement.remove();
            print("Wintix: Task Manager migration skipped: replacement configuration failed: " + error);
            continue;
        }

        try {
            panel.currentConfigGroup = ["General"];
            panel.writeConfig("AppletOrder", desiredOrder);
            if (String(panel.readConfig("AppletOrder", "")) !== desiredOrder) {
                replacement.remove();
                print("Wintix: Task Manager migration skipped: canonical panel order was not accepted");
                continue;
            }
        } catch (error) {
            replacement.remove();
            print("Wintix: Task Manager migration skipped: canonical panel order failed: " + error);
            continue;
        }

        try {
            oldWidget.remove();
        } catch (error) {
            // AppletOrder already selects the configured replacement. Keep it
            // rather than deleting the widget now occupying the canonical slot.
            print("Wintix: old Icons-Only Task Manager could not be removed: " + error);
        }
        continue;
    }

    // Canonical Wintix widgets may have the order left by the old migration.
    // Reorder this exact, unambiguous shape; leave every other shape untouched.
    const canonicalWidgets = discoverCanonicalWidgets(widgets);
    if (!canonicalWidgets) {
        continue;
    }

    const desiredOrder = appletOrder(canonicalWidgets);
    panel.currentConfigGroup = ["General"];
    if (String(panel.readConfig("AppletOrder", "")) !== desiredOrder) {
        panel.writeConfig("AppletOrder", desiredOrder);
    }
    configureTaskManager(canonicalWidgets[2]);
}
