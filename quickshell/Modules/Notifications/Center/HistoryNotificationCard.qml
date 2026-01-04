import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

Rectangle {
    id: root

    required property var historyItem
    property bool isSelected: false
    property bool keyboardNavigationActive: false

    width: parent ? parent.width : 400
    height: 116
    radius: Theme.cornerRadius
    clip: true

    color: {
        if (isSelected && keyboardNavigationActive)
            return Theme.primaryPressed;
        return Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency);
    }
    border.color: {
        if (isSelected && keyboardNavigationActive)
            return Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5);
        if (historyItem.urgency === 2)
            return Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3);
        return Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.05);
    }
    border.width: {
        if (isSelected && keyboardNavigationActive)
            return 1.5;
        if (historyItem.urgency === 2)
            return 2;
        return 1;
    }

    Behavior on border.color {
        ColorAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: historyItem.urgency === 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: Theme.primary
            }
            GradientStop {
                position: 0.02
                color: Theme.primary
            }
            GradientStop {
                position: 0.021
                color: "transparent"
            }
        }
    }

    Item {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 12
        anchors.leftMargin: 16
        anchors.rightMargin: 56
        height: 92

        DankCircularImage {
            id: iconContainer
            readonly property bool hasNotificationImage: historyItem.image && historyItem.image !== ""

            width: 63
            height: 63
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: 14

            imageSource: {
                if (hasNotificationImage)
                    return historyItem.image;
                if (historyItem.appIcon) {
                    const appIcon = historyItem.appIcon;
                    if (appIcon.startsWith("file://") || appIcon.startsWith("http://") || appIcon.startsWith("https://"))
                        return appIcon;
                    return Quickshell.iconPath(appIcon, true);
                }
                return "";
            }

            hasImage: hasNotificationImage
            fallbackIcon: ""
            fallbackText: {
                const appName = historyItem.appName || "?";
                return appName.charAt(0).toUpperCase();
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: width / 2
                color: "transparent"
                border.color: root.color
                border.width: 5
                visible: parent.hasImage
                antialiasing: true
            }
        }

        Rectangle {
            anchors.left: iconContainer.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            color: "transparent"

            Item {
                width: parent.width
                height: parent.height
                anchors.top: parent.top
                anchors.topMargin: -2

                Column {
                    width: parent.width
                    spacing: 2

                    StyledText {
                        width: parent.width
                        text: {
                            const timeStr = NotificationService.formatHistoryTime(historyItem.timestamp);
                            const appName = historyItem.appName || "";
                            return timeStr.length > 0 ? `${appName} • ${timeStr}` : appName;
                        }
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    StyledText {
                        text: historyItem.summary || ""
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        width: parent.width
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        visible: text.length > 0
                    }

                    StyledText {
                        id: descriptionText
                        text: historyItem.htmlBody || historyItem.body || ""
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        width: parent.width
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        visible: text.length > 0
                        linkColor: Theme.primary
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }
            }
        }
    }

    DankActionButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 12
        anchors.rightMargin: 16
        iconName: "close"
        iconSize: 18
        buttonSize: 28
        onClicked: NotificationService.removeFromHistory(historyItem.id)
    }
}
