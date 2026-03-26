pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  // Night Light properties - directly bound to settings
  readonly property var params: Settings.data.nightLight
  property var lastCommand: []

  // Crash tracking for auto-restart
  property int _crashCount: 0
  property int _maxCrashes: 5

  // Kill any stale wlsunset processes on startup to prevent issues after shell restart
  Component.onCompleted: {
    killStaleProcess.running = true;
  }

  Process {
    id: killStaleProcess
    running: false
    command: ["pkill", "-x", "wlsunset"]
    onExited: function (code, status) {
      if (code === 0) {
        Logger.i("NightLight", "Killed stale wlsunset process from previous session");
      }
      // Now apply the settings after cleanup
      root.apply();
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    repeat: false
    onTriggered: {
      if (root.params.enabled && !runner.running) {
        Logger.w("NightLight", "Restarting after crash...");
        runner.running = true;
      }
    }
  }

  function apply(force = false) {
    if (!params.enabled) {
      runner.running = false;
      return;
    }

    var command = buildCommand();

    // Compare with previous command to avoid unnecessary restart
    if (force || JSON.stringify(command) !== JSON.stringify(lastCommand)) {
      lastCommand = command;
      runner.command = command;

      // Set running to false so it may restart below if still enabled
      runner.running = false;
    }
    runner.running = true;
  }

  function buildCommand() {
    var temp = params.temperature;
    var cmd = ["wlsunset"];
    cmd.push("-t", `${temp}`, "-T", `${parseInt(temp) + 10}`);
    cmd.push("-S", "00:00");
    cmd.push("-s", "00:00");
    cmd.push("-d", 1);
    return cmd;
  }

  Connections {
    target: Settings.data.nightLight
    function onEnabledChanged() {
      apply();
      const enabled = !!Settings.data.nightLight.enabled;
      ToastService.showNotice(I18n.tr("common.night-light"), enabled ? I18n.tr("common.enabled") : I18n.tr("common.disabled"), enabled ? "nightlight-on" : "nightlight-off");
    }
    function onTemperatureChanged() {
      apply();
    }
  }

  Timer {
    id: resumeRetryTimer
    interval: 2000
    repeat: false
    onTriggered: {
      Logger.i("NightLight", "Resume retry - re-applying night light again");
      root.apply(true);
    }
  }

  Connections {
    target: Time
    function onResumed() {
      Logger.i("NightLight", "System resumed - re-applying night light");
      root.apply(true);
      resumeRetryTimer.restart();
    }
  }

  Process {
    id: runner
    running: false
    onStarted: {
      Logger.i("NightLight", "Wlsunset started:", runner.command);
      if (root._crashCount > 0) {
        root._crashCount = 0;
      }
    }
    onExited: function (code, status) {
      if (root.params.enabled) {
        root._crashCount++;
        if (root._crashCount <= root._maxCrashes) {
          Logger.w("NightLight", "Wlsunset exited unexpectedly (code: " + code + "), restarting in 2s... (attempt " + root._crashCount + "/" + root._maxCrashes + ")");
          restartTimer.start();
        } else {
          Logger.e("NightLight", "Wlsunset crashed too many times (" + root._maxCrashes + "), giving up");
        }
      } else {
        Logger.i("NightLight", "Wlsunset exited (disabled):", code, status);
        root._crashCount = 0;
      }
    }
  }
}
