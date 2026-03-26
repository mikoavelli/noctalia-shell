import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property var timeOptions

  signal checkWlsunset

  NToggle {
    label: I18n.tr("panels.display.night-light-enable-label")
    description: I18n.tr("panels.display.night-light-enable-description")
    checked: Settings.data.nightLight.enabled
    onToggled: checked => {
                 if (checked) {
                   root.checkWlsunset();
                 } else {
                   Settings.data.nightLight.enabled = false;
                   NightLightService.apply();
                   ToastService.showNotice(I18n.tr("common.night-light"), I18n.tr("common.disabled"), "nightlight-off");
                 }
               }
  }

  ColumnLayout {
    enabled: Settings.data.nightLight.enabled
    spacing: Style.marginL
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("panels.display.night-light-temperature-label")
      description: I18n.tr("panels.display.night-light-temperature-description")
      Layout.fillWidth: true
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NSlider {
        id: tempSlider
        Layout.fillWidth: true
        from: 1000
        to: 6500
        stepSize: 10
        value: Settings.data.nightLight.temperature

        onPressedChanged: {
          if (!pressed) {
            Settings.data.nightLight.temperature = Math.round(value);
          }
        }
      }

      NText {
        text: tempSlider.value + "K"
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}
