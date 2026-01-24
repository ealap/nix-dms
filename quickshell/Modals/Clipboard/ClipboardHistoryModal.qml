pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import qs.Common
import qs.Modals.Common
import qs.Services

DankModal {
    id: clipboardHistoryModal

    layerNamespace: "dms:clipboard"

    HyprlandFocusGrab {
        windows: [clipboardHistoryModal.contentWindow]
        active: clipboardHistoryModal.useHyprlandFocusGrab && clipboardHistoryModal.shouldHaveFocus
    }

    property int totalCount: 0
    property var clipboardEntries: []
    property var pinnedEntries: []
    property int pinnedCount: 0
    property string searchText: ""
    property int selectedIndex: 0
    property bool keyboardNavigationActive: false
    property bool showKeyboardHints: false
    property Component clipboardContent
    property int activeImageLoads: 0
    readonly property int maxConcurrentLoads: 3
    readonly property bool clipboardAvailable: DMSService.isConnected && (DMSService.capabilities.length === 0 || DMSService.capabilities.includes("clipboard"))
    readonly property bool wtypeAvailable: SessionService.wtypeAvailable

    Process {
        id: wtypeProcess
        command: ["wtype", "-M", "ctrl", "-P", "v", "-p", "v", "-m", "ctrl"]
        running: false
    }

    Timer {
        id: pasteTimer
        interval: 200
        repeat: false
        onTriggered: wtypeProcess.running = true
    }

    function pasteSelected() {
        if (!keyboardNavigationActive || clipboardEntries.length === 0 || selectedIndex < 0 || selectedIndex >= clipboardEntries.length) {
            return;
        }
        if (!wtypeAvailable) {
            ToastService.showError(I18n.tr("wtype not available - install wtype for paste support"));
            return;
        }
        const entry = clipboardEntries[selectedIndex];
        DMSService.sendRequest("clipboard.copyEntry", {
            "id": entry.id
        }, function (response) {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to copy entry"));
                return;
            }
            instantClose();
            pasteTimer.start();
        });
    }

    function updateFilteredModel() {
        const query = searchText.trim();
        let filtered = [];

        if (query.length === 0) {
            filtered = internalEntries;
        } else {
            const lowerQuery = query.toLowerCase();
            filtered = internalEntries.filter(entry => entry.preview.toLowerCase().includes(lowerQuery));
        }

        // Sort: pinned first, then by ID descending
        filtered.sort((a, b) => {
            if (a.pinned !== b.pinned)
                return b.pinned ? 1 : -1;
            return b.id - a.id;
        });

        clipboardEntries = filtered;
        unpinnedEntries = filtered.filter(e => !e.pinned);
        totalCount = clipboardEntries.length;
        if (unpinnedEntries.length === 0) {
            keyboardNavigationActive = false;
            selectedIndex = 0;
        } else if (selectedIndex >= unpinnedEntries.length) {
            selectedIndex = unpinnedEntries.length - 1;
        }
    }

    property var internalEntries: []
    property var unpinnedEntries: []
    property string activeTab: "recents"

    function toggle() {
        if (shouldBeVisible) {
            hide();
        } else {
            show();
        }
    }

    function show() {
        if (!clipboardAvailable) {
            ToastService.showError(I18n.tr("Clipboard service not available"));
            return;
        }
        open();
        searchText = "";
        activeImageLoads = 0;
        shouldHaveFocus = true;
        refreshClipboard();
        keyboardController.reset();

        Qt.callLater(function () {
            if (contentLoader.item?.searchField) {
                contentLoader.item.searchField.text = "";
                contentLoader.item.searchField.forceActiveFocus();
            }
        });
    }

    function hide() {
        close();
        searchText = "";
        activeImageLoads = 0;
        internalEntries = [];
        clipboardEntries = [];
        keyboardController.reset();
    }

    function refreshClipboard() {
        DMSService.sendRequest("clipboard.getHistory", null, function (response) {
            if (response.error) {
                console.warn("ClipboardHistoryModal: Failed to get history:", response.error);
                return;
            }
            internalEntries = response.result || [];

            pinnedEntries = internalEntries.filter(e => e.pinned);
            pinnedCount = pinnedEntries.length;

            updateFilteredModel();
        });
    }

    function copyEntry(entry) {
        DMSService.sendRequest("clipboard.copyEntry", {
            "id": entry.id
        }, function (response) {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to copy entry"));
                return;
            }
            ToastService.showInfo(entry.isImage ? I18n.tr("Image copied to clipboard") : I18n.tr("Copied to clipboard"));
            hide();
        });
    }

    function deleteEntry(entry) {
        DMSService.sendRequest("clipboard.deleteEntry", {
            "id": entry.id
        }, function (response) {
            if (response.error) {
                console.warn("ClipboardHistoryModal: Failed to delete entry:", response.error);
                return;
            }
            internalEntries = internalEntries.filter(e => e.id !== entry.id);
            updateFilteredModel();
            if (clipboardEntries.length === 0) {
                keyboardNavigationActive = false;
                selectedIndex = 0;
            } else if (selectedIndex >= clipboardEntries.length) {
                selectedIndex = clipboardEntries.length - 1;
            }
        });
    }

    function deletePinnedEntry(entry) {
        clearConfirmDialog.show(I18n.tr("Delete Saved Item?"), I18n.tr("This will permanently remove this saved clipboard item. This action cannot be undone."), function () {
            DMSService.sendRequest("clipboard.deleteEntry", {
                "id": entry.id
            }, function (response) {
                if (response.error) {
                    console.warn("ClipboardHistoryModal: Failed to delete entry:", response.error);
                    return;
                }
                internalEntries = internalEntries.filter(e => e.id !== entry.id);
                updateFilteredModel();
                ToastService.showInfo(I18n.tr("Saved item deleted"));
            });
        }, function () {});
    }

    function pinEntry(entry) {
        DMSService.sendRequest("clipboard.getPinnedCount", null, function (countResponse) {
            if (countResponse.error) {
                ToastService.showError(I18n.tr("Failed to check pin limit"));
                return;
            }

            const maxPinned = 25; // TODO: Get from config
            if (countResponse.result.count >= maxPinned) {
                ToastService.showError(I18n.tr("Maximum pinned entries reached") + " (" + maxPinned + ")");
                return;
            }

            DMSService.sendRequest("clipboard.pinEntry", {
                "id": entry.id
            }, function (response) {
                if (response.error) {
                    ToastService.showError(I18n.tr("Failed to pin entry"));
                    return;
                }
                ToastService.showInfo(I18n.tr("Entry pinned"));
                refreshClipboard();
            });
        });
    }

    function unpinEntry(entry) {
        DMSService.sendRequest("clipboard.unpinEntry", {
            "id": entry.id
        }, function (response) {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to unpin entry"));
                return;
            }
            ToastService.showInfo(I18n.tr("Entry unpinned"));
            refreshClipboard();
        });
    }

    function clearAll() {
        const hasPinned = pinnedCount > 0;
        const message = hasPinned ? I18n.tr("This will delete all unpinned entries. %1 pinned entries will be kept.").arg(pinnedCount) : I18n.tr("This will permanently delete all clipboard history.");

        clearConfirmDialog.show(I18n.tr("Clear History?"), message, function () {
            DMSService.sendRequest("clipboard.clearHistory", null, function (response) {
                if (response.error) {
                    console.warn("ClipboardHistoryModal: Failed to clear history:", response.error);
                    return;
                }
                refreshClipboard();
                if (hasPinned) {
                    ToastService.showInfo(I18n.tr("History cleared. %1 pinned entries kept.").arg(pinnedCount));
                }
            });
        }, function () {});
    }

    function getEntryPreview(entry) {
        return entry.preview || "";
    }

    function getEntryType(entry) {
        if (entry.isImage) {
            return "image";
        }
        if (entry.size > ClipboardConstants.longTextThreshold) {
            return "long_text";
        }
        return "text";
    }

    visible: false
    modalWidth: ClipboardConstants.modalWidth
    modalHeight: ClipboardConstants.modalHeight
    backgroundColor: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
    cornerRadius: Theme.cornerRadius
    borderColor: Theme.outlineMedium
    borderWidth: 1
    enableShadow: true
    onBackgroundClicked: hide()
    modalFocusScope.Keys.onPressed: function (event) {
        keyboardController.handleKey(event);
    }
    content: clipboardContent

    ClipboardKeyboardController {
        id: keyboardController
        modal: clipboardHistoryModal
    }

    ConfirmModal {
        id: clearConfirmDialog
        confirmButtonText: I18n.tr("Clear All")
        confirmButtonColor: Theme.primary
        onVisibleChanged: {
            if (visible) {
                clipboardHistoryModal.shouldHaveFocus = false;
            } else if (clipboardHistoryModal.shouldBeVisible) {
                clipboardHistoryModal.shouldHaveFocus = true;
                clipboardHistoryModal.modalFocusScope.forceActiveFocus();
                if (clipboardHistoryModal.contentLoader.item?.searchField) {
                    clipboardHistoryModal.contentLoader.item.searchField.forceActiveFocus();
                }
            }
        }
    }

    property var confirmDialog: clearConfirmDialog

    clipboardContent: Component {
        ClipboardContent {
            modal: clipboardHistoryModal
            clearConfirmDialog: clipboardHistoryModal.confirmDialog
        }
    }
}
