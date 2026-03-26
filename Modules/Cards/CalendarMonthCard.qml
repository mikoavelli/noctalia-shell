import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Location
import qs.Services.System
import qs.Services.UI
import qs.Widgets

// Calendar month grid with navigation
NBox {
  id: root
  Layout.fillWidth: true
  implicitHeight: calendarContent.implicitHeight + Style.marginXL

  // Internal state - independent from header
  readonly property var now: Time.now
  property int calendarMonth: now.getMonth()
  property int calendarYear: now.getFullYear()
  readonly property int firstDayOfWeek: -1 // Use locale

  // Navigation functions
  function navigateToPreviousMonth() {
    let newDate = new Date(root.calendarYear, root.calendarMonth - 1, 1);
    root.calendarYear = newDate.getFullYear();
    root.calendarMonth = newDate.getMonth();
  }

  function navigateToNextMonth() {
    let newDate = new Date(root.calendarYear, root.calendarMonth + 1, 1);
    root.calendarYear = newDate.getFullYear();
    root.calendarMonth = newDate.getMonth();
  }

  // Wheel handler for month navigation
  WheelHandler {
    id: wheelHandler
    target: root
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function (event) {
      if (event.angleDelta.y > 0) {
        // Scroll up - go to previous month
        root.navigateToPreviousMonth();
        event.accepted = true;
      } else if (event.angleDelta.y < 0) {
        // Scroll down - go to next month
        root.navigateToNextMonth();
        event.accepted = true;
      }
    }
  }

  ColumnLayout {
    id: calendarContent
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginS

    // Navigation row
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      Item {
        Layout.preferredWidth: Style.marginS
      }

      NText {
        text: I18n.locale.monthName(root.calendarMonth, Locale.LongFormat).toUpperCase() + " " + root.calendarYear
        pointSize: Style.fontSizeM
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }

      NDivider {
        Layout.fillWidth: true
      }

      NIconButton {
        icon: "chevron-left"
        onClicked: root.navigateToPreviousMonth()
      }

      NIconButton {
        icon: "calendar"
        onClicked: {
          root.calendarMonth = root.now.getMonth();
          root.calendarYear = root.now.getFullYear();
        }
      }

      NIconButton {
        icon: "chevron-right"
        onClicked: root.navigateToNextMonth()
      }
    }

    // Day names header
    RowLayout {
      Layout.fillWidth: true
      spacing: 0

      GridLayout {
        Layout.fillWidth: true
        columns: 7
        rows: 1
        columnSpacing: 0
        rowSpacing: 0

        Repeater {
          model: 7
          Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.fontSizeS * 2

            NText {
              anchors.centerIn: parent
              text: {
                let dayIndex = (root.firstDayOfWeek + index) % 7;
                const dayName = I18n.locale.dayName(dayIndex, Locale.ShortFormat);
                return dayName.substring(0, 2).toUpperCase();
              }
              color: Color.mPrimary
              pointSize: Style.fontSizeS
              font.weight: Style.fontWeightBold
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }

    // Calendar grid
    GridLayout {
      id: grid
      Layout.fillWidth: true
      columns: 7
      columnSpacing: Style.marginXXS
      rowSpacing: Style.marginXXS

      property int month: root.calendarMonth
      property int year: root.calendarYear

      property var daysModel: {
        const firstOfMonth = new Date(year, month, 1);
        const lastOfMonth = new Date(year, month + 1, 0);
        const daysInMonth = lastOfMonth.getDate();
        const firstDayOfWeek = root.firstDayOfWeek;
        const firstOfMonthDayOfWeek = firstOfMonth.getDay();
        let daysBefore = (firstOfMonthDayOfWeek - firstDayOfWeek + 7) % 7;
        const lastOfMonthDayOfWeek = lastOfMonth.getDay();
        const daysAfter = (firstDayOfWeek - lastOfMonthDayOfWeek - 1 + 7) % 7;
        const days = [];
        const today = new Date();

        // Previous month days
        const prevMonth = new Date(year, month, 0);
        const prevMonthDays = prevMonth.getDate();
        for (var i = daysBefore - 1; i >= 0; i--) {
          const day = prevMonthDays - i;
          days.push({
                      "day": day,
                      "month": month - 1,
                      "year": month === 0 ? year - 1 : year,
                      "today": false,
                      "currentMonth": false
                    });
        }

        // Current month days
        for (var day = 1; day <= daysInMonth; day++) {
          const date = new Date(year, month, day);
          const isToday = date.getFullYear() === today.getFullYear() && date.getMonth() === today.getMonth() && date.getDate() === today.getDate();
          days.push({
                      "day": day,
                      "month": month,
                      "year": year,
                      "today": isToday,
                      "currentMonth": true
                    });
        }

        // Next month days
        for (var i = 1; i <= daysAfter; i++) {
          days.push({
                      "day": i,
                      "month": month + 1,
                      "year": month === 11 ? year + 1 : year,
                      "today": false,
                      "currentMonth": false
                    });
        }

        return days;
      }

      Repeater {
        model: grid.daysModel

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.baseWidgetSize * 0.9

          Rectangle {
            width: Style.baseWidgetSize * 0.9
            height: Style.baseWidgetSize * 0.9
            anchors.centerIn: parent
            radius: Style.radiusM
            color: modelData.today ? Color.mSecondary : "transparent"

            NText {
              anchors.centerIn: parent
              text: modelData.day
              color: {
                if (modelData.today)
                  return Color.mOnSecondary;
                if (modelData.currentMonth)
                  return Color.mOnSurface;
                return Color.mOnSurfaceVariant;
              }
              opacity: modelData.currentMonth ? 1.0 : 0.4
              pointSize: Style.fontSizeM
              font.weight: modelData.today ? Style.fontWeightBold : Style.fontWeightMedium
            }

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }
        }
      }
    }
  }
}
