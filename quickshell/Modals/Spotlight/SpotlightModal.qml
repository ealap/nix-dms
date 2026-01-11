import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import qs.Common
import qs.Modals.Common

DankModal {
    id: spotlightModal

    layerNamespace: "dms:spotlight"

    HyprlandFocusGrab {
        windows: [spotlightModal.contentWindow]
        active: spotlightModal.useHyprlandFocusGrab && spotlightModal.shouldHaveFocus
    }

    property bool spotlightOpen: false
    property alias spotlightContent: spotlightContentInstance
    property bool openedFromOverview: false
    property bool isClosing: false

    function resetContent() {
        if (!spotlightContent)
            return;
        if (spotlightContent.appLauncher)
            spotlightContent.appLauncher.reset();
        if (spotlightContent.fileSearchController)
            spotlightContent.fileSearchController.reset();
        if (spotlightContent.resetScroll)
            spotlightContent.resetScroll();
        if (spotlightContent.searchField)
            spotlightContent.searchField.text = "";
        spotlightContent.searchMode = "apps";
    }

    function show() {
        openedFromOverview = false;
        isClosing = false;
        resetContent();
        spotlightOpen = true;
        open();
        Qt.callLater(() => {
            if (spotlightContent?.appLauncher)
                spotlightContent.appLauncher.ensureInitialized();
            if (spotlightContent?.searchField)
                spotlightContent.searchField.forceActiveFocus();
        });
    }

    function showWithQuery(query) {
        openedFromOverview = false;
        isClosing = false;
        resetContent();
        spotlightOpen = true;
        if (spotlightContent?.searchField)
            spotlightContent.searchField.text = query;
        open();
        Qt.callLater(() => {
            if (spotlightContent?.appLauncher) {
                spotlightContent.appLauncher.ensureInitialized();
                spotlightContent.appLauncher.searchQuery = query;
            }
            if (spotlightContent?.searchField)
                spotlightContent.searchField.forceActiveFocus();
        });
    }

    function hide() {
        openedFromOverview = false;
        isClosing = true;
        spotlightOpen = false;
        close();
    }

    onDialogClosed: {
        isClosing = false;
        resetContent();
    }

    function toggle() {
        if (spotlightOpen) {
            hide();
        } else {
            show();
        }
    }

    shouldBeVisible: spotlightOpen
    modalWidth: 500
    modalHeight: 600
    backgroundColor: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
    cornerRadius: Theme.cornerRadius
    borderColor: Theme.outlineMedium
    borderWidth: 1
    enableShadow: true
    keepContentLoaded: true
    animationScaleCollapsed: 0.96
    animationDuration: Theme.expressiveDurations.expressiveDefaultSpatial
    animationEnterCurve: Theme.expressiveCurves.expressiveDefaultSpatial
    animationExitCurve: Theme.expressiveCurves.emphasized
    onVisibleChanged: () => {
        if (visible && !spotlightOpen) {
            show();
        }
        if (visible && spotlightContent) {
            Qt.callLater(() => {
                if (spotlightContent.searchField) {
                    spotlightContent.searchField.forceActiveFocus();
                }
            });
        }
    }
    onBackgroundClicked: () => {
        return hide();
    }

    Connections {
        function onCloseAllModalsExcept(excludedModal) {
            if (excludedModal !== spotlightModal && !allowStacking && spotlightOpen) {
                spotlightOpen = false;
            }
        }

        target: ModalManager
    }

    IpcHandler {
        function open(): string {
            spotlightModal.show();
            return "SPOTLIGHT_OPEN_SUCCESS";
        }

        function close(): string {
            spotlightModal.hide();
            return "SPOTLIGHT_CLOSE_SUCCESS";
        }

        function toggle(): string {
            spotlightModal.toggle();
            return "SPOTLIGHT_TOGGLE_SUCCESS";
        }

        function openQuery(query: string): string {
            spotlightModal.showWithQuery(query);
            return "SPOTLIGHT_OPEN_QUERY_SUCCESS";
        }

        function toggleQuery(query: string): string {
            if (spotlightModal.spotlightOpen) {
                spotlightModal.hide();
            } else {
                spotlightModal.showWithQuery(query);
            }
            return "SPOTLIGHT_TOGGLE_QUERY_SUCCESS";
        }

        target: "spotlight"
    }

    SpotlightContent {
        id: spotlightContentInstance

        parentModal: spotlightModal
    }

    directContent: spotlightContentInstance
}
