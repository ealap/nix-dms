import QtQuick
import qs.Common

MouseArea {
    id: root

    property bool disabled: false
    property color stateColor: Theme.surfaceText
    property real cornerRadius: parent && parent.radius !== undefined ? parent.radius : Theme.cornerRadius
    property var tooltipText: null
    property string tooltipSide: "bottom"

    readonly property real stateOpacity: disabled ? 0 : pressed ? 0.12 : containsMouse ? 0.08 : 0

    anchors.fill: parent
    cursorShape: disabled ? undefined : Qt.PointingHandCursor
    hoverEnabled: true

    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: Qt.rgba(stateColor.r, stateColor.g, stateColor.b, stateOpacity)
    }

    Timer {
        id: hoverDelay
        interval: 400
        repeat: false
        onTriggered: {
            tooltip.show(root.tooltipText, root, 0, 0, root.tooltipSide);
        }
    }

    onEntered: {
        if (!tooltipText)
            return;
        hoverDelay.restart();
    }

    onExited: {
        if (!tooltipText)
            return;
        hoverDelay.stop();
        tooltip.hide();
    }

    DankTooltipV2 {
        id: tooltip
    }
}
