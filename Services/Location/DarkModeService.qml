pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  property bool initComplete: false
  property bool nextDarkModeState: false

  Connections {
    target: Time
    function onResumed() {
      Logger.i("DarkModeService", "System resumed - re-evaluating dark mode");
      root.update();
      resumeRetryTimer.restart();
    }
  }

  Timer {
    id: timer
    onTriggered: {
      Settings.data.colorSchemes.darkMode = root.nextDarkModeState;
      root.update();
    }
  }

  Timer {
    id: resumeRetryTimer
    interval: 2000
    repeat: false
    onTriggered: {
      Logger.i("DarkModeService", "Resume retry - re-evaluating dark mode again");
      root.update();
    }
  }

  function init() {
    Logger.i("DarkModeService", "Service started");
    root.update();
  }

  function update() {
    if (LocationService.data.weather) {
      const changes = collectWeatherChanges(LocationService.data.weather);
      initComplete = true;
      applyCurrentMode(changes);
      scheduleNextMode(changes);
    }
  }

  function parseTime(timeString) {
    const parts = timeString.split(":").map(Number);
    return {
      "hour": parts[0],
      "minute": parts[1]
    };
  }

  function collectWeatherChanges(weather) {
    const changes = [];

    if (Date.now() < Date.parse(weather.daily.sunrise[0])) {
      // The sun has not risen yet
      changes.push({
                     "time": Date.now() - 1,
                     "darkMode": true
                   });
    }

    for (var i = 0; i < weather.daily.sunrise.length; i++) {
      changes.push({
                     "time": Date.parse(weather.daily.sunrise[i]),
                     "darkMode": false
                   });
      changes.push({
                     "time": Date.parse(weather.daily.sunset[i]),
                     "darkMode": true
                   });
    }

    return changes;
  }

  function applyCurrentMode(changes) {
    const now = Date.now();
    Logger.i("DarkModeService", `Applying mode at ${new Date(now).toLocaleString()} (${now})`);

    // changes.findLast(change => change.time < now) // not available in QML...
    let lastChange = null;
    for (var i = 0; i < changes.length; i++) {
      Logger.d("DarkModeService", `Checking change: time=${changes[i].time} (${new Date(changes[i].time).toLocaleString()}), darkMode=${changes[i].darkMode}`);
      if (changes[i].time < now) {
        lastChange = changes[i];
      }
    }

    if (lastChange) {
      Logger.i("DarkModeService", `Selected change: time=${lastChange.time}, darkMode=${lastChange.darkMode}`);
      Settings.data.colorSchemes.darkMode = lastChange.darkMode;
      Logger.d("DarkModeService", `Reset: darkmode=${lastChange.darkMode}`);
    } else {
      Logger.w("DarkModeService", "No suitable change found for current time!");
    }
  }

  function scheduleNextMode(changes) {
    const now = Date.now();
    const nextChange = changes.find(change => change.time > now);
    if (nextChange) {
      root.nextDarkModeState = nextChange.darkMode;
      timer.interval = nextChange.time - now;
      timer.restart();
      Logger.d("DarkModeService", `Scheduled: darkmode=${nextChange.darkMode} in ${timer.interval} ms`);
    }
  }
}
