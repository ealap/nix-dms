import QtQuick
import qs.Services

QtObject {
    id: keyboardController

    required property var modal

    function reset() {
        ClipboardService.selectedIndex = 0;
        ClipboardService.keyboardNavigationActive = false;
        modal.showKeyboardHints = false;
    }

    function selectNext() {
        if (!ClipboardService.clipboardEntries || ClipboardService.clipboardEntries.length === 0) {
            return;
        }
        ClipboardService.keyboardNavigationActive = true;
        ClipboardService.selectedIndex = Math.min(ClipboardService.selectedIndex + 1, ClipboardService.clipboardEntries.length - 1);
    }

    function selectPrevious() {
        if (!ClipboardService.clipboardEntries || ClipboardService.clipboardEntries.length === 0) {
            return;
        }
        ClipboardService.keyboardNavigationActive = true;
        ClipboardService.selectedIndex = Math.max(ClipboardService.selectedIndex - 1, 0);
    }

    function copySelected() {
        if (!ClipboardService.clipboardEntries || ClipboardService.clipboardEntries.length === 0 || ClipboardService.selectedIndex < 0 || ClipboardService.selectedIndex >= ClipboardService.clipboardEntries.length) {
            return;
        }
        const selectedEntry = ClipboardService.clipboardEntries[ClipboardService.selectedIndex];
        modal.copyEntry(selectedEntry);
    }

    function deleteSelected() {
        if (!ClipboardService.clipboardEntries || ClipboardService.clipboardEntries.length === 0 || ClipboardService.selectedIndex < 0 || ClipboardService.selectedIndex >= ClipboardService.clipboardEntries.length) {
            return;
        }
        const selectedEntry = ClipboardService.clipboardEntries[ClipboardService.selectedIndex];
        modal.deleteEntry(selectedEntry);
    }

    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Escape:
            if (ClipboardService.keyboardNavigationActive) {
                ClipboardService.keyboardNavigationActive = false;
            } else {
                modal.hide();
            }
            event.accepted = true;
            return;
        case Qt.Key_Down:
        case Qt.Key_Tab:
            if (!ClipboardService.keyboardNavigationActive) {
                ClipboardService.keyboardNavigationActive = true;
                ClipboardService.selectedIndex = 0;
            } else {
                selectNext();
            }
            event.accepted = true;
            return;
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            if (!ClipboardService.keyboardNavigationActive) {
                ClipboardService.keyboardNavigationActive = true;
                ClipboardService.selectedIndex = 0;
            } else if (ClipboardService.selectedIndex === 0) {
                ClipboardService.keyboardNavigationActive = false;
            } else {
                selectPrevious();
            }
            event.accepted = true;
            return;
        case Qt.Key_F10:
            modal.showKeyboardHints = !modal.showKeyboardHints;
            event.accepted = true;
            return;
        }

        if (event.modifiers & Qt.ControlModifier) {
            switch (event.key) {
            case Qt.Key_N:
            case Qt.Key_J:
                if (!ClipboardService.keyboardNavigationActive) {
                    ClipboardService.keyboardNavigationActive = true;
                    ClipboardService.selectedIndex = 0;
                } else {
                    selectNext();
                }
                event.accepted = true;
                return;
            case Qt.Key_P:
            case Qt.Key_K:
                if (!ClipboardService.keyboardNavigationActive) {
                    ClipboardService.keyboardNavigationActive = true;
                    ClipboardService.selectedIndex = 0;
                } else if (ClipboardService.selectedIndex === 0) {
                    ClipboardService.keyboardNavigationActive = false;
                } else {
                    selectPrevious();
                }
                event.accepted = true;
                return;
            case Qt.Key_C:
                if (ClipboardService.keyboardNavigationActive) {
                    copySelected();
                    event.accepted = true;
                }
                return;
            }
        }

        if (event.modifiers & Qt.ShiftModifier) {
            switch (event.key) {
            case Qt.Key_Delete:
                modal.clearAll();
                modal.hide();
                event.accepted = true;
                return;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (ClipboardService.keyboardNavigationActive) {
                    modal.pasteSelected();
                    event.accepted = true;
                }
                return;
            }
        }

        if (ClipboardService.keyboardNavigationActive) {
            switch (event.key) {
            case Qt.Key_Return:
            case Qt.Key_Enter:
                copySelected();
                event.accepted = true;
                return;
            case Qt.Key_Delete:
                deleteSelected();
                event.accepted = true;
                return;
            }
        }
    }
}
