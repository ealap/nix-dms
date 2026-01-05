import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    property string iconName: ""
    property string title: ""
    property string description: ""

    readonly property real iconContainerSize: Math.round(Theme.iconSize * 1.5)

    height: Math.round(Theme.fontSizeMedium * 6.4)
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHigh

    Column {
        anchors.centerIn: parent
        spacing: Theme.spacingS

        Rectangle {
            width: root.iconContainerSize
            height: root.iconContainerSize
            radius: Math.round(root.iconContainerSize * 0.28)
            color: Theme.primaryContainer
            anchors.horizontalCenter: parent.horizontalCenter

            DankIcon {
                anchors.centerIn: parent
                name: root.iconName
                size: Theme.iconSize - 4
                color: Theme.primary
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            StyledText {
                text: root.title
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.description
                font.pixelSize: Theme.fontSizeSmall - 1
                color: Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
