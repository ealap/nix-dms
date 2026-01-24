import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    property var widgetData: null
    property var barConfig: null
    property bool isVertical: axis?.isVertical ?? false
    property var axis: null
    property string section: "left"
    property var parentScreen
    property var hoveredItem: null
    property var topBar: null
    property real widgetThickness: 30
    property real barThickness: 48
    property real barSpacing: 4
    property bool isAutoHideBar: false
    readonly property real horizontalPadding: (barConfig?.noBackground ?? false) ? 2 : Theme.spacingS
    property Item windowRoot: (Window.window ? Window.window.contentItem : null)

    property int draggedIndex: -1
    property int dropTargetIndex: -1
    property bool suppressShiftAnimation: false
    property int pinnedAppCount: 0

    readonly property real effectiveBarThickness: {
        if (barThickness > 0 && barSpacing > 0) {
            return barThickness + barSpacing;
        }
        const innerPadding = barConfig?.innerPadding ?? 4;
        const spacing = barConfig?.spacing ?? 4;
        return Math.max(26 + innerPadding * 0.6, Theme.barHeight - 4 - (8 - innerPadding)) + spacing;
    }

    readonly property var barBounds: {
        if (!parentScreen || !barConfig) {
            return {
                "x": 0,
                "y": 0,
                "width": 0,
                "height": 0,
                "wingSize": 0
            };
        }
        const barPosition = axis.edge === "left" ? 2 : (axis.edge === "right" ? 3 : (axis.edge === "top" ? 0 : 1));
        return SettingsData.getBarBounds(parentScreen, effectiveBarThickness, barPosition, barConfig);
    }

    readonly property real barY: barBounds.y

    readonly property real minTooltipY: {
        if (!parentScreen || !isVertical) {
            return 0;
        }

        if (isAutoHideBar) {
            return 0;
        }

        if (parentScreen.y > 0) {
            return effectiveBarThickness;
        }

        return 0;
    }

    // --- Dock Logic Helpers ---
    function movePinnedApp(fromDockIndex, toDockIndex) {
        if (fromDockIndex === toDockIndex)
            return;

        const currentPinned = [...(SessionData.barPinnedApps || [])];
        if (fromDockIndex < 0 || fromDockIndex >= currentPinned.length || toDockIndex < 0 || toDockIndex >= currentPinned.length) {
            return;
        }

        const movedApp = currentPinned.splice(fromDockIndex, 1)[0];
        currentPinned.splice(toDockIndex, 0, movedApp);

        SessionData.setBarPinnedApps(currentPinned);
    }

    property int _desktopEntriesUpdateTrigger: 0
    property int _toplevelsUpdateTrigger: 0
    property int _appIdSubstitutionsTrigger: 0

    Connections {
        target: CompositorService
        function onToplevelsChanged() {
            _toplevelsUpdateTrigger++;
            updateModel();
        }
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            _desktopEntriesUpdateTrigger++;
        }
    }

    Connections {
        target: SettingsData
        function onAppIdSubstitutionsChanged() {
            _appIdSubstitutionsTrigger++;
            updateModel();
        }
        function onRunningAppsCurrentWorkspaceChanged() {
            updateModel();
        }
    }

    Connections {
        target: SessionData
        function onBarPinnedAppsChanged() {
            root.suppressShiftAnimation = true;
            root.draggedIndex = -1;
            root.dropTargetIndex = -1;
            updateModel();
            Qt.callLater(() => {
                root.suppressShiftAnimation = false;
            });
        }
    }

    property var dockItems: []

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
            if (coreApps[i].builtInPluginId === appId)
                return coreApps[i];
        }
        return null;
    }

    function getCoreAppDataByTitle(windowTitle) {
        if (typeof AppSearchService === "undefined" || !windowTitle)
            return null;
        const coreApps = AppSearchService.coreApps || [];
        for (let i = 0; i < coreApps.length; i++) {
            if (coreApps[i].name === windowTitle)
                return coreApps[i];
        }
        return null;
    }

    function updateModel() {
        const items = [];
        const pinnedApps = [...(SessionData.barPinnedApps || [])];
        _toplevelsUpdateTrigger;
        const allToplevels = CompositorService.sortedToplevels;

        let sortedToplevels = allToplevels;
        if (SettingsData.runningAppsCurrentWorkspace && parentScreen) {
            sortedToplevels = CompositorService.filterCurrentWorkspace(allToplevels, parentScreen.name) || [];
        }

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
                index: index,
                windowTitle: toplevel.title
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

        root.pinnedAppCount = pinnedGroups.length;
        dockItems = items;
    }

    Component.onCompleted: updateModel()

    readonly property int calculatedSize: {
        const count = dockItems.length;
        if (count === 0)
            return 0;

        if (widgetData?.runningAppsCompactMode !== undefined ? widgetData.runningAppsCompactMode : SettingsData.runningAppsCompactMode) {
            return count * 24 + (count - 1) * Theme.spacingXS + horizontalPadding * 2;
        } else {
            return count * (24 + Theme.spacingXS + 120) + (count - 1) * Theme.spacingXS + horizontalPadding * 2;
        }
    }

    readonly property real realCalculatedSize: {
        let total = horizontalPadding * 2;
        const compact = (widgetData?.runningAppsCompactMode !== undefined ? widgetData.runningAppsCompactMode : SettingsData.runningAppsCompactMode);

        for (let i = 0; i < dockItems.length; i++) {
            const item = dockItems[i];
            let itemSize = 0;
            if (item.type === "separator") {
                itemSize = 8;
            } else {
                itemSize = compact ? 24 : (24 + Theme.spacingXS + 120);
            }

            total += itemSize;
            if (i < dockItems.length - 1)
                total += Theme.spacingXS;
        }
        return total;
    }

    width: dockItems.length > 0 ? (isVertical ? barThickness : realCalculatedSize) : 0
    height: dockItems.length > 0 ? (isVertical ? realCalculatedSize : barThickness) : 0
    visible: dockItems.length > 0

    Item {
        id: visualBackground
        width: root.isVertical ? root.widgetThickness : root.realCalculatedSize
        height: root.isVertical ? root.realCalculatedSize : root.widgetThickness
        anchors.centerIn: parent
        clip: false

        Rectangle {
            id: outline
            anchors.centerIn: parent
            width: {
                const borderWidth = (barConfig?.widgetOutlineEnabled ?? false) ? (barConfig?.widgetOutlineThickness ?? 1) : 0;
                return parent.width + borderWidth * 2;
            }
            height: {
                const borderWidth = (barConfig?.widgetOutlineEnabled ?? false) ? (barConfig?.widgetOutlineThickness ?? 1) : 0;
                return parent.height + borderWidth * 2;
            }
            radius: (barConfig?.noBackground ?? false) ? 0 : Theme.cornerRadius
            color: "transparent"
            border.width: (barConfig?.widgetOutlineEnabled ?? false) ? (barConfig?.widgetOutlineThickness ?? 1) : 0
            border.color: {
                if (!(barConfig?.widgetOutlineEnabled ?? false)) {
                    return "transparent";
                }
                const colorOption = barConfig?.widgetOutlineColor || "primary";
                const opacity = barConfig?.widgetOutlineOpacity ?? 1.0;
                switch (colorOption) {
                case "surfaceText":
                    return Theme.withAlpha(Theme.surfaceText, opacity);
                case "secondary":
                    return Theme.withAlpha(Theme.secondary, opacity);
                case "primary":
                    return Theme.withAlpha(Theme.primary, opacity);
                default:
                    return Theme.withAlpha(Theme.primary, opacity);
                }
            }
        }

        Rectangle {
            id: background
            anchors.fill: parent
            radius: (barConfig?.noBackground ?? false) ? 0 : Theme.cornerRadius
            color: {
                if (dockItems.length === 0)
                    return "transparent";
                if ((barConfig?.noBackground ?? false))
                    return "transparent";

                const baseColor = Theme.widgetBaseBackgroundColor;
                const transparency = (root.barConfig && root.barConfig.widgetTransparency !== undefined) ? root.barConfig.widgetTransparency : 1.0;
                if (Theme.widgetBackgroundHasAlpha) {
                    return Qt.rgba(baseColor.r, baseColor.g, baseColor.b, baseColor.a * transparency);
                }
                return Theme.withAlpha(baseColor, transparency);
            }
        }
    }

    Loader {
        id: layoutLoader
        anchors.centerIn: parent
        sourceComponent: root.isVertical ? columnLayout : rowLayout
    }

    Component {
        id: rowLayout
        Row {
            spacing: Theme.spacingXS

            Repeater {
                id: repeater
                model: ScriptModel {
                    values: root.dockItems
                    objectProp: "uniqueKey"
                }

                delegate: dockDelegate
            }
        }
    }

    Component {
        id: columnLayout
        Column {
            spacing: Theme.spacingXS

            Repeater {
                model: ScriptModel {
                    values: root.dockItems
                    objectProp: "uniqueKey"
                }
                delegate: dockDelegate
            }
        }
    }

    Loader {
        id: tooltipLoader
        active: false
        sourceComponent: DankTooltip {}
    }

    Component {
        id: dockDelegate
        Item {
            id: delegateItem
            property bool isSeparator: modelData.type === "separator"

            readonly property real visualSize: isSeparator ? 8 : ((widgetData?.runningAppsCompactMode !== undefined ? widgetData.runningAppsCompactMode : SettingsData.runningAppsCompactMode) ? 24 : (24 + Theme.spacingXS + 120))
            readonly property real visualWidth: root.isVertical ? root.barThickness : visualSize
            readonly property real visualHeight: root.isVertical ? visualSize : root.barThickness

            width: visualWidth
            height: visualHeight

            z: (dragHandler.dragging) ? 100 : 0

            // --- Drag and Drop Shift Animation Logic ---
            property real shiftOffset: {
                if (root.draggedIndex < 0 || !modelData.isPinned || isSeparator)
                    return 0;
                if (index === root.draggedIndex)
                    return 0;

                const dragIdx = root.draggedIndex;
                const dropIdx = root.dropTargetIndex;
                const myIdx = index;
                const shiftAmount = visualSize + Theme.spacingXS;

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
                visible: isSeparator
                width: root.isVertical ? root.barThickness * 0.6 : 2
                height: root.isVertical ? 2 : root.barThickness * 0.6
                color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3)
                radius: 1
                anchors.centerIn: parent
            }

            Item {
                id: appItem
                visible: !isSeparator
                anchors.fill: parent

                property bool isFocused: {
                    if (modelData.type === "grouped") {
                        return modelData.allWindows.some(w => w.toplevel && w.toplevel.activated);
                    }
                    return modelData.toplevel ? modelData.toplevel.activated : false;
                }

                property var appId: modelData.appId
                property int windowCount: modelData.windowCount || (modelData.isRunning ? 1 : 0)
                property string windowTitle: {
                    if (modelData.type === "grouped") {
                        const active = modelData.allWindows.find(w => w.toplevel && w.toplevel.activated);
                        if (active)
                            return active.windowTitle || "(Unnamed)";
                        if (modelData.allWindows.length > 0)
                            return modelData.allWindows[0].windowTitle || "(Unnamed)";
                        return "";
                    }
                    return modelData.toplevel ? (modelData.toplevel.title || "(Unnamed)") : "";
                }

                property string tooltipText: {
                    root._desktopEntriesUpdateTrigger;
                    const moddedId = Paths.moddedAppId(appId);
                    const desktopEntry = moddedId ? DesktopEntries.heuristicLookup(moddedId) : null;
                    const appName = appId ? Paths.getAppName(appId, desktopEntry) : "Unknown";

                    if (modelData.type === "grouped" && windowCount > 1) {
                        return appName + " (" + windowCount + " windows)";
                    }
                    return appName + (windowTitle ? " • " + windowTitle : "");
                }

                transform: Translate {
                    x: (dragHandler.dragging && !root.isVertical) ? dragHandler.dragAxisOffset : 0
                    y: (dragHandler.dragging && root.isVertical) ? dragHandler.dragAxisOffset : 0
                }

                Rectangle {
                    id: visualContent
                    width: root.isVertical ? 24 : delegateItem.visualSize
                    height: root.isVertical ? delegateItem.visualSize : 24
                    anchors.centerIn: parent
                    radius: Theme.cornerRadius
                    color: {
                        if (appItem.isFocused) {
                            return mouseArea.containsMouse ? Theme.primarySelected : Theme.withAlpha(Theme.primary, 0.2);
                        }
                        return mouseArea.containsMouse ? Theme.widgetBaseHoverColor : "transparent";
                    }

                    border.width: dragHandler.dragging ? 2 : 0
                    border.color: Theme.primary
                    opacity: dragHandler.dragging ? 0.8 : 1.0

                    AppIconRenderer {
                        id: coreIcon
                        readonly property bool isCompact: (widgetData?.runningAppsCompactMode !== undefined ? widgetData.runningAppsCompactMode : SettingsData.runningAppsCompactMode)
                        anchors.left: (root.isVertical || isCompact) ? undefined : parent.left
                        anchors.leftMargin: (root.isVertical || isCompact) ? 0 : Theme.spacingXS
                        anchors.top: (root.isVertical && !isCompact) ? parent.top : undefined
                        anchors.topMargin: (root.isVertical && !isCompact) ? Theme.spacingXS : 0
                        anchors.centerIn: (root.isVertical || isCompact) ? parent : undefined

                        iconSize: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.noBackground)
                        materialIconSizeAdjustment: 0
                        iconValue: {
                            if (!modelData || !modelData.isCoreApp || !modelData.coreAppData)
                                return "";
                            const appId = modelData.coreAppData.id || modelData.coreAppData.builtInPluginId;
                            if ((appId === "dms_settings" || appId === "dms_notepad" || appId === "dms_sysmon") && modelData.coreAppData.cornerIcon) {
                                return "material:" + modelData.coreAppData.cornerIcon;
                            }
                            return modelData.coreAppData.icon || "";
                        }
                        colorOverride: Theme.widgetIconColor
                        fallbackText: "?"
                        visible: iconValue !== ""
                        z: 2
                    }

                    IconImage {
                        id: iconImg
                        readonly property bool isCompact: (widgetData?.runningAppsCompactMode !== undefined ? widgetData.runningAppsCompactMode : SettingsData.runningAppsCompactMode)
                        anchors.left: (root.isVertical || isCompact) ? undefined : parent.left
                        anchors.leftMargin: (root.isVertical || isCompact) ? 0 : Theme.spacingXS
                        anchors.top: (root.isVertical && !isCompact) ? parent.top : undefined
                        anchors.topMargin: (root.isVertical && !isCompact) ? Theme.spacingXS : 0
                        anchors.centerIn: (root.isVertical || isCompact) ? parent : undefined

                        width: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.noBackground)
                        height: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.noBackground)
                        source: {
                            root._desktopEntriesUpdateTrigger;
                            root._appIdSubstitutionsTrigger;
                            if (!appItem.appId)
                                return "";
                            if (modelData.isCoreApp)
                                return ""; // Explicitly skip if core app to avoid flickering or wrong look ups
                            const moddedId = Paths.moddedAppId(appItem.appId);
                            const desktopEntry = DesktopEntries.heuristicLookup(moddedId);
                            return Paths.getAppIcon(appItem.appId, desktopEntry);
                        }
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        visible: status === Image.Ready && !coreIcon.visible
                        layer.enabled: appItem.appId === "org.quickshell"
                        layer.smooth: true
                        layer.mipmap: true
                        layer.effect: MultiEffect {
                            saturation: 0
                            colorization: 1
                            colorizationColor: Theme.primary
                        }
                        z: 2
                    }

                    DankIcon {
                        readonly property bool isCompact: (widgetData?.runningAppsCompactMode !== undefined ? widgetData.runningAppsCompactMode : SettingsData.runningAppsCompactMode)
                        anchors.left: (root.isVertical || isCompact) ? undefined : parent.left
                        anchors.leftMargin: (root.isVertical || isCompact) ? 0 : Theme.spacingXS
                        anchors.top: (root.isVertical && !isCompact) ? parent.top : undefined
                        anchors.topMargin: (root.isVertical && !isCompact) ? Theme.spacingXS : 0
                        anchors.centerIn: (root.isVertical || isCompact) ? parent : undefined

                        size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.noBackground)
                        name: "sports_esports"
                        color: Theme.widgetTextColor
                        visible: !iconImg.visible && !coreIcon.visible && Paths.isSteamApp(appItem.appId)
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !iconImg.visible && !coreIcon.visible && !Paths.isSteamApp(appItem.appId)
                        text: {
                            root._desktopEntriesUpdateTrigger;
                            if (!appItem.appId)
                                return "?";
                            const moddedId = Paths.moddedAppId(appItem.appId);
                            const desktopEntry = DesktopEntries.heuristicLookup(moddedId);
                            const appName = Paths.getAppName(appItem.appId, desktopEntry);
                            return appName.charAt(0).toUpperCase();
                        }
                        font.pixelSize: 10
                        color: Theme.widgetTextColor
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: (widgetData?.runningAppsCompactMode !== undefined ? widgetData.runningAppsCompactMode : SettingsData.runningAppsCompactMode) ? -2 : 2
                        anchors.bottomMargin: -2
                        width: 14
                        height: 14
                        radius: 7
                        color: Theme.primary
                        visible: modelData.type === "grouped" && appItem.windowCount > 1
                        z: 10

                        StyledText {
                            anchors.centerIn: parent
                            text: appItem.windowCount > 9 ? "9+" : appItem.windowCount
                            font.pixelSize: 9
                            color: Theme.surface
                        }
                    }

                    StyledText {
                        visible: !root.isVertical && !(widgetData?.runningAppsCompactMode !== undefined ? widgetData.runningAppsCompactMode : SettingsData.runningAppsCompactMode)
                        anchors.left: iconImg.right
                        anchors.leftMargin: Theme.spacingXS
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: appItem.windowTitle || appItem.appId
                        font.pixelSize: Theme.barTextSize(barThickness, barConfig?.fontScale)
                        color: Theme.widgetTextColor
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Rectangle {
                        visible: modelData.isRunning
                        width: root.isVertical ? 2 : 20
                        height: root.isVertical ? 20 : 2
                        radius: 1
                        color: appItem.isFocused ? Theme.primary : Theme.surfaceText
                        opacity: appItem.isFocused ? 1 : 0.5

                        anchors.bottom: root.isVertical ? undefined : parent.bottom
                        anchors.right: root.isVertical ? parent.right : undefined
                        anchors.horizontalCenter: root.isVertical ? undefined : parent.horizontalCenter
                        anchors.verticalCenter: root.isVertical ? parent.verticalCenter : undefined

                        anchors.margins: 0
                        z: 5
                    }
                }
            }

            // Handler for Drag Logic
            Item {
                id: dragHandler
                anchors.fill: parent
                property bool dragging: false
                property point dragStartPos: Qt.point(0, 0)
                property real dragAxisOffset: 0
                property bool longPressing: false

                Timer {
                    id: longPressTimer
                    interval: 500
                    repeat: false
                    onTriggered: {
                        if (modelData.isPinned) {
                            dragHandler.longPressing = true;
                        }
                    }
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: dragHandler.longPressing ? Qt.DragMoveCursor : Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    onPressed: mouse => {
                        if (mouse.button === Qt.LeftButton && modelData.isPinned) {
                            dragHandler.dragStartPos = Qt.point(mouse.x, mouse.y);
                            longPressTimer.start();
                        }
                    }

                    onReleased: mouse => {
                        longPressTimer.stop();
                        const wasDragging = dragHandler.dragging;
                        const didReorder = wasDragging && root.dropTargetIndex >= 0 && root.dropTargetIndex !== root.draggedIndex;

                        if (didReorder) {
                            root.movePinnedApp(root.draggedIndex, root.dropTargetIndex);
                        }

                        dragHandler.longPressing = false;
                        dragHandler.dragging = false;
                        dragHandler.dragAxisOffset = 0;
                        root.draggedIndex = -1;
                        root.dropTargetIndex = -1;

                        if (wasDragging || mouse.button !== Qt.LeftButton)
                            return;

                        if (wasDragging || mouse.button !== Qt.LeftButton)
                            return;

                        if (modelData.type === "grouped") {
                            if (modelData.windowCount === 0) {
                                if (modelData.isCoreApp && modelData.coreAppData) {
                                    AppSearchService.executeCoreApp(modelData.coreAppData);
                                } else {
                                    const moddedId = Paths.moddedAppId(modelData.appId);
                                    const desktopEntry = DesktopEntries.heuristicLookup(moddedId);
                                    if (desktopEntry)
                                        SessionService.launchDesktopEntry(desktopEntry);
                                }
                            } else if (modelData.windowCount === 1) {
                                if (modelData.allWindows[0].toplevel)
                                    modelData.allWindows[0].toplevel.activate();
                            } else {
                                let currentIndex = -1;
                                for (var i = 0; i < modelData.allWindows.length; i++) {
                                    if (modelData.allWindows[i].toplevel.activated) {
                                        currentIndex = i;
                                        break;
                                    }
                                }
                                const nextIndex = (currentIndex + 1) % modelData.allWindows.length;
                                modelData.allWindows[nextIndex].toplevel.activate();
                            }
                        }
                    }

                    onPositionChanged: mouse => {
                        if (dragHandler.longPressing && !dragHandler.dragging) {
                            const distance = Math.sqrt(Math.pow(mouse.x - dragHandler.dragStartPos.x, 2) + Math.pow(mouse.y - dragHandler.dragStartPos.y, 2));
                            if (distance > 5) {
                                dragHandler.dragging = true;
                                root.draggedIndex = index;
                                root.dropTargetIndex = index;
                            }
                        }

                        if (!dragHandler.dragging)
                            return;

                        const axisOffset = root.isVertical ? (mouse.y - dragHandler.dragStartPos.y) : (mouse.x - dragHandler.dragStartPos.x);
                        dragHandler.dragAxisOffset = axisOffset;

                        const itemSize = (root.isVertical ? delegateItem.height : delegateItem.width) + Theme.spacingXS;
                        const slotOffset = Math.round(axisOffset / itemSize);
                        const newTargetIndex = Math.max(0, Math.min(root.pinnedAppCount - 1, index + slotOffset));

                        if (newTargetIndex !== root.dropTargetIndex) {
                            root.dropTargetIndex = newTargetIndex;
                        }
                    }

                    onEntered: {
                        root.hoveredItem = delegateItem;
                        if (isSeparator)
                            return;

                        tooltipLoader.active = true;
                        if (tooltipLoader.item) {
                            if (root.isVertical) {
                                const globalPos = delegateItem.mapToGlobal(delegateItem.width / 2, delegateItem.height / 2);
                                const screenX = root.parentScreen ? root.parentScreen.x : 0;
                                const screenY = root.parentScreen ? root.parentScreen.y : 0;
                                const relativeY = globalPos.y - screenY;
                                const tooltipX = root.axis?.edge === "left" ? (Theme.barHeight + (barConfig?.spacing ?? 4) + Theme.spacingXS) : (root.parentScreen.width - Theme.barHeight - (barConfig?.spacing ?? 4) - Theme.spacingXS);
                                const isLeft = root.axis?.edge === "left";
                                const adjustedY = relativeY + root.minTooltipY;
                                const finalX = screenX + tooltipX;
                                tooltipLoader.item.show(appItem.tooltipText, finalX, adjustedY, root.parentScreen, isLeft, !isLeft);
                            } else {
                                const globalPos = delegateItem.mapToGlobal(delegateItem.width / 2, delegateItem.height);
                                const screenHeight = root.parentScreen ? root.parentScreen.height : Screen.height;
                                const isBottom = root.axis?.edge === "bottom";
                                const tooltipY = isBottom ? (screenHeight - Theme.barHeight - (barConfig?.spacing ?? 4) - Theme.spacingXS - 35) : (Theme.barHeight + (barConfig?.spacing ?? 4) + Theme.spacingXS);
                                tooltipLoader.item.show(appItem.tooltipText, globalPos.x, tooltipY, root.parentScreen, false, false);
                            }
                        }
                    }
                    onExited: {
                        if (root.hoveredItem === delegateItem) {
                            root.hoveredItem = null;
                            if (tooltipLoader.item)
                                tooltipLoader.item.hide();
                            tooltipLoader.active = false;
                        }
                    }

                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            if (tooltipLoader.item) {
                                tooltipLoader.item.hide();
                            }
                            tooltipLoader.active = false;
                            contextMenuLoader.active = true;

                            if (contextMenuLoader.item) {
                                const globalPos = delegateItem.mapToGlobal(delegateItem.width / 2, delegateItem.height / 2);

                                const isBarVertical = root.axis?.isVertical ?? false;
                                const barEdge = root.axis?.edge ?? "top";

                                let x = globalPos.x;
                                let y = globalPos.y;

                                if (barEdge === "bottom") {
                                    y = (root.parentScreen ? root.parentScreen.height : Screen.height) - root.effectiveBarThickness;
                                } else if (barEdge === "top") {
                                    y = root.effectiveBarThickness;
                                } else if (barEdge === "left") {
                                    x = root.effectiveBarThickness;
                                } else if (barEdge === "right") {
                                    x = (root.parentScreen ? root.parentScreen.width : Screen.width) - root.effectiveBarThickness;
                                }

                                const shouldHidePin = modelData.appId === "org.quickshell";
                                const moddedId = Paths.moddedAppId(modelData.appId);
                                const desktopEntry = moddedId ? DesktopEntries.heuristicLookup(moddedId) : null;

                                contextMenuLoader.item.showAt(x, y, isBarVertical, barEdge, modelData, shouldHidePin, desktopEntry, root.parentScreen);
                            }
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: contextMenuLoader
        active: false
        source: "AppsDockContextMenu.qml"
    }
}
