import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Cards
import qs.Modules.MainScreen
import qs.Services.Location
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  panelContent: Item {
    id: panelContent
    anchors.fill: parent

    readonly property real contentPreferredWidth: Math.round(420 * Style.uiScaleRatio)
    readonly property real contentPreferredHeight: content.implicitHeight + (Style.marginL * 2)

    ColumnLayout {
      id: content
      x: Style.marginL
      y: Style.marginL
      width: parent.width - (Style.marginL * 2)
      spacing: Style.marginL

      // All clock panel cards
      Repeater {
        model: Settings.data.calendar.cards
        Loader {
          active: modelData.enabled
          visible: active
          Layout.fillWidth: true
          sourceComponent: {
            switch (modelData.id) {
            case "calendar-month-card":
              return calendarMonthCard;
            default:
              return null;
            }
          }
        }
      }
    }
  }

  Component {
    id: calendarMonthCard
    CalendarMonthCard {
      Layout.fillWidth: true
    }
  }
}
