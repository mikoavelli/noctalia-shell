pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  property bool isLoaded: false
  readonly property string langCode: "en"
  property var locale: Qt.locale("en")
  property var translations: ({})

  // Signals for reactive updates
  signal languageChanged(string newLanguage)
  signal translationsLoaded

  // FileView to load translation files
  property FileView translationFile: FileView {
    id: fileView
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        root.translations = JSON.parse(text());
        Logger.i("I18n", "Loaded English translation");
        root.isLoaded = true;
        root.translationsLoaded();
      } catch (e) {
        Logger.e("I18n", `Failed to parse translation file: ${e}`);
        root.isLoaded = true;
        root.translationsLoaded();
      }
    }
    onLoadFailed: function (error) {
      Logger.e("I18n", `Failed to load English translation file: ${error}`);
      root.isLoaded = true;
      root.translationsLoaded();
    }
  }

  Component.onCompleted: {
    Logger.i("I18n", "Service started");
    loadTranslations();
  }

  function loadTranslations() {
    isLoaded = false;
    fileView.path = `file://${Quickshell.shellDir}/Assets/Translations/${langCode}.json`;
  }

  function reload() {
    Logger.d("I18n", "Reloading English translation");
    loadTranslations();
  }

  function hasTranslation(key) {
    if (!isLoaded)
      return false;

    var keys = key.split(".");
    var value = translations;

    for (var i = 0; i < keys.length; i++) {
      if (value && typeof value === "object" && keys[i] in value) {
        value = value[keys[i]];
      } else {
        return false;
      }
    }

    return typeof value === "string";
  }

  function tr(key, interpolations) {
    if (typeof interpolations === "undefined")
      interpolations = {};

    if (!isLoaded)
      return key;

    var keys = key.split(".");
    var value = translations;

    for (var i = 0; i < keys.length; i++) {
      if (value && typeof value === "object" && keys[i] in value) {
        value = value[keys[i]];
      } else {
        return `!!${key}!!`;
      }
    }

    if (typeof value !== "string")
      return key;

    var result = value;
    for (var placeholder in interpolations) {
      var regex = new RegExp(`\\{${placeholder}\\}`, 'g');
      result = result.replace(regex, interpolations[placeholder]);
    }

    return result;
  }

  function trp(key, count, interpolations) {
    if (typeof interpolations === "undefined")
      interpolations = {};

    var realKey = count === 1 ? key : `${key}-plural`;

    var finalInterpolations = {
      "count": count
    };
    for (var prop in interpolations) {
      finalInterpolations[prop] = interpolations[prop];
    }

    return tr(realKey, finalInterpolations);
  }
}
