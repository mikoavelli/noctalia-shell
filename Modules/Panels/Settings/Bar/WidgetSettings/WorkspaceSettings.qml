import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  property string valueLabelMode: widgetData.labelMode !== undefined ? widgetData.labelMode : widgetMetadata.labelMode
  property bool valueHideUnoccupied: widgetData.hideUnoccupied !== undefined ? widgetData.hideUnoccupied : widgetMetadata.hideUnoccupied
  property bool valueFollowFocusedScreen: widgetData.followFocusedScreen !== undefined ? widgetData.followFocusedScreen : widgetMetadata.followFocusedScreen
  property int valueCharacterCount: widgetData.characterCount !== undefined ? widgetData.characterCount : widgetMetadata.characterCount

  // Grouped mode settings
  property bool valueShowLabelsOnlyWhenOccupied: widgetData.showLabelsOnlyWhenOccupied !== undefined ? widgetData.showLabelsOnlyWhenOccupied : widgetMetadata.showLabelsOnlyWhenOccupied
  property bool valueEnableScrollWheel: widgetData.enableScrollWheel !== undefined ? widgetData.enableScrollWheel : widgetMetadata.enableScrollWheel
  property string valueFocusedColor: widgetData.focusedColor !== undefined ? widgetData.focusedColor : widgetMetadata.focusedColor
  property string valueOccupiedColor: widgetData.occupiedColor !== undefined ? widgetData.occupiedColor : widgetMetadata.occupiedColor
  property string valueEmptyColor: widgetData.emptyColor !== undefined ? widgetData.emptyColor : widgetMetadata.emptyColor
  property real valuePillSize: widgetData.pillSize !== undefined ? widgetData.pillSize : widgetMetadata.pillSize

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.labelMode = valueLabelMode;
    settings.hideUnoccupied = valueHideUnoccupied;
    settings.characterCount = valueCharacterCount;
    settings.followFocusedScreen = valueFollowFocusedScreen;
    settings.showLabelsOnlyWhenOccupied = valueShowLabelsOnlyWhenOccupied;
    settings.enableScrollWheel = valueEnableScrollWheel;
    settings.focusedColor = valueFocusedColor;
    settings.occupiedColor = valueOccupiedColor;
    settings.emptyColor = valueEmptyColor;
    settings.pillSize = valuePillSize;
    settingsChanged(settings);
  }

  NComboBox {
    id: labelModeCombo
    label: I18n.tr("bar.workspace.label-mode-label")
    description: I18n.tr("bar.workspace.label-mode-description")
    model: [
      {
        "key": "none",
        "name": I18n.tr("common.none")
      },
      {
        "key": "index",
        "name": I18n.tr("options.workspace-labels.index")
      },
      {
        "key": "name",
        "name": I18n.tr("options.workspace-labels.name")
      },
      {
        "key": "index+name",
        "name": I18n.tr("options.workspace-labels.index-and-name")
      }
    ]
    currentKey: widgetData.labelMode || widgetMetadata.labelMode
    onSelected: key => {
                  valueLabelMode = key;
                  saveSettings();
                }
    minimumWidth: 200
  }

  NSpinBox {
    label: I18n.tr("bar.workspace.character-count-label")
    description: I18n.tr("bar.workspace.character-count-description")
    from: 1
    to: 10
    value: valueCharacterCount
    onValueChanged: {
      valueCharacterCount = value;
      saveSettings();
    }
    visible: valueLabelMode === "name"
  }

  NValueSlider {
    label: I18n.tr("bar.workspace.pill-size-label")
    description: I18n.tr("bar.workspace.pill-size-description")
    from: 0.4
    to: 1.0
    stepSize: 0.01
    value: valuePillSize
    onMoved: value => {
               valuePillSize = value;
               saveSettings();
             }
    text: Math.round(valuePillSize * 100) + "%"
  }

  NToggle {
    label: I18n.tr("bar.workspace.hide-unoccupied-label")
    description: I18n.tr("bar.workspace.hide-unoccupied-description")
    checked: valueHideUnoccupied
    onToggled: checked => {
                 valueHideUnoccupied = checked;
                 saveSettings();
               }
  }

  NToggle {
    label: I18n.tr("bar.workspace.show-labels-only-when-occupied-label")
    description: I18n.tr("bar.workspace.show-labels-only-when-occupied-description")
    checked: valueShowLabelsOnlyWhenOccupied
    onToggled: checked => {
                 valueShowLabelsOnlyWhenOccupied = checked;
                 saveSettings();
               }
  }

  NToggle {
    label: I18n.tr("bar.workspace.follow-focused-screen-label")
    description: I18n.tr("bar.workspace.follow-focused-screen-description")
    checked: valueFollowFocusedScreen
    onToggled: checked => {
                 valueFollowFocusedScreen = checked;
                 saveSettings();
               }
  }

  NToggle {
    label: I18n.tr("bar.workspace.enable-scrollwheel-label")
    description: I18n.tr("bar.workspace.enable-scrollwheel-description")
    checked: valueEnableScrollWheel
    onToggled: checked => {
                 valueEnableScrollWheel = checked;
                 saveSettings();
               }
  }

  NDivider {
    Layout.fillWidth: true
  }

  NComboBox {
    id: focusedColorCombo
    label: I18n.tr("bar.workspace.focused-color-label")
    description: I18n.tr("bar.workspace.focused-color-description")
    model: [
      {
        "key": "none",
        "name": I18n.tr("common.none")
      },
      {
        "key": "primary",
        "name": I18n.tr("common.primary")
      },
      {
        "key": "secondary",
        "name": I18n.tr("common.secondary")
      },
      {
        "key": "tertiary",
        "name": I18n.tr("common.tertiary")
      }
    ]
    currentKey: valueFocusedColor
    onSelected: key => {
                  valueFocusedColor = key;
                  saveSettings();
                }
    minimumWidth: 200
  }

  NComboBox {
    id: occupiedColorCombo
    label: I18n.tr("bar.workspace.occupied-color-label")
    description: I18n.tr("bar.workspace.occupied-color-description")
    model: [
      {
        "key": "none",
        "name": I18n.tr("common.none")
      },
      {
        "key": "primary",
        "name": I18n.tr("common.primary")
      },
      {
        "key": "secondary",
        "name": I18n.tr("common.secondary")
      },
      {
        "key": "tertiary",
        "name": I18n.tr("common.tertiary")
      }
    ]
    currentKey: valueOccupiedColor
    onSelected: key => {
                  valueOccupiedColor = key;
                  saveSettings();
                }
    minimumWidth: 200
  }

  NComboBox {
    id: emptyColorCombo
    label: I18n.tr("bar.workspace.empty-color-label")
    description: I18n.tr("bar.workspace.empty-color-description")
    model: [
      {
        "key": "none",
        "name": I18n.tr("common.none")
      },
      {
        "key": "primary",
        "name": I18n.tr("common.primary")
      },
      {
        "key": "secondary",
        "name": I18n.tr("common.secondary")
      },
      {
        "key": "tertiary",
        "name": I18n.tr("common.tertiary")
      }
    ]
    currentKey: valueEmptyColor
    onSelected: key => {
                  valueEmptyColor = key;
                  saveSettings();
                }
    minimumWidth: 200
  }
}
