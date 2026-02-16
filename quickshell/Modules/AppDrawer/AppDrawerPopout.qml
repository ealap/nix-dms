import QtQuick
import qs.Common
import qs.Modals.DankLauncherV2
import qs.Widgets

DankPopout {
    id: appDrawerPopout

    layerNamespace: "dms:app-launcher"

    function show() {
        open();
    }

    popupWidth: 560
    popupHeight: 640
    triggerWidth: 40
    positioning: ""
    contentHandlesKeys: contentLoader.item?.launcherContent?.editMode ?? false

    onBackgroundClicked: {
        if (contentLoader.item?.launcherContent?.editMode) {
            contentLoader.item.launcherContent.closeEditMode();
            return;
        }
        close();
    }

    onOpened: {
        var lc = contentLoader.item?.launcherContent;
        if (!lc)
            return;
        if (lc.searchField) {
            lc.searchField.text = "";
            lc.searchField.forceActiveFocus();
        }
        if (lc.controller) {
            lc.controller.searchMode = "apps";
            lc.controller.pluginFilter = "";
            lc.controller.searchQuery = "";
            lc.controller.performSearch();
        }
        lc.resetScroll?.();
        lc.actionPanel?.hide();
    }

    content: Component {
        Rectangle {
            id: contentContainer

            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true

            property alias launcherContent: launcherContent

            color: "transparent"

            QtObject {
                id: modalAdapter
                property bool spotlightOpen: appDrawerPopout.shouldBeVisible
                property bool isClosing: false

                function hide() {
                    appDrawerPopout.close();
                }
            }

            FocusScope {
                anchors.fill: parent
                focus: true

                LauncherContent {
                    id: launcherContent
                    anchors.fill: parent
                    parentModal: modalAdapter
                    viewModeContext: "appDrawer"
                }

                Keys.onEscapePressed: event => {
                    if (launcherContent.editMode) {
                        launcherContent.closeEditMode();
                        event.accepted = true;
                        return;
                    }
                    appDrawerPopout.close();
                    event.accepted = true;
                }
            }
        }
    }
}
