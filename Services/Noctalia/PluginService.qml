pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI

Singleton {
  id: root

  signal pluginLoaded(string pluginId)
  signal pluginUnloaded(string pluginId)
  signal pluginEnabled(string pluginId)
  signal pluginDisabled(string pluginId)
  signal pluginReloaded(string pluginId)
  signal allPluginsLoaded

  // Loaded plugin instances
  property var loadedPlugins: ({}) // { pluginId: { component, instance, api } }

  // Plugin load errors: { pluginId: { error: string, entryPoint: string, timestamp: date } }
  property var pluginErrors: ({})
  signal pluginLoadError(string pluginId, string entryPoint, string error)

  // Hot reload: file watchers for plugin directories
  property var pluginFileWatchers: ({}) // { pluginId: FileView }
  property list<string> pluginHotReloadEnabled: [] // List of pluginIds that have hot reload enabled

  property bool initialized: false
  property bool pluginsFullyLoaded: false

  // Plugin container from shell.qml (for placing Main instances in graphics scene)
  property var pluginContainer: null

  // Screen detector from shell.qml (for withCurrentScreen in plugin API)
  property var screenDetector: null

  // Track if we need to initialize once container is ready
  property bool needsInit: false

  // Watch for pluginContainer to be set
  onPluginContainerChanged: {
    if (root.pluginContainer && root.needsInit) {
      Logger.d("PluginService", "Plugin container now available, initializing plugins");
      root.needsInit = false;
      root.init();
    }
  }

  // Listen for PluginRegistry to finish loading
  Connections {
    target: PluginRegistry

    function onPluginsChanged() {
      if (!root.initialized) {
        if (root.pluginContainer) {
          root.init();
        } else {
          Logger.d("PluginService", "Deferring plugin init until container is ready");
          root.needsInit = true;
        }
      }
    }
  }

  // When debug mode is disabled, tear down all hot reload watchers
  Connections {
    target: Settings

    function onIsDebugChanged() {
      if (!Settings.isDebug && root.pluginHotReloadEnabled.length > 0) {
        Logger.i("PluginService", "Debug mode disabled, removing all hot reload watchers");
        var plugins = root.pluginHotReloadEnabled.slice();
        for (var i = 0; i < plugins.length; i++) {
          removePluginFileWatcher(plugins[i]);
        }
        root.pluginHotReloadEnabled = [];
      }
    }
  }

  // Listen for language changes to reload plugin translations
  Connections {
    target: I18n

    function onLanguageChanged() {
      Logger.d("PluginService", "Language changed to:", I18n.langCode, "- reloading plugin translations");

      for (var pluginId in root.loadedPlugins) {
        (function (id, plugin) {
          if (plugin && plugin.api && plugin.manifest) {
            plugin.api.currentLanguage = I18n.langCode;

            loadPluginTranslationsAsync(id, plugin.manifest, I18n.langCode, function (translations) {
              plugin.api.pluginTranslations = translations;

              if (I18n.langCode !== "en") {
                loadPluginTranslationsAsync(id, plugin.manifest, "en", function (fallbackTranslations) {
                  plugin.api.pluginFallbackTranslations = fallbackTranslations;
                  plugin.api.translationVersion++;
                  Logger.d("PluginService", "Reloaded translations for plugin:", id);
                });
              } else {
                plugin.api.pluginFallbackTranslations = {};
                plugin.api.translationVersion++;
                Logger.d("PluginService", "Reloaded translations for plugin:", id);
              }
            });
          }
        })(pluginId, root.loadedPlugins[pluginId]);
      }

      if (root.pluginHotReloadEnabled.length > 0) {
        updateTranslationWatchers();
      }
    }
  }

  // Track pending plugin loads for init completion
  property int _pendingPluginLoads: 0

  function init() {
    if (root.initialized) {
      Logger.d("PluginService", "Already initialized, skipping");
      return;
    }

    Logger.i("PluginService", "Initializing plugin system");
    root.initialized = true;

    var allInstalled = PluginRegistry.getAllInstalledPluginIds();
    Logger.d("PluginService", "All installed plugins:", JSON.stringify(allInstalled));
    Logger.d("PluginService", "Plugin states:", JSON.stringify(PluginRegistry.pluginStates));

    // Load all enabled plugins
    var enabledIds = PluginRegistry.getEnabledPluginIds();
    Logger.i("PluginService", "Found", enabledIds.length, "enabled plugins:", JSON.stringify(enabledIds));

    var pluginsToLoad = [];
    for (var i = 0; i < enabledIds.length; i++) {
      var manifest = PluginRegistry.getPluginManifest(enabledIds[i]);
      if (manifest) {
        pluginsToLoad.push(enabledIds[i]);
      } else {
        Logger.w("PluginService", "Plugin", enabledIds[i], "is enabled but not found on disk - disabling");
        PluginRegistry.setPluginEnabled(enabledIds[i], false);
      }
    }

    // If no plugins to load, mark as complete immediately
    if (pluginsToLoad.length === 0) {
      root.pluginsFullyLoaded = true;
      Logger.i("PluginService", "No plugins to load");
      root.allPluginsLoaded();
      return;
    }

    // Track pending loads
    root._pendingPluginLoads = pluginsToLoad.length;

    // Load all plugins
    for (var j = 0; j < pluginsToLoad.length; j++) {
      Logger.d("PluginService", "Attempting to load plugin:", pluginsToLoad[j]);
      loadPlugin(pluginsToLoad[j]);
    }
  }

  // Called when a plugin finishes loading (success or failure)
  function _onPluginLoadComplete() {
    root._pendingPluginLoads--;

    if (root._pendingPluginLoads <= 0) {
      root.pluginsFullyLoaded = true;
      Logger.i("PluginService", "All plugins loaded");
      root.allPluginsLoaded();
    }
  }

  // Uninstall a plugin (remove files from disk)
  function uninstallPlugin(pluginId, callback) {
    Logger.i("PluginService", "Uninstalling plugin:", pluginId);

    // Disable and unload first
    if (PluginRegistry.isPluginEnabled(pluginId)) {
      disablePlugin(pluginId);
    }

    var pluginDir = PluginRegistry.getPluginDir(pluginId);

    var removeProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["rm", "-rf", "${pluginDir}"]
      }
    `, root, "RemovePlugin_" + pluginId);

    removeProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        PluginRegistry.unregisterPlugin(pluginId);
        Logger.i("PluginService", "Uninstalled plugin:", pluginId);

        if (callback)
          callback(true, null);
      } else {
        Logger.e("PluginService", "Failed to uninstall plugin:", pluginId);
        if (callback)
          callback(false, "Failed to remove plugin files");
      }

      removeProcess.destroy();
    });

    removeProcess.running = true;
  }

  // Enable a plugin
  function enablePlugin(pluginId, skipAddToBar) {
    if (PluginRegistry.isPluginEnabled(pluginId)) {
      Logger.w("PluginService", "Plugin already enabled:", pluginId);
      return true;
    }

    if (!PluginRegistry.isPluginDownloaded(pluginId)) {
      Logger.e("PluginService", "Cannot enable: plugin not installed:", pluginId);
      return false;
    }

    PluginRegistry.setPluginEnabled(pluginId, true);
    loadPlugin(pluginId);

    // Add plugin widget to bar if it provides one
    if (!skipAddToBar) {
      var manifest = PluginRegistry.getPluginManifest(pluginId);
      if (manifest && manifest.entryPoints && manifest.entryPoints.barWidget) {
        var widgetId = "plugin:" + pluginId;
        addWidgetToBar(widgetId, "right");
      }
    }

    root.pluginEnabled(pluginId);
    return true;
  }

  // Helper function to add a widget to the bar (global + all screen overrides)
  function addWidgetToBar(widgetId, section) {
    section = section || "right";

    var sections = ["left", "center", "right"];
    for (var s = 0; s < sections.length; s++) {
      var widgets = Settings.data.bar.widgets[sections[s]] || [];
      for (var i = 0; i < widgets.length; i++) {
        if (widgets[i].id === widgetId) {
          Logger.d("PluginService", "Widget already in bar:", widgetId);
          return false;
        }
      }
    }

    // Add to global
    var globalWidgets = Settings.data.bar.widgets[section] || [];
    globalWidgets.push({
                         id: widgetId
                       });
    Settings.data.bar.widgets[section] = globalWidgets;

    // Also add to any screen overrides that have widget configurations
    var overrides = Settings.data.bar.screenOverrides || [];
    for (var o = 0; o < overrides.length; o++) {
      if (overrides[o] && overrides[o].widgets) {
        var overrideWidgets = overrides[o].widgets;
        var sectionWidgets = overrideWidgets[section] || [];
        var alreadyExists = false;
        for (var j = 0; j < sections.length; j++) {
          var owSec = overrideWidgets[sections[j]] || [];
          for (var k = 0; k < owSec.length; k++) {
            if (owSec[k].id === widgetId) {
              alreadyExists = true;
              break;
            }
          }
          if (alreadyExists)
            break;
        }
        if (!alreadyExists) {
          sectionWidgets.push({
                                id: widgetId
                              });
          overrideWidgets[section] = sectionWidgets;
          Settings.setScreenOverride(overrides[o].name, "widgets", overrideWidgets);
        }
      }
    }

    Logger.i("PluginService", "Added widget", widgetId, "to bar section:", section);
    return true;
  }

  // Disable a plugin
  function disablePlugin(pluginId) {
    if (!PluginRegistry.isPluginEnabled(pluginId)) {
      Logger.w("PluginService", "Plugin already disabled:", pluginId);
      return true;
    }

    // Remove plugin widget from bar before unloading
    var widgetId = "plugin:" + pluginId;
    removeWidgetFromBar(widgetId);

    PluginRegistry.setPluginEnabled(pluginId, false);
    unloadPlugin(pluginId);

    root.pluginDisabled(pluginId);
    return true;
  }

  // Helper function to remove a widget from all bar sections (global + screen overrides)
  function removeWidgetFromBar(widgetId) {
    var sections = ["left", "center", "right"];
    var changed = false;

    for (var s = 0; s < sections.length; s++) {
      var section = sections[s];
      var widgets = Settings.data.bar.widgets[section] || [];
      var newWidgets = [];

      for (var i = 0; i < widgets.length; i++) {
        if (widgets[i].id !== widgetId) {
          newWidgets.push(widgets[i]);
        } else {
          changed = true;
          Logger.i("PluginService", "Removed widget", widgetId, "from bar section:", section);
        }
      }

      if (changed) {
        Settings.data.bar.widgets[section] = newWidgets;
      }
    }

    var overrides = Settings.data.bar.screenOverrides || [];
    for (var o = 0; o < overrides.length; o++) {
      if (overrides[o] && overrides[o].widgets) {
        var overrideWidgets = overrides[o].widgets;
        var overrideChanged = false;
        for (var s2 = 0; s2 < sections.length; s2++) {
          var sec = sections[s2];
          var owWidgets = overrideWidgets[sec] || [];
          var owNew = [];
          for (var j = 0; j < owWidgets.length; j++) {
            if (owWidgets[j].id !== widgetId) {
              owNew.push(owWidgets[j]);
            } else {
              overrideChanged = true;
              changed = true;
              Logger.i("PluginService", "Removed widget", widgetId, "from screen override:", overrides[o].name, "section:", sec);
            }
          }
          if (overrideChanged) {
            overrideWidgets[sec] = owNew;
          }
        }
        if (overrideChanged) {
          Settings.setScreenOverride(overrides[o].name, "widgets", overrideWidgets);
        }
      }
    }

    if (changed) {
      BarService.widgetsRevision++;
    }

    return changed;
  }

  // Load plugin settings and translations before instantiating components
  function loadPluginData(pluginId, manifest, callback) {
    loadPluginSettings(pluginId, function (settings) {
      loadPluginTranslationsAsync(pluginId, manifest, I18n.langCode, function (translations) {
        if (I18n.langCode !== "en") {
          loadPluginTranslationsAsync(pluginId, manifest, "en", function (fallbackTranslations) {
            callback(settings, translations, fallbackTranslations);
          });
        } else {
          callback(settings, translations, {});
        }
      });
    });
  }

  // Load a plugin
  function loadPlugin(pluginId) {
    if (root.loadedPlugins[pluginId]) {
      Logger.w("PluginService", "Plugin already loaded:", pluginId);
      return;
    }

    var manifest = PluginRegistry.getPluginManifest(pluginId);
    if (!manifest) {
      Logger.e("PluginService", "Cannot load: manifest not found for:", pluginId);
      return;
    }

    var pluginDir = PluginRegistry.getPluginDir(pluginId);

    Logger.i("PluginService", "Loading plugin:", pluginId);

    loadPluginData(pluginId, manifest, function (settings, translations, fallbackTranslations) {
      var pluginApi = createPluginAPI(pluginId, manifest, settings, translations, fallbackTranslations);

      root.loadedPlugins[pluginId] = {
        barWidget: null,
        mainInstance: null,
        api: pluginApi,
        manifest: manifest
      };

      root.clearPluginError(pluginId);

      // Load Main.qml entry point if it exists
      if (manifest.entryPoints && manifest.entryPoints.main) {
        var mainPath = pluginDir + "/" + manifest.entryPoints.main;
        var loadVersion = PluginRegistry.pluginLoadVersions[pluginId] || 0;
        var mainComponent = Qt.createComponent("file://" + mainPath + "?v=" + loadVersion);

        if (mainComponent.status === Component.Ready) {
          if (!root.pluginContainer) {
            Logger.e("PluginService", "Plugin container not set. Shell must set PluginService.pluginContainer.");
            return;
          }

          var mainInstance = mainComponent.createObject(root.pluginContainer, {
                                                          pluginApi: pluginApi
                                                        });

          if (mainInstance) {
            root.loadedPlugins[pluginId].mainInstance = mainInstance;
            pluginApi.mainInstance = mainInstance;
            Logger.i("PluginService", "Loaded Main.qml for plugin:", pluginId);
          } else {
            root.recordPluginError(pluginId, "main", "Failed to instantiate Main.qml");
          }
        } else if (mainComponent.status === Component.Error) {
          root.recordPluginError(pluginId, "main", mainComponent.errorString());
        }
      }

      // Load bar widget component if provided
      if (manifest.entryPoints && manifest.entryPoints.barWidget) {
        var widgetPath = pluginDir + "/" + manifest.entryPoints.barWidget;
        var widgetLoadVersion = PluginRegistry.pluginLoadVersions[pluginId] || 0;
        var widgetComponent = Qt.createComponent("file://" + widgetPath + "?v=" + widgetLoadVersion);

        if (widgetComponent.status === Component.Ready) {
          root.loadedPlugins[pluginId].barWidget = widgetComponent;
          pluginApi.barWidget = widgetComponent;

          BarWidgetRegistry.registerPluginWidget(pluginId, widgetComponent, manifest.metadata);
          Logger.i("PluginService", "Loaded bar widget for plugin:", pluginId);

          BarService.widgetsRevision++;
        } else if (widgetComponent.status === Component.Error) {
          root.recordPluginError(pluginId, "barWidget", widgetComponent.errorString());
        }
      }

      Logger.i("PluginService", "Plugin loaded:", pluginId);
      root.pluginLoaded(pluginId);

      setupPluginFileWatcher(pluginId);

      root._onPluginLoadComplete();
    });
  }

  // Unload a plugin
  function unloadPlugin(pluginId) {
    var plugin = root.loadedPlugins[pluginId];
    if (!plugin) {
      Logger.w("PluginService", "Plugin not loaded:", pluginId);
      return;
    }

    Logger.i("PluginService", "Unloading plugin:", pluginId);

    removePluginFileWatcher(pluginId);

    if (plugin.manifest.entryPoints && plugin.manifest.entryPoints.barWidget) {
      BarWidgetRegistry.unregisterPluginWidget(pluginId);
    }

    if (plugin.mainInstance) {
      plugin.mainInstance.destroy();
    }

    delete root.loadedPlugins[pluginId];
    root.pluginUnloaded(pluginId);
    Logger.i("PluginService", "Unloaded plugin:", pluginId);
  }

  // Create plugin API object with pre-loaded settings and translations
  function createPluginAPI(pluginId, manifest, settings, translations, fallbackTranslations) {
    var pluginDir = PluginRegistry.getPluginDir(pluginId);

    var api = Qt.createQmlObject(`
      import QtQuick

      QtObject {
        readonly property string pluginId: "${pluginId}"
        readonly property string pluginDir: "${pluginDir}"
        property var pluginSettings: ({})
        property var manifest: ({})

        property var mainInstance: null
        property var barWidget: null

        property var panelOpenScreen: null

        property var ipcHandlers: ({})

        property var pluginTranslations: ({})
        property var pluginFallbackTranslations: ({})
        property string currentLanguage: ""
        property int translationVersion: 0

        property var saveSettings: null
        property var openPanel: null
        property var closePanel: null
        property var togglePanel: null
        property var withCurrentScreen: null
        property var tr: null
        property var trp: null
        property var hasTranslation: null
      }
    `, root, "PluginAPI_" + pluginId);

    api.manifest = manifest;
    api.currentLanguage = I18n.langCode;
    api.pluginSettings = settings || {};
    api.pluginTranslations = translations || {};
    api.pluginFallbackTranslations = fallbackTranslations || {};

    var getNestedProperty = function (obj, path) {
      var keys = path.split('.');
      var current = obj;
      for (var i = 0; i < keys.length; i++) {
        if (current === undefined || current === null) {
          return undefined;
        }
        current = current[keys[i]];
      }
      return current;
    };

    api.saveSettings = function () {
      savePluginSettings(pluginId, api.pluginSettings);
      api.pluginSettings = Object.assign({}, api.pluginSettings);
    };

    api.togglePanel = function (screen, buttonItem) {
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for toggling panel");
        return false;
      }
      return togglePluginPanel(pluginId, screen, buttonItem);
    };

    api.openPanel = function (screen, buttonItem) {
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for opening panel");
        return false;
      }
      return openPluginPanel(pluginId, screen, buttonItem);
    };

    api.closePanel = function (screen) {
      for (var slotNum = 1; slotNum <= 2; slotNum++) {
        var panelName = "pluginPanel" + slotNum;
        var panel = PanelService.getPanel(panelName, screen);
        if (panel && panel.currentPluginId === pluginId) {
          panel.close();
          return true;
        }
      }
      return false;
    };

    api.withCurrentScreen = function (callback) {
      if (!root.screenDetector) {
        Logger.w("PluginAPI", "Screen detector not available, using primary screen");
        callback(Quickshell.screens[0]);
        return;
      }
      root.screenDetector.withCurrentScreen(callback);
    };

    api.tr = function (key, interpolations) {
      if (typeof interpolations === 'undefined') {
        interpolations = {};
      }

      var translation = getNestedProperty(api.pluginTranslations, key);

      if (translation === undefined || translation === null || typeof translation !== 'string') {
        translation = getNestedProperty(api.pluginFallbackTranslations, key);
      }

      if (translation === undefined || translation === null) {
        return `!!${key}!!`;
      }

      if (typeof translation !== 'string') {
        return `!!${key}!!`;
      }

      var result = translation;
      for (var placeholder in interpolations) {
        var regex = new RegExp('\\{' + placeholder + '\\}', 'g');
        result = result.replace(regex, interpolations[placeholder]);
      }

      return result;
    };

    api.trp = function (key, count, interpolations) {
      if (typeof interpolations === 'undefined') {
        interpolations = {};
      }

      const realKey = count === 1 ? key : `${key}-plural`;

      var finalInterpolations = {
        'count': count
      };
      for (var prop in interpolations) {
        finalInterpolations[prop] = interpolations[prop];
      }

      return api.tr(realKey, finalInterpolations);
    };

    api.hasTranslation = function (key) {
      return getNestedProperty(api.pluginTranslations, key) !== undefined || getNestedProperty(api.pluginFallbackTranslations, key) !== undefined;
    };

    return api;
  }

  // Load plugin translations asynchronously
  function loadPluginTranslationsAsync(pluginId, manifest, language, callback) {
    var pluginDir = PluginRegistry.getPluginDir(pluginId);
    var translationFile = pluginDir + "/i18n/" + language + ".json";

    var readProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["cat", "${translationFile}"]
        stdout: StdioCollector {}
      }
    `, root, "ReadTranslation_" + pluginId + "_" + language);

    readProcess.exited.connect(function (exitCode) {
      var translations = {};

      if (exitCode === 0) {
        try {
          translations = JSON.parse(readProcess.stdout.text);
          Logger.d("PluginService", "Loaded translations for", pluginId, "language:", language);
        } catch (e) {
          Logger.w("PluginService", "Failed to parse translations for", pluginId, "language:", language);
        }
      } else {
        Logger.d("PluginService", "No translation file for", pluginId, "language:", language);
      }

      if (callback) {
        callback(translations);
      }

      readProcess.destroy();
    });

    readProcess.running = true;
  }

  // Load plugin settings
  function loadPluginSettings(pluginId, callback) {
    var settingsFile = PluginRegistry.getPluginSettingsFile(pluginId);

    var readProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["cat", "${settingsFile}"]
        stdout: StdioCollector {}
      }
    `, root, "ReadSettings_" + pluginId);

    readProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        try {
          var settings = JSON.parse(readProcess.stdout.text);
          callback(settings);
        } catch (e) {
          Logger.w("PluginService", "Failed to parse settings for", pluginId, "- using defaults");
          callback({});
        }
      } else {
        callback({});
      }

      readProcess.destroy();
    });

    readProcess.running = true;
  }

  // Save plugin settings
  function savePluginSettings(pluginId, settings) {
    var settingsFile = PluginRegistry.getPluginSettingsFile(pluginId);
    var settingsJson = JSON.stringify(settings, null, 2);

    var delimiter = "PLUGIN_SETTINGS_EOF_" + Math.random().toString(36).substr(2, 9);
    var fileEsc = settingsFile.replace(/'/g, "'\\''");

    var settingsDir = settingsFile.substring(0, settingsFile.lastIndexOf('/'));
    var dirEsc = settingsDir.replace(/'/g, "'\\''");

    var writeCmd = "mkdir -p '" + dirEsc + "' && cat > '" + fileEsc + "' << '" + delimiter + "'\n" + settingsJson + "\n" + delimiter + "\n";

    Logger.d("PluginService", "Saving settings to:", settingsFile);

    var pid = Quickshell.execDetached(["sh", "-c", writeCmd]);
    Logger.d("PluginService", "Write process started, PID:", pid);
  }

  // Get plugin API for a loaded plugin
  function getPluginAPI(pluginId) {
    return root.loadedPlugins[pluginId]?.api || null;
  }

  // Check if plugin is loaded
  function isPluginLoaded(pluginId) {
    return !!root.loadedPlugins[pluginId];
  }

  // Open a plugin's panel
  function openPluginPanel(pluginId, screen, buttonItem) {
    if (!isPluginLoaded(pluginId)) {
      Logger.w("PluginService", "Cannot open panel: plugin not loaded:", pluginId);
      return false;
    }

    var plugin = root.loadedPlugins[pluginId];
    if (!plugin || !plugin.manifest || !plugin.manifest.entryPoints || !plugin.manifest.entryPoints.panel) {
      Logger.w("PluginService", "Plugin does not provide a panel:", pluginId);
      return false;
    }

    var closedSlot = null;

    for (var slotNum = 1; slotNum <= 2; slotNum++) {
      var panelName = "pluginPanel" + slotNum;
      var panel = PanelService.getPanel(panelName, screen);

      if (panel) {
        if (panel.currentPluginId === pluginId) {
          panel.toggle(buttonItem);
          return true;
        }

        if (panel.currentPluginId === "") {
          panel.currentPluginId = pluginId;
          panel.open(buttonItem);
          return true;
        }

        if (!closedSlot && !panel.isPanelOpen) {
          closedSlot = panel;
        }
      }
    }

    if (closedSlot) {
      closedSlot.currentPluginId = pluginId;
      closedSlot.open(buttonItem);
      return true;
    }

    var panel1 = PanelService.getPanel("pluginPanel1", screen);
    if (panel1) {
      var wasAlreadyOpen = panel1.isPanelOpen;
      panel1.unloadPluginPanel();
      panel1.currentPluginId = pluginId;

      if (wasAlreadyOpen && panel1.contentLoader) {
        panel1.loadPluginPanel(pluginId);
      }

      panel1.open(buttonItem);
      return true;
    }

    Logger.e("PluginService", "Failed to find plugin panel slot");
    return false;
  }

  // Toggle a plugin's panel
  function togglePluginPanel(pluginId, screen, buttonItem) {
    if (!isPluginLoaded(pluginId)) {
      Logger.w("PluginService", "Cannot toggle panel: plugin not loaded:", pluginId);
      return false;
    }

    var plugin = root.loadedPlugins[pluginId];
    if (!plugin || !plugin.manifest || !plugin.manifest.entryPoints || !plugin.manifest.entryPoints.panel) {
      Logger.w("PluginService", "Plugin does not provide a panel:", pluginId);
      return false;
    }

    for (var slotNum = 1; slotNum <= 2; slotNum++) {
      var panelName = "pluginPanel" + slotNum;
      var panel = PanelService.getPanel(panelName, screen);

      if (panel && panel.currentPluginId === pluginId) {
        panel.toggle(buttonItem);
        return true;
      }
    }

    return openPluginPanel(pluginId, screen, buttonItem);
  }

  // ----- Error tracking functions -----

  function recordPluginError(pluginId, entryPoint, errorMessage) {
    var errors = Object.assign({}, root.pluginErrors);
    errors[pluginId] = {
      error: errorMessage,
      entryPoint: entryPoint,
      timestamp: new Date()
    };
    root.pluginErrors = errors;
    root.pluginLoadError(pluginId, entryPoint, errorMessage);
    Logger.e("PluginService", "Plugin load error [" + pluginId + "/" + entryPoint + "]:", errorMessage);
  }

  function clearPluginError(pluginId) {
    if (pluginId in root.pluginErrors) {
      var errors = Object.assign({}, root.pluginErrors);
      delete errors[pluginId];
      root.pluginErrors = errors;
    }
  }

  function getPluginError(pluginId) {
    return root.pluginErrors[pluginId] || null;
  }

  function hasPluginError(pluginId) {
    return pluginId in root.pluginErrors;
  }

  // ----- Hot reload functions -----

  function setupPluginFileWatcher(pluginId) {
    if (!isPluginHotReloadEnabled(pluginId)) {
      return;
    }

    if (root.pluginFileWatchers[pluginId]) {
      return;
    }

    var manifest = PluginRegistry.getPluginManifest(pluginId);
    if (!manifest) {
      return;
    }

    var pluginDir = PluginRegistry.getPluginDir(pluginId);

    var debounceTimer = Qt.createQmlObject(`
      import QtQuick
      Timer {
        property string targetPluginId: ""
        property var reloadCallback: null
        interval: 500
        repeat: false
        onTriggered: {
          if (reloadCallback) reloadCallback(targetPluginId);
        }
      }
    `, root, "HotReloadDebounce_" + pluginId);

    debounceTimer.targetPluginId = pluginId;
    debounceTimer.reloadCallback = root.reloadPlugin;

    var manifestWatcher = Qt.createQmlObject(`
      import Quickshell.Io
      FileView {
        path: "${pluginDir}/manifest.json"
        watchChanges: true
      }
    `, root, "ManifestWatcher_" + pluginId);

    var watchers = [manifestWatcher];

    var qmlWatcher = Qt.createQmlObject(`
        import QtQuick
        import Quickshell.Io

        import qs.Commons

        Item {
            id: root
            signal fileChanged();

            Process {
                command: [ "sh", "-c", "find -L ${pluginDir} -name '*.qml' -o -name '*.js'" ]
                running: true
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: line => {
                        fileWatcher.createObject(root, { path: Qt.resolvedUrl(line) });
                    }
                }
            }

            Component {
                id: fileWatcher
                FileView {
                    watchChanges: true

                    onFileChanged: {
                        root.fileChanged();
                    }
                }
            }

        }
    `, root, "QmlWatcher_" + pluginId);
    watchers.push(qmlWatcher);

    for (var j = 0; j < watchers.length; j++) {
      watchers[j].fileChanged.connect(function () {
        debounceTimer.restart();
      });
    }

    var translationDebounceTimer = Qt.createQmlObject(`
      import QtQuick
      Timer {
        property string targetPluginId: ""
        property var reloadCallback: null
        interval: 300
        repeat: false
        onTriggered: {
          if (reloadCallback) reloadCallback(targetPluginId);
        }
      }
    `, root, "TranslationReloadDebounce_" + pluginId);

    translationDebounceTimer.targetPluginId = pluginId;
    translationDebounceTimer.reloadCallback = root.reloadPluginTranslations;

    var translationWatcher = createTranslationWatcher(pluginId, pluginDir, I18n.langCode, translationDebounceTimer);

    root.pluginFileWatchers[pluginId] = {
      watchers: watchers,
      debounceTimer: debounceTimer,
      translationWatcher: translationWatcher,
      translationDebounceTimer: translationDebounceTimer,
      pluginDir: pluginDir
    };

    Logger.d("PluginService", "Set up hot reload watcher for plugin:", pluginId, "(including translations)");
  }

  function createTranslationWatcher(pluginId, pluginDir, language, debounceTimer) {
    var translationFile = pluginDir + "/i18n/" + language + ".json";

    var watcher = Qt.createQmlObject(`
      import Quickshell.Io
      FileView {
        path: "${translationFile}"
        watchChanges: true
      }
    `, root, "TranslationWatcher_" + pluginId + "_" + language);

    watcher.fileChanged.connect(function () {
      debounceTimer.restart();
    });

    Logger.d("PluginService", "Watching translation file:", translationFile);
    return watcher;
  }

  function updateTranslationWatchers() {
    for (var pluginId in root.pluginFileWatchers) {
      var watcherData = root.pluginFileWatchers[pluginId];
      if (!watcherData || !watcherData.translationDebounceTimer)
        continue;

      if (watcherData.translationWatcher) {
        watcherData.translationWatcher.destroy();
      }

      watcherData.translationWatcher = createTranslationWatcher(pluginId, watcherData.pluginDir, I18n.langCode, watcherData.translationDebounceTimer);
    }
    Logger.d("PluginService", "Updated translation watchers for language:", I18n.langCode);
  }

  function removePluginFileWatcher(pluginId) {
    var watcherData = root.pluginFileWatchers[pluginId];
    if (!watcherData) {
      return;
    }

    if (watcherData.watchers) {
      for (var i = 0; i < watcherData.watchers.length; i++) {
        if (watcherData.watchers[i]) {
          watcherData.watchers[i].destroy();
        }
      }
    }

    if (watcherData.debounceTimer) {
      watcherData.debounceTimer.destroy();
    }

    if (watcherData.translationWatcher) {
      watcherData.translationWatcher.destroy();
    }

    if (watcherData.translationDebounceTimer) {
      watcherData.translationDebounceTimer.destroy();
    }

    delete root.pluginFileWatchers[pluginId];
    Logger.d("PluginService", "Removed hot reload watcher for plugin:", pluginId);
  }

  function reloadPlugin(pluginId) {
    if (!root.loadedPlugins[pluginId]) {
      Logger.w("PluginService", "Cannot reload: plugin not loaded:", pluginId);
      return false;
    }

    Logger.i("PluginService", "Hot reloading plugin:", pluginId);

    var manifest = PluginRegistry.getPluginManifest(pluginId);
    if (!manifest) {
      Logger.e("PluginService", "Cannot reload: manifest not found for:", pluginId);
      return false;
    }

    BarService.destroyPluginWidgetInstances(pluginId);

    unloadPlugin(pluginId);

    PluginRegistry.incrementPluginLoadVersion(pluginId);

    Qt.callLater(function () {
      loadPlugin(pluginId);

      setupPluginFileWatcher(pluginId);

      root.pluginReloaded(pluginId);

      var pluginName = manifest.name || pluginId;
      ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.hot-reloaded", {
                                                                         "name": pluginName
                                                                       }));

      Logger.i("PluginService", "Hot reload complete for plugin:", pluginId);
    });

    return true;
  }

  function reloadPluginTranslations(pluginId) {
    var plugin = root.loadedPlugins[pluginId];
    if (!plugin || !plugin.api || !plugin.manifest) {
      Logger.w("PluginService", "Cannot reload translations: plugin not loaded:", pluginId);
      return false;
    }

    Logger.i("PluginService", "Hot reloading translations for plugin:", pluginId);

    loadPluginTranslationsAsync(pluginId, plugin.manifest, I18n.langCode, function (translations) {
      plugin.api.pluginTranslations = translations;

      if (I18n.langCode !== "en") {
        loadPluginTranslationsAsync(pluginId, plugin.manifest, "en", function (fallbackTranslations) {
          plugin.api.pluginFallbackTranslations = fallbackTranslations;
          plugin.api.translationVersion++;

          var pluginName = plugin.manifest.name || pluginId;
          ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.translations-reloaded", {
                                                                             "name": pluginName
                                                                           }));
          Logger.i("PluginService", "Translation hot reload complete for plugin:", pluginId);
        });
      } else {
        plugin.api.pluginFallbackTranslations = {};
        plugin.api.translationVersion++;

        var pluginName = plugin.manifest.name || pluginId;
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.translations-reloaded", {
                                                                           "name": pluginName
                                                                         }));
        Logger.i("PluginService", "Translation hot reload complete for plugin:", pluginId);
      }
    });

    return true;
  }

  function isPluginHotReloadEnabled(pluginId) {
    return root.pluginHotReloadEnabled.indexOf(pluginId) !== -1;
  }

  function togglePluginHotReload(pluginId) {
    const index = root.pluginHotReloadEnabled.indexOf(pluginId);
    if (index === -1) {
      root.pluginHotReloadEnabled.push(pluginId);
      setupPluginFileWatcher(pluginId);
      Logger.i("PluginService", "Hot reload enabled for plugin:", pluginId);
    } else {
      root.pluginHotReloadEnabled.splice(index, 1);
      removePluginFileWatcher(pluginId);
      Logger.i("PluginService", "Hot reload disabled for plugin:", pluginId);
    }
  }
}
