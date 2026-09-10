// Reconcile the live Plasma 6 bottom panel. Runtime IDs are deliberately
// discovered from Plasma; plugin IDs are the only stable identities here.
(function () {
    try {
        const result = (function () {
    const canonicalWidgetTypes = [
        "org.kde.plasma.kickoff",
        "org.kde.plasma.pager",
        "org.kde.plasma.taskmanager",
        "org.kde.plasma.marginsseparator",
        "org.kde.plasma.systemtray",
        "org.kde.plasma.digitalclock",
        "org.kde.plasma.showdesktop",
    ];

    function widgetId(widget) {
        const id = String(widget.id);
        if (!/^[1-9][0-9]*$/.test(id)) {
            throw new Error("Plasma returned an invalid widget ID");
        }
        return id;
    }

    function inventory(panel) {
        panel.currentConfigGroup = ["General"];
        const order = String(panel.readConfig("AppletOrder", ""));
        const byId = {};
        const result = [];

        // AppletOrder determines which existing duplicate is retained. Append
        // widgets absent from the order only to make inventory complete.
        if (order.length > 0) {
            const ids = order.split(";");
            for (let i = 0; i < ids.length; ++i) {
                if (!/^[1-9][0-9]*$/.test(ids[i]) || byId[ids[i]]) continue;
                const widget = panel.widgetById(Number(ids[i]));
                if (!widget || widgetId(widget) !== ids[i]) continue;
                byId[ids[i]] = true;
                result.push(widget);
            }
        }
        const widgets = panel.widgets();
        for (let i = 0; i < widgets.length; ++i) {
            const id = widgetId(widgets[i]);
            if (!byId[id]) {
                byId[id] = true;
                result.push(widgets[i]);
            }
        }
        return { order: order, widgets: result };
    }

    const allPanels = panels();
    let eligible = 0;
    let changed = false;
    for (let panelIndex = 0; panelIndex < allPanels.length; ++panelIndex) {
        const panel = allPanels[panelIndex];
        if (panel.location !== "bottom" || Number(panel.screen) < 0) continue;
        ++eligible;

        const state = inventory(panel);
        const selected = [];
        for (let typeIndex = 0; typeIndex < canonicalWidgetTypes.length; ++typeIndex) {
            const type = canonicalWidgetTypes[typeIndex];
            const existing = state.widgets.filter(function (widget) { return widget.type === type; });
            if (existing.length > 0) {
                selected.push(existing[0]);
            } else {
                const added = panel.addWidget(type);
                if (!added || added.type !== type) throw new Error("could not add " + type);
                selected.push(added);
                changed = true;
            }
        }

        // Plasma saves its current live layout when a widget is removed. Do
        // every removal in this phase, before the separate order phase.
        for (let i = 0; i < state.widgets.length; ++i) {
            if (selected.indexOf(state.widgets[i]) === -1) {
                state.widgets[i].remove();
                changed = true;
            }
        }

        const survivors = inventory(panel).widgets;
        if (survivors.length !== canonicalWidgetTypes.length) {
            throw new Error("unexpected widgets survived structural reconciliation");
        }
        for (let typeIndex = 0; typeIndex < canonicalWidgetTypes.length; ++typeIndex) {
            const matches = survivors.filter(function (widget) {
                return widget.type === canonicalWidgetTypes[typeIndex];
            });
            if (matches.length !== 1) {
                throw new Error("canonical widget survival verification failed");
            }
        }
    }
    if (eligible === 0) throw new Error("no usable bottom panel was found");
    return changed ? "changed" : "unchanged";
        }());
        print(result);
    } catch (error) {
        print("WINTIX_ERROR: " + error);
    }
}());
