import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NToggle {
    label: I18n.tr("panels.location.date-time-12hour-format-label")
    description: I18n.tr("panels.location.date-time-12hour-format-description")
    checked: Settings.data.location.use12hourFormat
    onToggled: checked => Settings.data.location.use12hourFormat = checked
  }
}
