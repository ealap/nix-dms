import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Widgets

Popup {
    id: processContextMenu

    property var processData: null

    function show(x, y) {
        let finalX = x;
        let finalY = y;

        if (processContextMenu.parent) {
            const parentWidth = processContextMenu.parent.width;
            const parentHeight = processContextMenu.parent.height;
            const menuWidth = processContextMenu.width;
            const menuHeight = processContextMenu.height;

            if (finalX + menuWidth > parentWidth)
                finalX = Math.max(0, parentWidth - menuWidth);
            if (finalY + menuHeight > parentHeight)
                finalY = Math.max(0, parentHeight - menuHeight);
        }

        processContextMenu.x = finalX;
        processContextMenu.y = finalY;
        open();
    }

    width: 200
    height: menuColumn.implicitHeight + Theme.spacingS * 2
    padding: 0
    modal: false
    closePolicy: Popup.CloseOnEscape

    onClosed: closePolicy = Popup.CloseOnEscape
    onOpened: outsideClickTimer.start()

    Timer {
        id: outsideClickTimer
        interval: 100
        onTriggered: processContextMenu.closePolicy = Popup.CloseOnEscape | Popup.CloseOnPressOutside
    }

    background: Rectangle {
        color: "transparent"
    }

    contentItem: Rectangle {
        color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
        radius: Theme.cornerRadius
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.08)
        border.width: 1

        Column {
            id: menuColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: 1

            MenuItem {
                text: I18n.tr("Copy PID")
                iconName: "tag"
                onClicked: {
                    if (processContextMenu.processData)
                        Quickshell.execDetached(["dms", "cl", "copy", processContextMenu.processData.pid.toString()]);
                    processContextMenu.close();
                }
            }

            MenuItem {
                text: I18n.tr("Copy Name")
                iconName: "content_copy"
                onClicked: {
                    if (processContextMenu.processData) {
                        const name = processContextMenu.processData.command || "";
                        Quickshell.execDetached(["dms", "cl", "copy", name]);
                    }
                    processContextMenu.close();
                }
            }

            MenuItem {
                text: I18n.tr("Copy Full Command")
                iconName: "code"
                onClicked: {
                    if (processContextMenu.processData) {
                        const fullCmd = processContextMenu.processData.fullCommand || processContextMenu.processData.command || "";
                        Quickshell.execDetached(["dms", "cl", "copy", fullCmd]);
                    }
                    processContextMenu.close();
                }
            }

            Rectangle {
                width: parent.width - Theme.spacingS * 2
                height: 1
                anchors.horizontalCenter: parent.horizontalCenter
                color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.15)
            }

            MenuItem {
                text: I18n.tr("Kill Process")
                iconName: "close"
                dangerous: true
                enabled: processContextMenu.processData
                onClicked: {
                    if (processContextMenu.processData)
                        Quickshell.execDetached(["kill", processContextMenu.processData.pid.toString()]);
                    processContextMenu.close();
                }
            }

            MenuItem {
                text: I18n.tr("Force Kill (SIGKILL)")
                iconName: "dangerous"
                dangerous: true
                enabled: processContextMenu.processData && processContextMenu.processData.pid > 1000
                onClicked: {
                    if (processContextMenu.processData)
                        Quickshell.execDetached(["kill", "-9", processContextMenu.processData.pid.toString()]);
                    processContextMenu.close();
                }
            }
        }
    }

    component MenuItem: Rectangle {
        id: menuItem

        property string text: ""
        property string iconName: ""
        property bool dangerous: false
        property bool enabled: true

        signal clicked

        width: parent.width
        height: 32
        radius: Theme.cornerRadius
        color: {
            if (!enabled)
                return "transparent";
            if (dangerous)
                return menuItemArea.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12) : "transparent";
            return menuItemArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : "transparent";
        }
        opacity: enabled ? 1 : 0.5

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DankIcon {
                name: menuItem.iconName
                size: 16
                color: {
                    if (!menuItem.enabled)
                        return Theme.surfaceVariantText;
                    if (menuItem.dangerous && menuItemArea.containsMouse)
                        return Theme.error;
                    return Theme.surfaceText;
                }
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: menuItem.text
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Normal
                color: {
                    if (!menuItem.enabled)
                        return Theme.surfaceVariantText;
                    if (menuItem.dangerous && menuItemArea.containsMouse)
                        return Theme.error;
                    return Theme.surfaceText;
                }
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: menuItemArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: menuItem.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: menuItem.enabled
            onClicked: menuItem.clicked()
        }
    }
}
