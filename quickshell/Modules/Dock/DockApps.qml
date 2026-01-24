import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Common
import qs.Services

Item {
    id: root

    property var contextMenu: null
    property bool requestDockShow: false
    property int pinnedAppCount: 0
    property bool groupByApp: false
    property bool isVertical: false
    property var dockScreen: null
    property real iconSize: 40
    property int draggedIndex: -1
    property int dropTargetIndex: -1
    property bool suppressShiftAnimation: false

    clip: false
    implicitWidth: isVertical ? appLayout.height : appLayout.width
    implicitHeight: isVertical ? appLayout.width : appLayout.height

    function dockIndexToPinnedIndex(dockIndex) {
        if (!SettingsData.dockLauncherEnabled) {
            return dockIndex;
        }

        const launcherPos = SessionData.dockLauncherPosition;
        if (dockIndex < launcherPos) {
            return dockIndex;
        } else {
            return dockIndex - 1;
        }
    }

    function movePinnedApp(fromDockIndex, toDockIndex) {
        const fromPinnedIndex = dockIndexToPinnedIndex(fromDockIndex);
        const toPinnedIndex = dockIndexToPinnedIndex(toDockIndex);

        if (fromPinnedIndex === toPinnedIndex) {
            return;
        }

        const currentPinned = [...(SessionData.pinnedApps || [])];
        if (fromPinnedIndex < 0 || fromPinnedIndex >= currentPinned.length || toPinnedIndex < 0 || toPinnedIndex >= currentPinned.length) {
            return;
        }

        const movedApp = currentPinned.splice(fromPinnedIndex, 1)[0];
        currentPinned.splice(toPinnedIndex, 0, movedApp);

        SessionData.setPinnedApps(currentPinned);
    }

    Item {
        id: appLayout
        width: layoutFlow.width
        height: layoutFlow.height
        anchors.horizontalCenter: root.isVertical ? undefined : parent.horizontalCenter
        anchors.verticalCenter: root.isVertical ? parent.verticalCenter : undefined
        anchors.left: root.isVertical && SettingsData.dockPosition === SettingsData.Position.Left ? parent.left : undefined
        anchors.right: root.isVertical && SettingsData.dockPosition === SettingsData.Position.Right ? parent.right : undefined
        anchors.top: root.isVertical ? undefined : parent.top

        Flow {
            id: layoutFlow
            flow: root.isVertical ? Flow.TopToBottom : Flow.LeftToRight
            spacing: Math.min(8, Math.max(4, root.iconSize * 0.08))

            Repeater {
                id: repeater

                property var dockItems: []

                model: ScriptModel {
                    values: repeater.dockItems
                    objectProp: "uniqueKey"
                }

                Component.onCompleted: updateModel()

                function isOnScreen(toplevel, screenName) {
                    if (!toplevel.screens)
                        return false;
                    for (let i = 0; i < toplevel.screens.length; i++) {
                        if (toplevel.screens[i]?.name === screenName)
                            return true;
                    }
                    return false;
                }

                function getCoreAppData(appId) {
                    if (typeof AppSearchService === "undefined")
                        return null;

                    const coreApps = AppSearchService.coreApps || [];
                    for (let i = 0; i < coreApps.length; i++) {
                        const app = coreApps[i];
                        if (app.builtInPluginId === appId) {
                            return app;
                        }
                    }
                    return null;
                }

                function getCoreAppDataByTitle(windowTitle) {
                    if (typeof AppSearchService === "undefined" || !windowTitle)
                        return null;

                    const coreApps = AppSearchService.coreApps || [];
                    for (let i = 0; i < coreApps.length; i++) {
                        const app = coreApps[i];
                        if (app.name === windowTitle) {
                            return app;
                        }
                    }
                    return null;
                }

                function insertLauncher(targetArray) {
                    if (!SettingsData.dockLauncherEnabled)
                        return;

                    const launcherItem = {
                        uniqueKey: "launcher_button",
                        type: "launcher",
                        appId: "__LAUNCHER__",
                        toplevel: null,
                        isPinned: true,
                        isRunning: false
                    };

                    const pos = Math.max(0, Math.min(SessionData.dockLauncherPosition, targetArray.length));
                    targetArray.splice(pos, 0, launcherItem);
                }

                function updateModel() {
                    const items = [];
                    const pinnedApps = [...(SessionData.pinnedApps || [])];
                    const allToplevels = CompositorService.sortedToplevels;
                    const sortedToplevels = (SettingsData.dockIsolateDisplays && root.dockScreen) ? allToplevels.filter(t => isOnScreen(t, root.dockScreen.name)) : allToplevels;

                    if (root.groupByApp) {
                        const appGroups = new Map();

                        pinnedApps.forEach(rawAppId => {
                            const appId = Paths.moddedAppId(rawAppId);
                            const coreAppData = getCoreAppData(appId);
                            appGroups.set(appId, {
                                appId: appId,
                                isPinned: true,
                                windows: [],
                                isCoreApp: coreAppData !== null,
                                coreAppData: coreAppData
                            });
                        });

                        sortedToplevels.forEach((toplevel, index) => {
                            const rawAppId = toplevel.appId || "unknown";
                            let appId = Paths.moddedAppId(rawAppId);

                            let coreAppData = null;
                            if (rawAppId === "org.quickshell") {
                                coreAppData = getCoreAppDataByTitle(toplevel.title);
                                if (coreAppData) {
                                    appId = coreAppData.builtInPluginId;
                                }
                            }

                            if (!appGroups.has(appId)) {
                                appGroups.set(appId, {
                                    appId: appId,
                                    isPinned: false,
                                    windows: [],
                                    isCoreApp: coreAppData !== null,
                                    coreAppData: coreAppData
                                });
                            }

                            appGroups.get(appId).windows.push({
                                toplevel: toplevel,
                                index: index
                            });
                        });

                        const pinnedGroups = [];
                        const unpinnedGroups = [];

                        Array.from(appGroups.entries()).forEach(([appId, group]) => {
                            const firstWindow = group.windows.length > 0 ? group.windows[0] : null;

                            const item = {
                                uniqueKey: "grouped_" + appId,
                                type: "grouped",
                                appId: appId,
                                toplevel: firstWindow ? firstWindow.toplevel : null,
                                isPinned: group.isPinned,
                                isRunning: group.windows.length > 0,
                                windowCount: group.windows.length,
                                allWindows: group.windows,
                                isCoreApp: group.isCoreApp || false,
                                coreAppData: group.coreAppData || null
                            };

                            if (group.isPinned) {
                                pinnedGroups.push(item);
                            } else {
                                unpinnedGroups.push(item);
                            }
                        });

                        pinnedGroups.forEach(item => items.push(item));

                        insertLauncher(items);

                        if (pinnedGroups.length > 0 && unpinnedGroups.length > 0) {
                            items.push({
                                uniqueKey: "separator_grouped",
                                type: "separator",
                                appId: "__SEPARATOR__",
                                toplevel: null,
                                isPinned: false,
                                isRunning: false
                            });
                        }

                        unpinnedGroups.forEach(item => items.push(item));
                        root.pinnedAppCount = pinnedGroups.length + (SettingsData.dockLauncherEnabled ? 1 : 0);
                    } else {
                        pinnedApps.forEach(rawAppId => {
                            const appId = Paths.moddedAppId(rawAppId);
                            const coreAppData = getCoreAppData(appId);
                            items.push({
                                uniqueKey: "pinned_" + appId,
                                type: "pinned",
                                appId: appId,
                                toplevel: null,
                                isPinned: true,
                                isRunning: false,
                                isCoreApp: coreAppData !== null,
                                coreAppData: coreAppData
                            });
                        });

                        root.pinnedAppCount = pinnedApps.length + (SettingsData.dockLauncherEnabled ? 1 : 0);

                        insertLauncher(items);

                        if (pinnedApps.length > 0 && sortedToplevels.length > 0) {
                            items.push({
                                uniqueKey: "separator_ungrouped",
                                type: "separator",
                                appId: "__SEPARATOR__",
                                toplevel: null,
                                isPinned: false,
                                isRunning: false
                            });
                        }

                        sortedToplevels.forEach((toplevel, index) => {
                            let uniqueKey = "window_" + index;
                            if (CompositorService.isHyprland && Hyprland.toplevels) {
                                const hyprlandToplevels = Array.from(Hyprland.toplevels.values);
                                for (let i = 0; i < hyprlandToplevels.length; i++) {
                                    if (hyprlandToplevels[i].wayland === toplevel) {
                                        uniqueKey = "window_" + hyprlandToplevels[i].address;
                                        break;
                                    }
                                }
                            }

                            const rawAppId = toplevel.appId || "unknown";
                            const moddedAppId = Paths.moddedAppId(rawAppId);

                            // Check if this is a core app window (e.g., Settings modal with appId "org.quickshell")
                            let coreAppData = null;
                            let isCoreApp = false;
                            if (rawAppId === "org.quickshell") {
                                coreAppData = getCoreAppDataByTitle(toplevel.title);
                                if (coreAppData) {
                                    isCoreApp = true;
                                }
                            }

                            const finalAppId = isCoreApp ? coreAppData.builtInPluginId : moddedAppId;
                            const isPinned = pinnedApps.indexOf(finalAppId) !== -1;

                            items.push({
                                uniqueKey: uniqueKey,
                                type: "window",
                                appId: finalAppId,
                                toplevel: toplevel,
                                isPinned: isPinned,
                                isRunning: true,
                                isCoreApp: isCoreApp,
                                coreAppData: coreAppData
                            });
                        });
                    }

                    dockItems = items;
                }

                delegate: Item {
                    id: delegateItem
                    property var dockButton: itemData.type === "launcher" ? launcherButton : button
                    property var itemData: modelData
                    clip: false
                    z: (itemData.type === "launcher" ? launcherButton.dragging : button.dragging) ? 100 : 0

                    width: itemData.type === "separator" ? (root.isVertical ? root.iconSize : 8) : (root.isVertical ? root.iconSize : root.iconSize * 1.2)
                    height: itemData.type === "separator" ? (root.isVertical ? 8 : root.iconSize) : (root.isVertical ? root.iconSize * 1.2 : root.iconSize)

                    property real shiftOffset: {
                        if (root.draggedIndex < 0 || !itemData.isPinned || itemData.type === "separator")
                            return 0;
                        if (model.index === root.draggedIndex)
                            return 0;

                        const dragIdx = root.draggedIndex;
                        const dropIdx = root.dropTargetIndex;
                        const myIdx = model.index;
                        const shiftAmount = root.iconSize * 1.2 + layoutFlow.spacing;

                        if (dropIdx < 0)
                            return 0;
                        if (dragIdx < dropIdx && myIdx > dragIdx && myIdx <= dropIdx)
                            return -shiftAmount;
                        if (dragIdx > dropIdx && myIdx >= dropIdx && myIdx < dragIdx)
                            return shiftAmount;
                        return 0;
                    }

                    transform: Translate {
                        x: root.isVertical ? 0 : delegateItem.shiftOffset
                        y: root.isVertical ? delegateItem.shiftOffset : 0

                        Behavior on x {
                            enabled: !root.suppressShiftAnimation
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on y {
                            enabled: !root.suppressShiftAnimation
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Rectangle {
                        visible: itemData.type === "separator"
                        width: root.isVertical ? root.iconSize * 0.5 : 2
                        height: root.isVertical ? 2 : root.iconSize * 0.5
                        color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3)
                        radius: 1
                        anchors.centerIn: parent
                    }

                    DockLauncherButton {
                        id: launcherButton
                        visible: itemData.type === "launcher"
                        anchors.centerIn: parent

                        width: delegateItem.width
                        height: delegateItem.height
                        actualIconSize: root.iconSize

                        dockApps: root
                        index: model.index
                    }

                    DockAppButton {
                        id: button
                        visible: itemData.type !== "separator" && itemData.type !== "launcher"
                        anchors.centerIn: parent

                        width: delegateItem.width
                        height: delegateItem.height
                        actualIconSize: root.iconSize

                        appData: itemData
                        contextMenu: root.contextMenu
                        dockApps: root
                        index: model.index
                        parentDockScreen: root.dockScreen

                        showWindowTitle: itemData?.type === "window" || itemData?.type === "grouped"
                        windowTitle: {
                            const title = itemData?.toplevel?.title || "(Unnamed)";
                            return title.length > 50 ? title.substring(0, 47) + "..." : title;
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: CompositorService
        function onToplevelsChanged() {
            repeater.updateModel();
        }
    }

    Connections {
        target: SessionData
        function onPinnedAppsChanged() {
            root.suppressShiftAnimation = true;
            root.draggedIndex = -1;
            root.dropTargetIndex = -1;
            repeater.updateModel();
            Qt.callLater(() => {
                root.suppressShiftAnimation = false;
            });
        }
    }

    onGroupByAppChanged: repeater.updateModel()

    Connections {
        target: SettingsData
        function onDockIsolateDisplaysChanged() {
            repeater.updateModel();
        }
        function onDockLauncherEnabledChanged() {
            root.suppressShiftAnimation = true;
            root.draggedIndex = -1;
            root.dropTargetIndex = -1;
            repeater.updateModel();
            Qt.callLater(() => {
                root.suppressShiftAnimation = false;
            });
        }
    }

    Connections {
        target: SessionData
        function onDockLauncherPositionChanged() {
            root.suppressShiftAnimation = true;
            root.draggedIndex = -1;
            root.dropTargetIndex = -1;
            repeater.updateModel();
            Qt.callLater(() => {
                root.suppressShiftAnimation = false;
            });
        }
    }
}
