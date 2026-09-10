// Persist canonical bottom-panel ordering after Plasma's deferred structural
// layout saves have had an event-loop turn to settle.
(function () {
    try {
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
            if (!/^[1-9][0-9]*$/.test(id)) throw new Error("Plasma returned an invalid widget ID");
            return id;
        }

        let eligible = 0;
        let changed = false;
        const allPanels = panels();
        for (let panelIndex = 0; panelIndex < allPanels.length; ++panelIndex) {
            const panel = allPanels[panelIndex];
            if (panel.location !== "bottom" || Number(panel.screen) < 0) continue;
            ++eligible;

            const widgets = panel.widgets();
            if (widgets.length !== canonicalWidgetTypes.length) {
                throw new Error("canonical panel composition is unavailable during order phase");
            }
            const ids = [];
            for (let typeIndex = 0; typeIndex < canonicalWidgetTypes.length; ++typeIndex) {
                const matches = widgets.filter(function (widget) {
                    return widget.type === canonicalWidgetTypes[typeIndex];
                });
                if (matches.length !== 1) throw new Error("canonical widget is missing or duplicated during order phase");
                ids.push(widgetId(matches[0]));
            }

            const desiredOrder = ids.join(";");
            panel.currentConfigGroup = ["General"];
            if (String(panel.readConfig("AppletOrder", "")) !== desiredOrder) {
                panel.writeConfig("AppletOrder", desiredOrder);
                changed = true;
            }
            if (String(panel.readConfig("AppletOrder", "")) !== desiredOrder) {
                throw new Error("canonical AppletOrder persistence verification failed");
            }
        }
        if (eligible === 0) throw new Error("no usable bottom panel was found");
        print(changed ? "changed" : "unchanged");
    } catch (error) {
        print("WINTIX_ERROR: " + error);
    }
}());
