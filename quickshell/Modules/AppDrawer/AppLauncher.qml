import QtQuick
import Quickshell
import qs.Common
import qs.Services

Item {
    id: root

    // DEVELOPER NOTE: This component manages the AppDrawer launcher (accessed via DankBar icon).
    // Changes to launcher behavior, especially item rendering, filtering, or model structure,
    // likely require corresponding updates in Modals/Spotlight/SpotlightResults.qml and vice versa.

    property string searchQuery: ""
    property string selectedCategory: I18n.tr("All")
    property string viewMode: "list" // "list" or "grid"
    property int selectedIndex: 0
    property int maxResults: 50
    property int gridColumns: 4
    property bool debounceSearch: true
    property int debounceInterval: 50
    property bool keyboardNavigationActive: false
    property bool suppressUpdatesWhileLaunching: false
    property var categories: []
    readonly property var categoryIcons: categories.map(category => AppSearchService.getCategoryIcon(category))
    property var appUsageRanking: AppUsageHistoryData.appUsageRanking || {}
    property alias model: filteredModel
    property var _uniqueApps: []
    property bool _initialized: false
    property bool _isTriggered: false
    property string _triggeredCategory: ""
    property bool _updatingFromTrigger: false

    signal appLaunched(var app)
    signal categorySelected(string category)
    signal viewModeSelected(string mode)

    function ensureInitialized() {
        if (_initialized)
            return;
        _initialized = true;
        updateCategories();
        updateFilteredModel();
    }

    function updateCategories() {
        const allCategories = AppSearchService.getAllCategories().filter(cat => cat !== "Education" && cat !== "Science");
        const result = [I18n.tr("All")];
        categories = result.concat(allCategories.filter(cat => cat !== I18n.tr("All")));
    }

    Connections {
        target: PluginService
        function onPluginLoaded() {
            updateCategories();
        }
        function onPluginUnloaded() {
            updateCategories();
        }
        function onPluginListUpdated() {
            updateCategories();
        }
        function onRequestLauncherUpdate(pluginId) {
            // Only update if we are actually looking at this plugin or in All category
            updateFilteredModel();
        }
    }

    Connections {
        target: SettingsData
        function onSortAppsAlphabeticallyChanged() {
            updateFilteredModel();
        }
    }

    function updateFilteredModel() {
        if (suppressUpdatesWhileLaunching) {
            suppressUpdatesWhileLaunching = false;
            return;
        }
        filteredModel.clear();
        selectedIndex = 0;
        keyboardNavigationActive = false;

        const triggerResult = checkPluginTriggers(searchQuery);
        if (triggerResult.triggered) {
            console.log("AppLauncher: Plugin trigger detected:", triggerResult.trigger, "for plugin:", triggerResult.pluginId);
        }

        let apps = [];
        const allCategory = I18n.tr("All");
        const emptyTriggerPlugins = typeof PluginService !== "undefined" ? PluginService.getPluginsWithEmptyTrigger() : [];

        if (triggerResult.triggered) {
            _isTriggered = true;
            _triggeredCategory = triggerResult.pluginCategory;
            _updatingFromTrigger = true;
            selectedCategory = triggerResult.pluginCategory;
            _updatingFromTrigger = false;
            if (triggerResult.isBuiltIn) {
                apps = AppSearchService.getBuiltInLauncherItems(triggerResult.pluginId, triggerResult.query);
            } else {
                apps = AppSearchService.getPluginItems(triggerResult.pluginCategory, triggerResult.query);
            }
        } else {
            if (_isTriggered) {
                _updatingFromTrigger = true;
                selectedCategory = allCategory;
                _updatingFromTrigger = false;
                _isTriggered = false;
                _triggeredCategory = "";
            }
            if (searchQuery.length === 0) {
                if (selectedCategory === allCategory) {
                    let emptyTriggerItems = [];
                    emptyTriggerPlugins.forEach(pluginId => {
                        const plugin = PluginService.getLauncherPlugin(pluginId);
                        const pluginCategory = plugin.name || pluginId;
                        const items = AppSearchService.getPluginItems(pluginCategory, "");
                        emptyTriggerItems = emptyTriggerItems.concat(items);
                    });
                    const builtInEmptyTrigger = AppSearchService.getBuiltInLauncherPluginsWithEmptyTrigger();
                    builtInEmptyTrigger.forEach(pluginId => {
                        const items = AppSearchService.getBuiltInLauncherItems(pluginId, "");
                        emptyTriggerItems = emptyTriggerItems.concat(items);
                    });
                    const coreItems = AppSearchService.getCoreApps("");
                    apps = AppSearchService.applications.concat(emptyTriggerItems).concat(coreItems);
                } else {
                    apps = AppSearchService.getAppsInCategory(selectedCategory).slice(0, maxResults);
                    const coreItems = AppSearchService.getCoreApps("").filter(app => app.categories.includes(selectedCategory));
                    apps = apps.concat(coreItems);
                }
            } else {
                if (selectedCategory === allCategory) {
                    apps = AppSearchService.searchApplications(searchQuery);

                    let emptyTriggerItems = [];
                    emptyTriggerPlugins.forEach(pluginId => {
                        const plugin = PluginService.getLauncherPlugin(pluginId);
                        const pluginCategory = plugin.name || pluginId;
                        const items = AppSearchService.getPluginItems(pluginCategory, searchQuery);
                        emptyTriggerItems = emptyTriggerItems.concat(items);
                    });
                    const builtInEmptyTrigger = AppSearchService.getBuiltInLauncherPluginsWithEmptyTrigger();
                    builtInEmptyTrigger.forEach(pluginId => {
                        const items = AppSearchService.getBuiltInLauncherItems(pluginId, searchQuery);
                        emptyTriggerItems = emptyTriggerItems.concat(items);
                    });

                    const coreItems = AppSearchService.getCoreApps(searchQuery);
                    apps = apps.concat(emptyTriggerItems).concat(coreItems);
                } else {
                    const categoryApps = AppSearchService.getAppsInCategory(selectedCategory);
                    if (categoryApps.length > 0) {
                        const allSearchResults = AppSearchService.searchApplications(searchQuery);
                        const categoryNames = new Set(categoryApps.map(app => app.name));
                        apps = allSearchResults.filter(searchApp => categoryNames.has(searchApp.name)).slice(0, maxResults);
                    } else {
                        apps = [];
                    }

                    const coreItems = AppSearchService.getCoreApps(searchQuery).filter(app => app.categories.includes(selectedCategory));
                    apps = apps.concat(coreItems);
                }
            }
        }

        if (searchQuery.length === 0) {
            if (SettingsData.sortAppsAlphabetically) {
                apps = apps.sort((a, b) => {
                    return (a.name || "").localeCompare(b.name || "");
                });
            } else {
                apps = apps.sort((a, b) => {
                    const aId = a.id || a.execString || a.exec || "";
                    const bId = b.id || b.execString || b.exec || "";
                    const aUsage = appUsageRanking[aId] ? appUsageRanking[aId].usageCount : 0;
                    const bUsage = appUsageRanking[bId] ? appUsageRanking[bId].usageCount : 0;
                    if (aUsage !== bUsage) {
                        return bUsage - aUsage;
                    }
                    return (a.name || "").localeCompare(b.name || "");
                });
            }
        }

        const seenNames = new Set();
        const uniqueApps = [];
        apps.forEach(app => {
            if (app) {
                const itemKey = app.name + "|" + (app.execString || app.exec || app.action || "");
                if (seenNames.has(itemKey)) {
                    return;
                }
                seenNames.add(itemKey);
                uniqueApps.push(app);

                const isPluginItem = app.isCore ? false : (app.action !== undefined);
                filteredModel.append({
                    "name": app.name || "",
                    "exec": app.execString || app.exec || app.action || "",
                    "icon": app.icon !== undefined ? String(app.icon) : (isPluginItem ? "" : "application-x-executable"),
                    "comment": app.comment || "",
                    "categories": app.categories || [],
                    "isPlugin": isPluginItem,
                    "isCore": app.isCore === true,
                    "isBuiltInLauncher": app.isBuiltInLauncher === true,
                    "appIndex": uniqueApps.length - 1,
                    "pinned": app._pinned === true
                });
            }
        });

        root._uniqueApps = uniqueApps;
    }

    function selectNext() {
        if (filteredModel.count === 0) {
            return;
        }
        keyboardNavigationActive = true;
        selectedIndex = viewMode === "grid" ? Math.min(selectedIndex + gridColumns, filteredModel.count - 1) : Math.min(selectedIndex + 1, filteredModel.count - 1);
    }

    function selectPrevious() {
        if (filteredModel.count === 0) {
            return;
        }
        keyboardNavigationActive = true;
        selectedIndex = viewMode === "grid" ? Math.max(selectedIndex - gridColumns, 0) : Math.max(selectedIndex - 1, 0);
    }

    function selectNextInRow() {
        if (filteredModel.count === 0 || viewMode !== "grid") {
            return;
        }
        keyboardNavigationActive = true;
        selectedIndex = Math.min(selectedIndex + 1, filteredModel.count - 1);
    }

    function selectPreviousInRow() {
        if (filteredModel.count === 0 || viewMode !== "grid") {
            return;
        }
        keyboardNavigationActive = true;
        selectedIndex = Math.max(selectedIndex - 1, 0);
    }

    function launchSelected() {
        if (filteredModel.count === 0 || selectedIndex < 0 || selectedIndex >= filteredModel.count) {
            return;
        }
        const selectedApp = filteredModel.get(selectedIndex);
        launchApp(selectedApp);
    }

    function launchApp(appData) {
        if (!appData || typeof appData.appIndex === "undefined" || appData.appIndex < 0 || appData.appIndex >= _uniqueApps.length)
            return;
        suppressUpdatesWhileLaunching = true;

        const actualApp = _uniqueApps[appData.appIndex];

        if (appData.isBuiltInLauncher) {
            AppSearchService.executeBuiltInLauncherItem(actualApp);
            appLaunched(appData);
            return;
        }

        if (appData.isCore) {
            AppSearchService.executeCoreApp(actualApp);
            appLaunched(appData);
            return;
        }

        if (appData.isPlugin) {
            const pluginId = getPluginIdForItem(actualApp);
            if (pluginId) {
                AppSearchService.executePluginItem(actualApp, pluginId);
                appLaunched(appData);
                return;
            }
            return;
        }

        SessionService.launchDesktopEntry(actualApp);
        appLaunched(appData);
        AppUsageHistoryData.addAppUsage(actualApp);
    }

    function reset() {
        suppressUpdatesWhileLaunching = false;
        searchQuery = "";
        selectedIndex = 0;
        setCategory(I18n.tr("All"));
        updateFilteredModel();
    }

    function setCategory(category) {
        selectedCategory = category;
        categorySelected(category);
    }

    function setViewMode(mode) {
        viewMode = mode;
        viewModeSelected(mode);
    }

    onSearchQueryChanged: {
        if (!_initialized)
            return;
        if (debounceSearch) {
            searchDebounceTimer.restart();
        } else {
            updateFilteredModel();
        }
    }

    onSelectedCategoryChanged: {
        if (_updatingFromTrigger || !_initialized)
            return;
        updateFilteredModel();
    }

    onAppUsageRankingChanged: {
        if (_initialized)
            updateFilteredModel();
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            if (!root._initialized)
                return;
            root.updateCategories();
            root.updateFilteredModel();
        }
    }

    ListModel {
        id: filteredModel
    }

    Timer {
        id: searchDebounceTimer

        interval: root.debounceInterval
        repeat: false
        onTriggered: updateFilteredModel()
    }

    function checkPluginTriggers(query) {
        if (!query)
            return {
                triggered: false,
                pluginCategory: "",
                query: ""
            };

        const builtInTriggers = AppSearchService.getBuiltInLauncherTriggers();
        for (const trigger in builtInTriggers) {
            if (!query.startsWith(trigger))
                continue;
            const pluginId = builtInTriggers[trigger];
            const plugin = AppSearchService.builtInPlugins[pluginId];
            if (!plugin)
                continue;
            return {
                triggered: true,
                pluginId: pluginId,
                pluginCategory: plugin.name,
                query: query.substring(trigger.length).trim(),
                trigger: trigger,
                isBuiltIn: true
            };
        }

        if (typeof PluginService === "undefined")
            return {
                triggered: false,
                pluginCategory: "",
                query: ""
            };

        const triggers = PluginService.getAllPluginTriggers();
        for (const trigger in triggers) {
            if (!query.startsWith(trigger))
                continue;
            const pluginId = triggers[trigger];
            const plugin = PluginService.getLauncherPlugin(pluginId);
            if (!plugin)
                continue;
            return {
                triggered: true,
                pluginId: pluginId,
                pluginCategory: plugin.name || pluginId,
                query: query.substring(trigger.length).trim(),
                trigger: trigger,
                isBuiltIn: false
            };
        }

        return {
            triggered: false,
            pluginCategory: "",
            query: ""
        };
    }

    function getPluginIdForItem(item) {
        if (!item || !item.categories || typeof PluginService === "undefined") {
            return null;
        }

        const launchers = PluginService.getLauncherPlugins();
        for (const pluginId in launchers) {
            const plugin = launchers[pluginId];
            const pluginCategory = plugin.name || pluginId;

            let hasCategory = false;
            if (Array.isArray(item.categories)) {
                hasCategory = item.categories.includes(pluginCategory);
            } else if (item.categories && typeof item.categories.count !== "undefined") {
                for (let i = 0; i < item.categories.count; i++) {
                    if (item.categories.get(i) === pluginCategory) {
                        hasCategory = true;
                        break;
                    }
                }
            }

            if (hasCategory) {
                return pluginId;
            }
        }
        return null;
    }
}
