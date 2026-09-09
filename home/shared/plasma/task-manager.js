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
const brokenWidgetTypes = [
    canonicalWidgetTypes[0],
    canonicalWidgetTypes[1],
    canonicalWidgetTypes[3],
    canonicalWidgetTypes[4],
    canonicalWidgetTypes[5],
    canonicalWidgetTypes[6],
    canonicalWidgetTypes[2],
];
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

function readOrderedWidgets(panel) {
    if (typeof panel.widgetById !== "function") {
        return null;
    }

    panel.currentConfigGroup = ["General"];
    const rawOrder = panel.readConfig("AppletOrder", "");
    if (typeof rawOrder !== "string" || rawOrder.length === 0) {
        return null;
    }

    const ids = rawOrder.split(";");
    const seenIds = {};
    const widgets = [];
    for (let i = 0; i < ids.length; ++i) {
        const idText = ids[i];
        if (!/^[1-9][0-9]*$/.test(idText) || seenIds[idText]) {
            return null;
        }
        const widget = panel.widgetById(Number(idText));
        if (!widget || String(widget.id) !== idText) {
            return null;
        }
        seenIds[idText] = true;
        widgets.push(widget);
    }

    // AppletOrder must describe the complete panel, not a subset that happens
    // to resemble a supported layout. Enumeration order is irrelevant here.
    const allWidgets = panel.widgets();
    if (allWidgets.length !== widgets.length) {
        return null;
    }
    const enumeratedIds = {};
    for (let i = 0; i < allWidgets.length; ++i) {
        const idText = String(allWidgets[i].id);
        if (!seenIds[idText] || enumeratedIds[idText]) {
            return null;
        }
        enumeratedIds[idText] = true;
    }

    return {
        order: rawOrder,
        widgets: widgets,
        types: widgets.map(function (widget) { return widget.type; }),
    };
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

    const ordered = readOrderedWidgets(panel);
    if (!ordered) {
        continue;
    }

    if (arraysEqual(ordered.types, defaultWidgetTypes)) {
        const originalOrder = ordered.order;
        const oldWidget = ordered.widgets[2];
        const replacement = panel.addWidget(taskManager);
        if (!replacement || replacement.type !== taskManager) {
            if (replacement) {
                replacement.remove();
            }
            print("Wintix: Task Manager migration skipped: replacement could not be created safely");
            continue;
        }

        const desiredWidgets = ordered.widgets.slice();
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
            try {
                panel.writeConfig("AppletOrder", originalOrder);
                if (String(panel.readConfig("AppletOrder", "")) !== originalOrder) {
                    print("Wintix: Task Manager migration rollback failed to restore original order: " + error);
                    continue;
                }
            } catch (rollbackError) {
                print("Wintix: Task Manager migration rollback failed to restore original order: " + rollbackError);
                continue;
            }
            try {
                replacement.remove();
                print("Wintix: Task Manager migration failed and was rolled back: " + error);
            } catch (rollbackError) {
                print("Wintix: Task Manager migration rollback could not remove replacement: " + rollbackError);
            }
        }
        continue;
    }

    if (arraysEqual(ordered.types, canonicalWidgetTypes)) {
        configureTaskManager(ordered.widgets[2]);
        continue;
    }

    // Repair only the exact ordering produced by PR #47. Every other semantic
    // shape is user/custom state and remains untouched.
    if (arraysEqual(ordered.types, brokenWidgetTypes)) {
        const canonicalWidgets = [
            ordered.widgets[0],
            ordered.widgets[1],
            ordered.widgets[6],
            ordered.widgets[2],
            ordered.widgets[3],
            ordered.widgets[4],
            ordered.widgets[5],
        ];
        const desiredOrder = appletOrder(canonicalWidgets);
        panel.writeConfig("AppletOrder", desiredOrder);
        if (String(panel.readConfig("AppletOrder", "")) !== desiredOrder) {
            print("Wintix: canonical panel order repair was not accepted");
            continue;
        }
        configureTaskManager(canonicalWidgets[2]);
    }
}
