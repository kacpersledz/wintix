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

function readPanelState(panel) {
    if (typeof panel.widgetById !== "function") {
        return null;
    }

    panel.currentConfigGroup = ["General"];
    const order = panel.readConfig("AppletOrder", "");
    if (typeof order !== "string" || order.length === 0) {
        return null;
    }

    const ids = order.split(";");
    const seenIds = {};
    const orderedWidgets = [];
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
        orderedWidgets.push(widget);
    }

    // Append active widgets missing from AppletOrder so interrupted previous
    // convergence can be repaired. Their enumeration order is not used for
    // visual ordering; the canonical type list below defines that order.
    const widgets = orderedWidgets.slice();
    const activeWidgets = panel.widgets();
    for (let i = 0; i < activeWidgets.length; ++i) {
        const idText = String(activeWidgets[i].id);
        if (!/^[1-9][0-9]*$/.test(idText)) {
            return null;
        }
        if (!seenIds[idText]) {
            seenIds[idText] = true;
            widgets.push(activeWidgets[i]);
        }
    }

    return { order: order, widgets: widgets };
}

function widgetOrder(widgets) {
    return widgets.map(function (widget) { return String(widget.id); }).join(";");
}

function rollbackAdditions(panel, originalOrder, additions, message) {
    try {
        panel.writeConfig("AppletOrder", originalOrder);
        if (String(panel.readConfig("AppletOrder", "")) !== originalOrder) {
            print("Wintix: panel convergence rollback failed to restore original order: " + message);
            return;
        }
    } catch (error) {
        print("Wintix: panel convergence rollback failed to restore original order: " + error);
        return;
    }

    for (let i = additions.length - 1; i >= 0; --i) {
        try {
            additions[i].remove();
        } catch (error) {
            print("Wintix: panel convergence rollback could not remove added widget: " + error);
        }
    }
    print("Wintix: panel convergence failed and was rolled back: " + message);
}

const allPanels = panels();
for (let panelIndex = 0; panelIndex < allPanels.length; ++panelIndex) {
    const panel = allPanels[panelIndex];
    if (panel.location !== "bottom" || Number(panel.screen) < 0) {
        continue;
    }

    const state = readPanelState(panel);
    if (!state) {
        continue;
    }

    const originalOrder = state.order;
    const canonicalWidgets = [];
    const additions = [];
    const removals = [];

    for (let typeIndex = 0; typeIndex < canonicalWidgetTypes.length; ++typeIndex) {
        const type = canonicalWidgetTypes[typeIndex];
        const matches = state.widgets.filter(function (widget) { return widget.type === type; });
        if (matches.length > 0) {
            canonicalWidgets.push(matches[0]);
            removals.push.apply(removals, matches.slice(1));
            continue;
        }

        const added = panel.addWidget(type);
        if (!added || added.type !== type) {
            if (added) {
                additions.push(added);
            }
            rollbackAdditions(panel, originalOrder, additions, "required widget could not be created safely");
            canonicalWidgets.length = 0;
            break;
        }
        canonicalWidgets.push(added);
        additions.push(added);
    }
    if (canonicalWidgets.length !== canonicalWidgetTypes.length) {
        continue;
    }

    for (let i = 0; i < state.widgets.length; ++i) {
        if (canonicalWidgets.indexOf(state.widgets[i]) === -1
            && removals.indexOf(state.widgets[i]) === -1) {
            removals.push(state.widgets[i]);
        }
    }

    try {
        configureTaskManager(canonicalWidgets[2]);
    } catch (error) {
        rollbackAdditions(panel, originalOrder, additions, "Task Manager configuration failed: " + error);
        continue;
    }

    const desiredOrder = widgetOrder(canonicalWidgets);
    if (desiredOrder !== originalOrder) {
        try {
            panel.writeConfig("AppletOrder", desiredOrder);
            if (String(panel.readConfig("AppletOrder", "")) !== desiredOrder) {
                rollbackAdditions(panel, originalOrder, additions, "canonical AppletOrder was not accepted");
                continue;
            }
        } catch (error) {
            rollbackAdditions(panel, originalOrder, additions, "canonical AppletOrder failed: " + error);
            continue;
        }
    }

    // Remove Icons-Only first. If its replacement cannot complete, restore the
    // original order and remove every widget added by this convergence attempt.
    const iconsOnlyWidgets = removals.filter(function (widget) {
        return widget.type === iconsOnlyTaskManager;
    });
    let migrationFailed = false;
    for (let i = 0; i < iconsOnlyWidgets.length; ++i) {
        try {
            iconsOnlyWidgets[i].remove();
        } catch (error) {
            rollbackAdditions(panel, originalOrder, additions, "Icons-Only Task Manager removal failed: " + error);
            migrationFailed = true;
            break;
        }
    }
    if (migrationFailed) {
        continue;
    }

    for (let i = 0; i < removals.length; ++i) {
        if (removals[i].type === iconsOnlyTaskManager) {
            continue;
        }
        try {
            removals[i].remove();
        } catch (error) {
            print("Wintix: panel convergence could not remove non-baseline widget: " + error);
        }
    }
}
