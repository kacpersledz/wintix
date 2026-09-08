// Targeted for the Plasma 6.6 scripting API pinned by Wintix.
const iconsOnlyTaskManager = "org.kde.plasma.icontasks";
const taskManager = "org.kde.plasma.taskmanager";
const launchers = [
    "applications:brave-browser.desktop",
    "applications:org.kde.dolphin.desktop",
    "applications:org.kde.konsole.desktop",
];

function copyConfigGroup(source, target, group) {
    source.currentConfigGroup = group;
    target.currentConfigGroup = group;

    const keys = source.configKeys.slice();
    for (let i = 0; i < keys.length; ++i) {
        target.writeConfig(keys[i], source.readConfig(keys[i]));
    }

    const groups = source.configGroups.slice();
    for (let i = 0; i < groups.length; ++i) {
        copyConfigGroup(source, target, group.concat([groups[i]]));
    }
}

function configureTaskManager(widget) {
    widget.currentConfigGroup = ["General"];
    widget.writeConfig("groupingStrategy", 0);
    widget.writeConfig("separateLaunchers", false);
    widget.writeConfig("interactiveMute", false);
    widget.writeConfig("launchers", launchers);
    widget.reloadConfig();
}

const allPanels = panels();
for (let panelIndex = 0; panelIndex < allPanels.length; ++panelIndex) {
    const panel = allPanels[panelIndex];
    const normalWidgets = panel.widgets(taskManager);
    const iconsOnlyWidgets = panel.widgets(iconsOnlyTaskManager);

    // A single existing normal Task Manager is unambiguous and safe to manage.
    if (normalWidgets.length === 1 && iconsOnlyWidgets.length === 0) {
        configureTaskManager(normalWidgets[0]);
        continue;
    }

    // Only convert the default, unambiguous one-widget shape. If a panel has a
    // custom mix of task managers, leave it alone instead of guessing.
    if (normalWidgets.length !== 0 || iconsOnlyWidgets.length !== 1) {
        continue;
    }

    const oldWidget = iconsOnlyWidgets[0];
    const oldIndex = oldWidget.index;
    const oldShortcut = oldWidget.globalShortcut;
    const replacement = panel.addWidget(taskManager);

    if (!replacement) {
        print("Wintix: Task Manager migration skipped: replacement could not be created");
        continue;
    }

    if (replacement.type !== taskManager) {
        const unexpectedType = replacement.type;
        replacement.remove();
        print("Wintix: Task Manager migration skipped: unexpected replacement type " + unexpectedType);
        continue;
    }

    try {
        // Preserve user-owned Task Manager options while changing widget type.
        copyConfigGroup(oldWidget, replacement, []);
        replacement.globalShortcut = oldShortcut;
        configureTaskManager(replacement);
        replacement.index = oldIndex;

        // Plasma 6.6 only logs when reordering fails, so verify the setter's
        // result before deleting the original widget.
        const actualIndex = replacement.index;
        if (actualIndex !== oldIndex) {
            replacement.remove();
            print("Wintix: Task Manager migration skipped: could not preserve panel index " + oldIndex);
            continue;
        }

        oldWidget.remove();
    } catch (error) {
        // Never leave a duplicate behind when migration cannot complete.
        replacement.remove();
        print("Wintix: Task Manager migration skipped: " + error);
    }
}
