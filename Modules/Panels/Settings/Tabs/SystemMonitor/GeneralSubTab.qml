import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property var screen

  NTextInput {
    label: I18n.tr("panels.system-monitor.external-monitor-label")
    description: I18n.tr("panels.system-monitor.external-monitor-description")
    placeholderText: I18n.tr("panels.system-monitor.external-monitor-placeholder")
    text: Settings.data.systemMonitor.externalMonitor
    defaultValue: Settings.getDefaultValue("systemMonitor.externalMonitor")
    onTextChanged: Settings.data.systemMonitor.externalMonitor = text
  }
}
