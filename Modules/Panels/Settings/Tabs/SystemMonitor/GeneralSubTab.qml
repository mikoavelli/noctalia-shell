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

  NToggle {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    label: I18n.tr("panels.system-monitor.enable-dgpu-monitoring-label")
    description: I18n.tr("panels.system-monitor.enable-dgpu-monitoring-description")
    checked: Settings.data.systemMonitor.enableDgpuMonitoring
    defaultValue: Settings.getDefaultValue("systemMonitor.enableDgpuMonitoring")
    onToggled: checked => Settings.data.systemMonitor.enableDgpuMonitoring = checked
  }

  NDivider {
    Layout.fillWidth: true
  }

  NTextInput {
    label: I18n.tr("panels.system-monitor.external-monitor-label")
    description: I18n.tr("panels.system-monitor.external-monitor-description")
    placeholderText: I18n.tr("panels.system-monitor.external-monitor-placeholder")
    text: Settings.data.systemMonitor.externalMonitor
    defaultValue: Settings.getDefaultValue("systemMonitor.externalMonitor")
    onTextChanged: Settings.data.systemMonitor.externalMonitor = text
  }
}
