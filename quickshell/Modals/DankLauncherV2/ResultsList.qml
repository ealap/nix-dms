pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    property var controller: null
    property int gridColumns: controller?.gridColumns ?? 4

    signal itemRightClicked(int index, var item, real mouseX, real mouseY)

    function resetScroll() {
        mainFlickable.contentY = 0;
    }

    function ensureVisible(index) {
        if (index < 0 || !controller?.flatModel || index >= controller.flatModel.length)
            return;
        var entry = controller.flatModel[index];
        if (!entry || entry.isHeader)
            return;
        scrollItemIntoView(index, entry.sectionId);
    }

    function scrollItemIntoView(flatIndex, sectionId) {
        var sections = controller?.sections ?? [];
        var sectionIndex = -1;
        for (var i = 0; i < sections.length; i++) {
            if (sections[i].id === sectionId) {
                sectionIndex = i;
                break;
            }
        }
        if (sectionIndex < 0)
            return;
        var itemInSection = 0;
        var foundSection = false;
        for (var i = 0; i < controller.flatModel.length && i < flatIndex; i++) {
            var e = controller.flatModel[i];
            if (e.isHeader && e.section?.id === sectionId)
                foundSection = true;
            else if (foundSection && !e.isHeader && e.sectionId === sectionId)
                itemInSection++;
        }

        var mode = controller.getSectionViewMode(sectionId);
        var sectionY = 0;
        for (var i = 0; i < sectionIndex; i++) {
            sectionY += getSectionHeight(sections[i]);
        }

        var itemY, itemHeight;
        if (mode === "list") {
            itemY = itemInSection * 52;
            itemHeight = 52;
        } else {
            var cols = controller.getGridColumns(sectionId);
            var cellWidth = mode === "tile" ? Math.floor(mainFlickable.width / 3) : Math.floor(mainFlickable.width / root.gridColumns);
            var cellHeight = mode === "tile" ? cellWidth * 0.75 : cellWidth + 24;
            var row = Math.floor(itemInSection / cols);
            itemY = row * cellHeight;
            itemHeight = cellHeight;
        }

        var targetY = sectionY + 32 + itemY;
        var targetBottom = targetY + itemHeight;
        var stickyHeight = mainFlickable.contentY > 0 ? 32 : 0;

        var shadowPadding = 24;
        if (targetY < mainFlickable.contentY + stickyHeight) {
            mainFlickable.contentY = Math.max(0, targetY - 32);
        } else if (targetBottom > mainFlickable.contentY + mainFlickable.height - shadowPadding) {
            mainFlickable.contentY = Math.min(mainFlickable.contentHeight - mainFlickable.height, targetBottom - mainFlickable.height + shadowPadding);
        }
    }

    function getSectionHeight(section) {
        var mode = controller?.getSectionViewMode(section.id) ?? "list";
        if (section.collapsed)
            return 32;

        if (mode === "list") {
            return 32 + (section.items?.length ?? 0) * 52;
        } else {
            var cols = controller?.getGridColumns(section.id) ?? root.gridColumns;
            var rows = Math.ceil((section.items?.length ?? 0) / cols);
            var cellWidth = mode === "tile" ? Math.floor(root.width / 3) : Math.floor(root.width / cols);
            var cellHeight = mode === "tile" ? cellWidth * 0.75 : cellWidth + 24;
            return 32 + rows * cellHeight;
        }
    }

    function getSelectedItemPosition() {
        var fallback = mapToItem(null, width / 2, height / 2);
        if (!controller?.flatModel || controller.selectedFlatIndex < 0)
            return fallback;

        var entry = controller.flatModel[controller.selectedFlatIndex];
        if (!entry || entry.isHeader)
            return fallback;

        var sections = controller.sections;
        var sectionIndex = -1;
        for (var i = 0; i < sections.length; i++) {
            if (sections[i].id === entry.sectionId) {
                sectionIndex = i;
                break;
            }
        }
        if (sectionIndex < 0)
            return fallback;

        var sectionY = 0;
        for (var i = 0; i < sectionIndex; i++) {
            sectionY += getSectionHeight(sections[i]);
        }

        var mode = controller.getSectionViewMode(entry.sectionId);
        var itemInSection = entry.indexInSection || 0;

        var itemY, itemX, itemH;
        if (mode === "list") {
            itemY = sectionY + 32 + itemInSection * 52;
            itemX = width / 2;
            itemH = 52;
        } else {
            var cols = controller.getGridColumns(entry.sectionId);
            var cellWidth = mode === "tile" ? Math.floor(width / 3) : Math.floor(width / cols);
            var cellHeight = mode === "tile" ? cellWidth * 0.75 : cellWidth + 24;
            var row = Math.floor(itemInSection / cols);
            var col = itemInSection % cols;
            itemY = sectionY + 32 + row * cellHeight;
            itemX = col * cellWidth + cellWidth / 2;
            itemH = cellHeight;
        }

        var visualY = itemY - mainFlickable.contentY + itemH / 2;
        var clampedY = Math.max(40, Math.min(height - 40, visualY));
        return mapToItem(null, itemX, clampedY);
    }

    Connections {
        target: root.controller
        function onSelectedFlatIndexChanged() {
            if (root.controller?.keyboardNavigationActive) {
                Qt.callLater(() => root.ensureVisible(root.controller.selectedFlatIndex));
            }
        }
    }

    DankFlickable {
        id: mainFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: sectionsColumn.height
        clip: true

        Component.onCompleted: {
            verticalScrollBar.targetFlickable = mainFlickable;
            verticalScrollBar.parent = root;
            verticalScrollBar.z = 102;
            verticalScrollBar.anchors.right = root.right;
            verticalScrollBar.anchors.top = root.top;
            verticalScrollBar.anchors.bottom = root.bottom;
        }

        Column {
            id: sectionsColumn
            width: parent.width

            Repeater {
                model: root.controller?.sections ?? []

                Column {
                    id: sectionDelegate
                    required property var modelData
                    required property int index

                    readonly property int versionTrigger: root.controller?.viewModeVersion ?? 0
                    readonly property string sectionId: modelData?.id ?? ""
                    readonly property string currentViewMode: {
                        void (versionTrigger);
                        return root.controller?.getSectionViewMode(sectionId) ?? "list";
                    }
                    readonly property bool isGridMode: currentViewMode === "grid" || currentViewMode === "tile"
                    readonly property bool isCollapsed: modelData?.collapsed ?? false

                    width: sectionsColumn.width

                    SectionHeader {
                        width: parent.width
                        height: 32
                        section: sectionDelegate.modelData
                        controller: root.controller
                        viewMode: sectionDelegate.currentViewMode
                        canChangeViewMode: root.controller?.canChangeSectionViewMode(sectionDelegate.sectionId) ?? false
                        canCollapse: root.controller?.canCollapseSection(sectionDelegate.sectionId) ?? false
                    }

                    Column {
                        id: listContent
                        width: parent.width
                        visible: !sectionDelegate.isGridMode && !sectionDelegate.isCollapsed

                        Repeater {
                            model: sectionDelegate.isGridMode || sectionDelegate.isCollapsed ? [] : (sectionDelegate.modelData?.items ?? [])

                            ResultItem {
                                required property var modelData
                                required property int index

                                width: listContent.width
                                height: 52
                                item: modelData
                                isSelected: getFlatIndex() === root.controller?.selectedFlatIndex
                                controller: root.controller
                                flatIndex: getFlatIndex()

                                function getFlatIndex() {
                                    if (!sectionDelegate?.sectionId)
                                        return -1;
                                    var flatIdx = 0;
                                    var sections = root.controller?.sections ?? [];
                                    for (var i = 0; i < sections.length; i++) {
                                        flatIdx++;
                                        if (sections[i].id === sectionDelegate.sectionId)
                                            return flatIdx + index;
                                        if (!sections[i].collapsed)
                                            flatIdx += sections[i].items?.length ?? 0;
                                    }
                                    return -1;
                                }

                                onClicked: {
                                    if (root.controller) {
                                        root.controller.executeItem(modelData);
                                    }
                                }

                                onRightClicked: (mouseX, mouseY) => {
                                    root.itemRightClicked(getFlatIndex(), modelData, mouseX, mouseY);
                                }
                            }
                        }
                    }

                    Grid {
                        id: gridContent
                        width: parent.width
                        visible: sectionDelegate.isGridMode && !sectionDelegate.isCollapsed
                        columns: sectionDelegate.currentViewMode === "tile" ? 3 : root.gridColumns

                        readonly property real cellWidth: sectionDelegate.currentViewMode === "tile" ? Math.floor(width / 3) : Math.floor(width / root.gridColumns)
                        readonly property real cellHeight: sectionDelegate.currentViewMode === "tile" ? cellWidth * 0.75 : cellWidth + 24

                        Repeater {
                            model: sectionDelegate.isGridMode && !sectionDelegate.isCollapsed ? (sectionDelegate.modelData?.items ?? []) : []

                            Item {
                                id: gridDelegateItem
                                required property var modelData
                                required property int index

                                width: gridContent.cellWidth
                                height: gridContent.cellHeight

                                function getFlatIndex() {
                                    if (!sectionDelegate?.sectionId)
                                        return -1;
                                    var flatIdx = 0;
                                    var sections = root.controller?.sections ?? [];
                                    for (var i = 0; i < sections.length; i++) {
                                        flatIdx++;
                                        if (sections[i].id === sectionDelegate.sectionId)
                                            return flatIdx + index;
                                        if (!sections[i].collapsed)
                                            flatIdx += sections[i].items?.length ?? 0;
                                    }
                                    return -1;
                                }

                                readonly property int cachedFlatIndex: getFlatIndex()

                                GridItem {
                                    width: parent.width - 4
                                    height: parent.height - 4
                                    anchors.centerIn: parent
                                    visible: sectionDelegate.currentViewMode === "grid"
                                    item: gridDelegateItem.modelData
                                    isSelected: gridDelegateItem.cachedFlatIndex === root.controller?.selectedFlatIndex
                                    controller: root.controller
                                    flatIndex: gridDelegateItem.cachedFlatIndex

                                    onClicked: {
                                        if (root.controller) {
                                            root.controller.executeItem(gridDelegateItem.modelData);
                                        }
                                    }

                                    onRightClicked: (mouseX, mouseY) => {
                                        root.itemRightClicked(gridDelegateItem.cachedFlatIndex, gridDelegateItem.modelData, mouseX, mouseY);
                                    }
                                }

                                TileItem {
                                    width: parent.width - 4
                                    height: parent.height - 4
                                    anchors.centerIn: parent
                                    visible: sectionDelegate.currentViewMode === "tile"
                                    item: gridDelegateItem.modelData
                                    isSelected: gridDelegateItem.cachedFlatIndex === root.controller?.selectedFlatIndex
                                    controller: root.controller
                                    flatIndex: gridDelegateItem.cachedFlatIndex

                                    onClicked: {
                                        if (root.controller) {
                                            root.controller.executeItem(gridDelegateItem.modelData);
                                        }
                                    }

                                    onRightClicked: (mouseX, mouseY) => {
                                        root.itemRightClicked(gridDelegateItem.cachedFlatIndex, gridDelegateItem.modelData, mouseX, mouseY);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: bottomShadow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 24
        z: 100
        visible: {
            if (mainFlickable.contentHeight <= mainFlickable.height)
                return false;
            var atBottom = mainFlickable.contentY >= mainFlickable.contentHeight - mainFlickable.height - 5;
            if (atBottom)
                return false;

            var flatModel = root.controller?.flatModel;
            if (!flatModel || flatModel.length === 0)
                return false;
            var lastItemIdx = -1;
            for (var i = flatModel.length - 1; i >= 0; i--) {
                if (!flatModel[i].isHeader) {
                    lastItemIdx = i;
                    break;
                }
            }
            if (lastItemIdx >= 0 && root.controller?.selectedFlatIndex === lastItemIdx)
                return false;
            return true;
        }
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: "transparent"
            }
            GradientStop {
                position: 1.0
                color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
            }
        }
    }

    Rectangle {
        id: stickyHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 32
        z: 101
        color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
        visible: stickyHeaderSection !== null

        readonly property int versionTrigger: root.controller?.viewModeVersion ?? 0

        readonly property var stickyHeaderSection: {
            if (!root.controller?.sections || root.controller.sections.length === 0)
                return null;
            var sections = root.controller.sections;
            if (sections.length === 0)
                return null;

            var scrollY = mainFlickable.contentY;
            if (scrollY <= 0)
                return null;

            var y = 0;
            for (var i = 0; i < sections.length; i++) {
                var section = sections[i];
                var sectionHeight = root.getSectionHeight(section);
                if (scrollY < y + sectionHeight)
                    return section;
                y += sectionHeight;
            }
            return sections[sections.length - 1];
        }

        SectionHeader {
            width: parent.width
            section: stickyHeader.stickyHeaderSection
            controller: root.controller
            viewMode: {
                void (stickyHeader.versionTrigger);
                return root.controller?.getSectionViewMode(stickyHeader.stickyHeaderSection?.id) ?? "list";
            }
            canChangeViewMode: {
                void (stickyHeader.versionTrigger);
                return root.controller?.canChangeSectionViewMode(stickyHeader.stickyHeaderSection?.id) ?? false;
            }
            canCollapse: {
                void (stickyHeader.versionTrigger);
                return root.controller?.canCollapseSection(stickyHeader.stickyHeaderSection?.id) ?? false;
            }
            isSticky: true
        }
    }

    Item {
        anchors.centerIn: parent
        visible: (!root.controller?.sections || root.controller.sections.length === 0) && !root.controller?.isFileSearching
        width: emptyColumn.implicitWidth
        height: emptyColumn.implicitHeight

        Column {
            id: emptyColumn
            spacing: Theme.spacingM

            DankIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: getEmptyIcon()
                size: 48
                color: Theme.outlineButton

                function getEmptyIcon() {
                    var mode = root.controller?.searchMode ?? "all";
                    switch (mode) {
                    case "files":
                        return "folder_open";
                    case "plugins":
                        return "extension";
                    case "apps":
                        return "apps";
                    default:
                        return root.controller?.searchQuery?.length > 0 ? "search_off" : "search";
                    }
                }
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: getEmptyText()
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                horizontalAlignment: Text.AlignHCenter

                function getEmptyText() {
                    var mode = root.controller?.searchMode ?? "all";
                    var hasQuery = root.controller?.searchQuery?.length > 0;

                    switch (mode) {
                    case "files":
                        if (!DSearchService.dsearchAvailable)
                            return I18n.tr("File search requires dsearch\nInstall from github.com/morelazers/dsearch");
                        if (!hasQuery)
                            return I18n.tr("Type to search files");
                        if (root.controller.searchQuery.length < 2)
                            return I18n.tr("Type at least 2 characters");
                        return I18n.tr("No files found");
                    case "plugins":
                        return hasQuery ? I18n.tr("No plugin results") : I18n.tr("Browse or search plugins");
                    case "apps":
                        return hasQuery ? I18n.tr("No apps found") : I18n.tr("Type to search apps");
                    default:
                        return hasQuery ? I18n.tr("No results found") : I18n.tr("Type to search");
                    }
                }
            }
        }
    }
}
