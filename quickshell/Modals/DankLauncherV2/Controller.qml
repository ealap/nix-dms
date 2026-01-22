pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "Scorer.js" as Scorer

Item {
    id: root

    property string searchQuery: ""
    property string searchMode: "all"
    property string previousSearchMode: "all"
    property bool autoSwitchedToFiles: false
    property bool isFileSearching: false
    property var sections: []
    property var flatModel: []
    property int selectedFlatIndex: 0
    property var selectedItem: null
    property bool isSearching: false
    property string activePluginId: ""
    property var collapsedSections: ({})
    property bool keyboardNavigationActive: false
    property var sectionViewModes: ({})
    property var pluginViewPreferences: ({})
    property int gridColumns: SettingsData.appLauncherGridColumns
    property int viewModeVersion: 0
    property string viewModeContext: "spotlight"

    signal itemExecuted
    signal searchCompleted
    signal modeChanged(string mode)
    signal viewModeChanged(string sectionId, string mode)
    signal searchQueryRequested(string query)

    Connections {
        target: SettingsData
        function onSortAppsAlphabeticallyChanged() {
            AppSearchService.invalidateLauncherCache();
        }
    }

    readonly property var sectionDefinitions: [
        {
            id: "calculator",
            title: I18n.tr("Calculator"),
            icon: "calculate",
            priority: 0,
            defaultViewMode: "list"
        },
        {
            id: "favorites",
            title: I18n.tr("Pinned"),
            icon: "push_pin",
            priority: 1,
            defaultViewMode: "list"
        },
        {
            id: "apps",
            title: I18n.tr("Applications"),
            icon: "apps",
            priority: 2,
            defaultViewMode: "list"
        },
        {
            id: "browse_plugins",
            title: I18n.tr("Browse"),
            icon: "category",
            priority: 2.5,
            defaultViewMode: "grid"
        },
        {
            id: "files",
            title: I18n.tr("Files"),
            icon: "folder",
            priority: 4,
            defaultViewMode: "list"
        },
        {
            id: "fallback",
            title: I18n.tr("Commands"),
            icon: "terminal",
            priority: 5,
            defaultViewMode: "list"
        }
    ]

    property string pluginFilter: ""
    property string activePluginName: ""

    function getSectionViewMode(sectionId) {
        if (sectionId === "browse_plugins")
            return "list";
        if (pluginViewPreferences[sectionId]?.enforced)
            return pluginViewPreferences[sectionId].mode;
        if (sectionViewModes[sectionId])
            return sectionViewModes[sectionId];

        var savedModes = viewModeContext === "appDrawer" ? (SettingsData.appDrawerSectionViewModes || {}) : (SettingsData.spotlightSectionViewModes || {});
        if (savedModes[sectionId])
            return savedModes[sectionId];

        for (var i = 0; i < sectionDefinitions.length; i++) {
            if (sectionDefinitions[i].id === sectionId)
                return sectionDefinitions[i].defaultViewMode || "list";
        }
        return "list";
    }

    function setSectionViewMode(sectionId, mode) {
        if (sectionId === "browse_plugins")
            return;
        if (pluginViewPreferences[sectionId]?.enforced)
            return;
        sectionViewModes = Object.assign({}, sectionViewModes, {
            [sectionId]: mode
        });
        viewModeVersion++;
        if (viewModeContext === "appDrawer") {
            var savedModes = Object.assign({}, SettingsData.appDrawerSectionViewModes || {}, {
                [sectionId]: mode
            });
            SettingsData.appDrawerSectionViewModes = savedModes;
        } else {
            var savedModes = Object.assign({}, SettingsData.spotlightSectionViewModes || {}, {
                [sectionId]: mode
            });
            SettingsData.spotlightSectionViewModes = savedModes;
        }
        viewModeChanged(sectionId, mode);
    }

    function canChangeSectionViewMode(sectionId) {
        if (sectionId === "browse_plugins")
            return false;
        return !pluginViewPreferences[sectionId]?.enforced;
    }

    function canCollapseSection(sectionId) {
        return searchMode === "all";
    }

    function setPluginViewPreference(pluginId, mode, enforced) {
        var prefs = pluginViewPreferences;
        prefs[pluginId] = {
            mode: mode,
            enforced: enforced || false
        };
        pluginViewPreferences = prefs;
    }

    function applyActivePluginViewPreference(pluginId, isBuiltIn) {
        var sectionId = "plugin_" + pluginId;
        var pref = null;
        if (isBuiltIn) {
            var builtIn = AppSearchService.builtInPlugins[pluginId];
            if (builtIn && builtIn.viewMode) {
                pref = {
                    mode: builtIn.viewMode,
                    enforced: builtIn.viewModeEnforced === true
                };
            }
        } else {
            pref = PluginService.getPluginViewPreference(pluginId);
        }

        if (pref && pref.mode) {
            setPluginViewPreference(sectionId, pref.mode, pref.enforced);
        } else {
            var prefs = pluginViewPreferences;
            delete prefs[sectionId];
            pluginViewPreferences = prefs;
        }
    }

    function clearActivePluginViewPreference() {
        var prefs = {};
        for (var key in pluginViewPreferences) {
            if (!key.startsWith("plugin_")) {
                prefs[key] = pluginViewPreferences[key];
            }
        }
        pluginViewPreferences = prefs;
    }

    property int _searchVersion: 0

    Timer {
        id: searchDebounce
        interval: searchMode === "all" && searchQuery.length > 0 ? 90 : 60
        onTriggered: root.performSearch()
    }

    Timer {
        id: fileSearchDebounce
        interval: 200
        onTriggered: root.performFileSearch()
    }

    function getOrTransformApp(app) {
        return AppSearchService.getOrTransformApp(app, transformApp);
    }

    function setSearchQuery(query) {
        _searchVersion++;
        searchQuery = query;
        searchDebounce.restart();

        if (searchMode !== "plugins" && (searchMode === "files" || query.startsWith("/")) && query.length > 0) {
            fileSearchDebounce.restart();
        }
    }

    function setMode(mode, isAutoSwitch) {
        if (searchMode === mode)
            return;
        if (isAutoSwitch) {
            previousSearchMode = searchMode;
            autoSwitchedToFiles = true;
        } else {
            autoSwitchedToFiles = false;
        }
        searchMode = mode;
        modeChanged(mode);
        performSearch();
        if (mode === "files") {
            fileSearchDebounce.restart();
        }
    }

    function restorePreviousMode() {
        if (!autoSwitchedToFiles)
            return;
        autoSwitchedToFiles = false;
        searchMode = previousSearchMode;
        modeChanged(previousSearchMode);
        performSearch();
    }

    function cycleMode() {
        var modes = ["all", "apps", "files", "plugins"];
        var currentIndex = modes.indexOf(searchMode);
        var nextIndex = (currentIndex + 1) % modes.length;
        setMode(modes[nextIndex]);
    }

    function reset() {
        searchQuery = "";
        searchMode = "all";
        previousSearchMode = "all";
        autoSwitchedToFiles = false;
        isFileSearching = false;
        sections = [];
        flatModel = [];
        selectedFlatIndex = 0;
        selectedItem = null;
        isSearching = false;
        activePluginId = "";
        activePluginName = "";
        pluginFilter = "";
        collapsedSections = {};
    }

    function clearPluginFilter() {
        if (pluginFilter) {
            pluginFilter = "";
            performSearch();
            return true;
        }
        return false;
    }

    function performSearch() {
        var currentVersion = _searchVersion;
        isSearching = true;

        var cachedSections = AppSearchService.getCachedDefaultSections();
        if (cachedSections && !searchQuery && searchMode === "all" && !pluginFilter) {
            activePluginId = "";
            activePluginName = "";
            clearActivePluginViewPreference();
            sections = cachedSections.map(function (s) {
                var copy = Object.assign({}, s, {
                    items: s.items ? s.items.slice() : []
                });
                if (collapsedSections[s.id] !== undefined)
                    copy.collapsed = collapsedSections[s.id];
                return copy;
            });
            flatModel = Scorer.flattenSections(sections);
            selectedFlatIndex = getFirstItemIndex();
            updateSelectedItem();
            isSearching = false;
            searchCompleted();
            return;
        }

        var allItems = [];

        var triggerMatch = detectTrigger(searchQuery);
        if (triggerMatch.pluginId) {
            activePluginId = triggerMatch.pluginId;
            activePluginName = getPluginName(triggerMatch.pluginId, triggerMatch.isBuiltIn);
            applyActivePluginViewPreference(triggerMatch.pluginId, triggerMatch.isBuiltIn);

            var pluginItems = getPluginItems(triggerMatch.pluginId, triggerMatch.query);
            allItems = allItems.concat(pluginItems);

            if (triggerMatch.isBuiltIn) {
                var builtInItems = AppSearchService.getBuiltInLauncherItems(triggerMatch.pluginId, triggerMatch.query);
                for (var j = 0; j < builtInItems.length; j++) {
                    allItems.push(transformBuiltInLauncherItem(builtInItems[j], triggerMatch.pluginId));
                }
            }

            var dynamicDefs = buildDynamicSectionDefs(allItems);
            var scoredItems = Scorer.scoreItems(allItems, triggerMatch.query, getFrecencyForItem);
            var sortAlpha = !triggerMatch.query && SettingsData.sortAppsAlphabetically;
            sections = Scorer.groupBySection(scoredItems, dynamicDefs, sortAlpha, 500);

            for (var sid in collapsedSections) {
                for (var i = 0; i < sections.length; i++) {
                    if (sections[i].id === sid) {
                        sections[i].collapsed = collapsedSections[sid];
                    }
                }
            }

            flatModel = Scorer.flattenSections(sections);
            selectedFlatIndex = getFirstItemIndex();
            updateSelectedItem();

            isSearching = false;
            searchCompleted();
            return;
        }

        activePluginId = "";
        activePluginName = "";
        clearActivePluginViewPreference();

        if (searchMode === "files") {
            var fileQuery = searchQuery.startsWith("/") ? searchQuery.substring(1).trim() : searchQuery.trim();
            isFileSearching = fileQuery.length >= 2 && DSearchService.dsearchAvailable;
            sections = [];
            flatModel = [];
            selectedFlatIndex = 0;
            selectedItem = null;
            isSearching = false;
            searchCompleted();
            return;
        }

        if (searchMode === "apps") {
            var cachedSections = AppSearchService.getCachedDefaultSections();
            if (cachedSections && !searchQuery) {
                var appSectionIds = ["favorites", "apps"];
                sections = cachedSections.filter(function (s) {
                    return appSectionIds.indexOf(s.id) !== -1;
                }).map(function (s) {
                    var copy = Object.assign({}, s, {
                        items: s.items ? s.items.slice() : []
                    });
                    if (collapsedSections[s.id] !== undefined)
                        copy.collapsed = collapsedSections[s.id];
                    return copy;
                });
                flatModel = Scorer.flattenSections(sections);
                selectedFlatIndex = getFirstItemIndex();
                updateSelectedItem();
                isSearching = false;
                searchCompleted();
                return;
            }

            var apps = searchApps(searchQuery);
            for (var i = 0; i < apps.length; i++) {
                allItems.push(apps[i]);
            }

            var scoredItems = Scorer.scoreItems(allItems, searchQuery, getFrecencyForItem);
            var sortAlpha = !searchQuery && SettingsData.sortAppsAlphabetically;
            sections = Scorer.groupBySection(scoredItems, sectionDefinitions, sortAlpha, searchQuery ? 50 : 500);

            for (var sid in collapsedSections) {
                for (var i = 0; i < sections.length; i++) {
                    if (sections[i].id === sid) {
                        sections[i].collapsed = collapsedSections[sid];
                    }
                }
            }

            flatModel = Scorer.flattenSections(sections);
            selectedFlatIndex = getFirstItemIndex();
            updateSelectedItem();

            isSearching = false;
            searchCompleted();
            return;
        }

        if (searchMode === "plugins") {
            if (!searchQuery && !pluginFilter) {
                var browseItems = getPluginBrowseItems();
                allItems = allItems.concat(browseItems);
            } else if (pluginFilter) {
                var isBuiltInFilter = !!AppSearchService.builtInPlugins[pluginFilter];
                applyActivePluginViewPreference(pluginFilter, isBuiltInFilter);

                var filterItems = getPluginItems(pluginFilter, searchQuery);
                allItems = allItems.concat(filterItems);

                var builtInItems = AppSearchService.getBuiltInLauncherItems(pluginFilter, searchQuery);
                for (var j = 0; j < builtInItems.length; j++) {
                    allItems.push(transformBuiltInLauncherItem(builtInItems[j], pluginFilter));
                }
            } else {
                var emptyTriggerPlugins = getEmptyTriggerPlugins();
                for (var i = 0; i < emptyTriggerPlugins.length; i++) {
                    var pluginId = emptyTriggerPlugins[i];
                    var pItems = getPluginItems(pluginId, searchQuery);
                    allItems = allItems.concat(pItems);
                }

                var builtInLauncherPlugins = getBuiltInEmptyTriggerLaunchers();
                for (var i = 0; i < builtInLauncherPlugins.length; i++) {
                    var pluginId = builtInLauncherPlugins[i];
                    var blItems = AppSearchService.getBuiltInLauncherItems(pluginId, searchQuery);
                    for (var j = 0; j < blItems.length; j++) {
                        allItems.push(transformBuiltInLauncherItem(blItems[j], pluginId));
                    }
                }
            }

            var dynamicDefs = buildDynamicSectionDefs(allItems);
            var scoredItems = Scorer.scoreItems(allItems, searchQuery, getFrecencyForItem);
            var sortAlpha = !searchQuery && SettingsData.sortAppsAlphabetically;
            sections = Scorer.groupBySection(scoredItems, dynamicDefs, sortAlpha, 500);

            for (var sid in collapsedSections) {
                for (var i = 0; i < sections.length; i++) {
                    if (sections[i].id === sid) {
                        sections[i].collapsed = collapsedSections[sid];
                    }
                }
            }

            flatModel = Scorer.flattenSections(sections);
            selectedFlatIndex = getFirstItemIndex();
            updateSelectedItem();

            isSearching = false;
            searchCompleted();
            return;
        }

        var calculatorResult = evaluateCalculator(searchQuery);
        if (calculatorResult) {
            allItems.push(calculatorResult);
        }

        var apps = searchApps(searchQuery);
        allItems = allItems.concat(apps);

        if (searchMode === "all") {
            var includePlugins = !searchQuery || searchQuery.length >= 2;
            if (searchQuery && includePlugins) {
                var allPluginsOrdered = getAllVisiblePluginsOrdered();
                var maxPerPlugin = 10;
                for (var i = 0; i < allPluginsOrdered.length; i++) {
                    var plugin = allPluginsOrdered[i];
                    if (plugin.isBuiltIn) {
                        var blItems = AppSearchService.getBuiltInLauncherItems(plugin.id, searchQuery);
                        var blLimit = Math.min(blItems.length, maxPerPlugin);
                        for (var j = 0; j < blLimit; j++)
                            allItems.push(transformBuiltInLauncherItem(blItems[j], plugin.id));
                    } else {
                        var pItems = getPluginItems(plugin.id, searchQuery);
                        if (pItems.length > maxPerPlugin)
                            pItems = pItems.slice(0, maxPerPlugin);
                        allItems = allItems.concat(pItems);
                    }
                }
            } else if (!searchQuery) {
                var emptyTriggerOrdered = getEmptyTriggerPluginsOrdered();
                for (var i = 0; i < emptyTriggerOrdered.length; i++) {
                    var plugin = emptyTriggerOrdered[i];
                    if (plugin.isBuiltIn) {
                        var blItems = AppSearchService.getBuiltInLauncherItems(plugin.id, searchQuery);
                        for (var j = 0; j < blItems.length; j++)
                            allItems.push(transformBuiltInLauncherItem(blItems[j], plugin.id));
                    } else {
                        var pItems = getPluginItems(plugin.id, searchQuery);
                        allItems = allItems.concat(pItems);
                    }
                }

                var browseItems = getPluginBrowseItems();
                allItems = allItems.concat(browseItems);
            }
        }

        var dynamicDefs = buildDynamicSectionDefs(allItems);

        if (currentVersion !== _searchVersion) {
            isSearching = false;
            return;
        }

        var scoredItems = Scorer.scoreItems(allItems, searchQuery, getFrecencyForItem);
        var sortAlpha = !searchQuery && SettingsData.sortAppsAlphabetically;
        var newSections = Scorer.groupBySection(scoredItems, dynamicDefs, sortAlpha, searchQuery ? 50 : 500);

        if (currentVersion !== _searchVersion) {
            isSearching = false;
            return;
        }

        for (var i = 0; i < newSections.length; i++) {
            var sid = newSections[i].id;
            if (collapsedSections[sid] !== undefined) {
                newSections[i].collapsed = collapsedSections[sid];
            }
        }

        sections = newSections;
        flatModel = Scorer.flattenSections(sections);

        if (!AppSearchService.isCacheValid() && !searchQuery && searchMode === "all" && !pluginFilter) {
            AppSearchService.setCachedDefaultSections(sections, flatModel);
        }

        selectedFlatIndex = getFirstItemIndex();
        updateSelectedItem();

        isSearching = false;
        searchCompleted();
    }

    function performFileSearch() {
        if (!DSearchService.dsearchAvailable)
            return;
        var fileQuery = "";
        if (searchQuery.startsWith("/")) {
            fileQuery = searchQuery.substring(1).trim();
        } else if (searchMode === "files") {
            fileQuery = searchQuery.trim();
        } else {
            return;
        }

        if (fileQuery.length < 2) {
            isFileSearching = false;
            return;
        }

        isFileSearching = true;
        var params = {
            limit: 20,
            fuzzy: true,
            sort: "score",
            desc: true
        };

        DSearchService.search(fileQuery, params, function (response) {
            isFileSearching = false;
            if (response.error)
                return;
            var fileItems = [];
            var hits = response.result?.hits || [];

            for (var i = 0; i < hits.length; i++) {
                var hit = hits[i];
                fileItems.push(transformFileResult({
                    path: hit.id || "",
                    score: hit.score || 0
                }));
            }

            var fileSection = {
                id: "files",
                title: I18n.tr("Files"),
                icon: "folder",
                priority: 4,
                items: fileItems,
                collapsed: collapsedSections["files"] || false
            };

            var newSections;
            if (searchMode === "files") {
                newSections = fileItems.length > 0 ? [fileSection] : [];
            } else {
                var existingNonFile = sections.filter(function (s) {
                    return s.id !== "files";
                });
                if (fileItems.length > 0) {
                    newSections = existingNonFile.concat([fileSection]);
                } else {
                    newSections = existingNonFile;
                }
            }
            newSections.sort(function (a, b) {
                return a.priority - b.priority;
            });
            sections = newSections;

            flatModel = Scorer.flattenSections(sections);
            if (selectedFlatIndex >= flatModel.length) {
                selectedFlatIndex = getFirstItemIndex();
            }
            updateSelectedItem();
        });
    }

    function searchApps(query) {
        var apps = AppSearchService.searchApplications(query);
        var items = [];

        for (var i = 0; i < apps.length; i++) {
            items.push(getOrTransformApp(apps[i]));
        }

        var coreApps = AppSearchService.getCoreApps(query);
        for (var i = 0; i < coreApps.length; i++) {
            items.push(transformCoreApp(coreApps[i]));
        }

        return items;
    }

    function transformApp(app) {
        var appId = app.id || app.execString || app.exec || "";
        var override = SessionData.getAppOverride(appId);

        var actions = [];
        if (app.actions && app.actions.length > 0) {
            for (var i = 0; i < app.actions.length; i++) {
                actions.push({
                    name: app.actions[i].name,
                    icon: "play_arrow",
                    actionData: app.actions[i]
                });
            }
        }

        if (SessionService.nvidiaCommand) {
            actions.push({
                name: I18n.tr("Launch on dGPU"),
                icon: "memory",
                action: "launch_dgpu"
            });
        }

        return {
            id: appId,
            type: "app",
            name: override?.name || app.name || "",
            subtitle: override?.comment || app.comment || "",
            icon: override?.icon || app.icon || "application-x-executable",
            iconType: "image",
            section: "apps",
            data: app,
            keywords: app.keywords || [],
            actions: actions,
            primaryAction: {
                name: I18n.tr("Launch"),
                icon: "open_in_new",
                action: "launch"
            }
        };
    }

    function transformCoreApp(app) {
        var iconName = "apps";
        var iconType = "material";

        if (app.icon) {
            if (app.icon.startsWith("svg+corner:")) {
                iconType = "composite";
            } else if (app.icon.startsWith("material:")) {
                iconName = app.icon.substring(9);
            } else {
                iconName = app.icon;
                iconType = "image";
            }
        }

        return {
            id: app.builtInPluginId || app.action || "",
            type: "app",
            name: app.name || "",
            subtitle: app.comment || "",
            icon: iconName,
            iconType: iconType,
            iconFull: app.icon,
            section: "apps",
            data: app,
            isCore: true,
            actions: [],
            primaryAction: {
                name: I18n.tr("Open"),
                icon: "open_in_new",
                action: "launch"
            }
        };
    }

    function transformBuiltInLauncherItem(item, pluginId) {
        var rawIcon = item.icon || "extension";
        var icon = stripIconPrefix(rawIcon);
        var iconType = item.iconType;
        if (!iconType) {
            if (rawIcon.startsWith("material:"))
                iconType = "material";
            else if (rawIcon.startsWith("unicode:"))
                iconType = "unicode";
            else
                iconType = "image";
        }

        return {
            id: item.action || "",
            type: "plugin",
            name: item.name || "",
            subtitle: item.comment || "",
            icon: icon,
            iconType: iconType,
            section: "plugin_" + pluginId,
            data: item,
            pluginId: pluginId,
            isBuiltInLauncher: true,
            keywords: item.keywords || [],
            actions: [],
            primaryAction: {
                name: I18n.tr("Open"),
                icon: "open_in_new",
                action: "execute"
            }
        };
    }

    function transformFileResult(file) {
        var filename = file.path ? file.path.split("/").pop() : "";
        var dirname = file.path ? file.path.substring(0, file.path.lastIndexOf("/")) : "";

        return {
            id: file.path || "",
            type: "file",
            name: filename,
            subtitle: dirname,
            icon: getFileIcon(filename),
            iconType: "material",
            section: "files",
            data: file,
            actions: [
                {
                    name: I18n.tr("Open folder"),
                    icon: "folder_open",
                    action: "open_folder"
                },
                {
                    name: I18n.tr("Copy path"),
                    icon: "content_copy",
                    action: "copy_path"
                }
            ],
            primaryAction: {
                name: I18n.tr("Open"),
                icon: "open_in_new",
                action: "open"
            }
        };
    }

    function getFileIcon(filename) {
        var ext = filename.lastIndexOf(".") > 0 ? filename.substring(filename.lastIndexOf(".") + 1).toLowerCase() : "";

        var iconMap = {
            "pdf": "picture_as_pdf",
            "doc": "description",
            "docx": "description",
            "odt": "description",
            "xls": "table_chart",
            "xlsx": "table_chart",
            "ods": "table_chart",
            "ppt": "slideshow",
            "pptx": "slideshow",
            "odp": "slideshow",
            "txt": "article",
            "md": "article",
            "rst": "article",
            "jpg": "image",
            "jpeg": "image",
            "png": "image",
            "gif": "image",
            "svg": "image",
            "webp": "image",
            "mp3": "audio_file",
            "wav": "audio_file",
            "flac": "audio_file",
            "ogg": "audio_file",
            "mp4": "video_file",
            "mkv": "video_file",
            "avi": "video_file",
            "webm": "video_file",
            "zip": "folder_zip",
            "tar": "folder_zip",
            "gz": "folder_zip",
            "7z": "folder_zip",
            "rar": "folder_zip",
            "js": "code",
            "ts": "code",
            "py": "code",
            "rs": "code",
            "go": "code",
            "java": "code",
            "c": "code",
            "cpp": "code",
            "h": "code",
            "html": "web",
            "css": "web",
            "htm": "web",
            "json": "data_object",
            "xml": "data_object",
            "yaml": "data_object",
            "yml": "data_object",
            "sh": "terminal",
            "bash": "terminal",
            "zsh": "terminal"
        };

        return iconMap[ext] || "insert_drive_file";
    }

    function evaluateCalculator(query) {
        if (!query || query.length === 0)
            return null;

        var mathExpr = query.replace(/[^0-9+\-*/().%\s^]/g, "");
        if (mathExpr.length < 2)
            return null;

        var hasMath = /[+\-*/^%]/.test(query) && /\d/.test(query);
        if (!hasMath)
            return null;

        try {
            var sanitized = mathExpr.replace(/\^/g, "**");
            var result = Function('"use strict"; return (' + sanitized + ')')();

            if (typeof result === "number" && isFinite(result)) {
                var displayResult = Number.isInteger(result) ? result.toString() : result.toFixed(6).replace(/\.?0+$/, "");

                return {
                    id: "calculator_result",
                    type: "calculator",
                    name: displayResult,
                    subtitle: query + " =",
                    icon: "calculate",
                    iconType: "material",
                    section: "calculator",
                    data: {
                        expression: query,
                        result: result
                    },
                    actions: [],
                    primaryAction: {
                        name: I18n.tr("Copy"),
                        icon: "content_copy",
                        action: "copy"
                    }
                };
            }
        } catch (e) {}

        return null;
    }

    function detectTrigger(query) {
        if (!query || query.length === 0)
            return {
                pluginId: null,
                query: query
            };

        var pluginTriggers = PluginService.getAllPluginTriggers();
        for (var trigger in pluginTriggers) {
            if (trigger && query.startsWith(trigger)) {
                return {
                    pluginId: pluginTriggers[trigger],
                    query: query.substring(trigger.length).trim()
                };
            }
        }

        var builtInTriggers = AppSearchService.getBuiltInLauncherTriggers();
        for (var trigger in builtInTriggers) {
            if (trigger && query.startsWith(trigger)) {
                return {
                    pluginId: builtInTriggers[trigger],
                    query: query.substring(trigger.length).trim(),
                    isBuiltIn: true
                };
            }
        }

        return {
            pluginId: null,
            query: query
        };
    }

    function getEmptyTriggerPlugins() {
        var plugins = PluginService.getPluginsWithEmptyTrigger();
        var visible = plugins.filter(function (pluginId) {
            return SettingsData.getPluginAllowWithoutTrigger(pluginId);
        });
        return sortPluginIdsByOrder(visible);
    }

    function getAllLauncherPluginIds() {
        var launchers = PluginService.getLauncherPlugins();
        return Object.keys(launchers);
    }

    function getVisibleLauncherPluginIds() {
        var launchers = PluginService.getLauncherPlugins();
        var visible = Object.keys(launchers).filter(function (pluginId) {
            return SettingsData.getPluginAllowWithoutTrigger(pluginId);
        });
        return sortPluginIdsByOrder(visible);
    }

    function getAllBuiltInLauncherIds() {
        var launchers = AppSearchService.getBuiltInLauncherPlugins();
        return Object.keys(launchers);
    }

    function getVisibleBuiltInLauncherIds() {
        var launchers = AppSearchService.getBuiltInLauncherPlugins();
        var visible = Object.keys(launchers).filter(function (pluginId) {
            return SettingsData.getPluginAllowWithoutTrigger(pluginId);
        });
        return sortPluginIdsByOrder(visible);
    }

    function sortPluginIdsByOrder(pluginIds) {
        var order = SettingsData.launcherPluginOrder || [];
        if (order.length === 0)
            return pluginIds;
        var orderMap = {};
        for (var i = 0; i < order.length; i++)
            orderMap[order[i]] = i;
        return pluginIds.slice().sort(function (a, b) {
            var aOrder = orderMap[a] !== undefined ? orderMap[a] : 9999;
            var bOrder = orderMap[b] !== undefined ? orderMap[b] : 9999;
            return aOrder - bOrder;
        });
    }

    function getAllVisiblePluginsOrdered() {
        var thirdPartyLaunchers = PluginService.getLauncherPlugins() || {};
        var builtInLaunchers = AppSearchService.getBuiltInLauncherPlugins() || {};
        var all = [];
        for (var id in thirdPartyLaunchers) {
            if (SettingsData.getPluginAllowWithoutTrigger(id))
                all.push({
                    id: id,
                    isBuiltIn: false
                });
        }
        for (var id in builtInLaunchers) {
            if (SettingsData.getPluginAllowWithoutTrigger(id))
                all.push({
                    id: id,
                    isBuiltIn: true
                });
        }
        var order = SettingsData.launcherPluginOrder || [];
        if (order.length === 0)
            return all;
        var orderMap = {};
        for (var i = 0; i < order.length; i++)
            orderMap[order[i]] = i;
        return all.sort(function (a, b) {
            var aOrder = orderMap[a.id] !== undefined ? orderMap[a.id] : 9999;
            var bOrder = orderMap[b.id] !== undefined ? orderMap[b.id] : 9999;
            return aOrder - bOrder;
        });
    }

    function getEmptyTriggerPluginsOrdered() {
        var thirdParty = PluginService.getPluginsWithEmptyTrigger() || [];
        var builtIn = AppSearchService.getBuiltInLauncherPluginsWithEmptyTrigger() || [];
        var all = [];
        for (var i = 0; i < thirdParty.length; i++) {
            var id = thirdParty[i];
            if (SettingsData.getPluginAllowWithoutTrigger(id))
                all.push({
                    id: id,
                    isBuiltIn: false
                });
        }
        for (var i = 0; i < builtIn.length; i++) {
            var id = builtIn[i];
            if (SettingsData.getPluginAllowWithoutTrigger(id))
                all.push({
                    id: id,
                    isBuiltIn: true
                });
        }
        var order = SettingsData.launcherPluginOrder || [];
        if (order.length === 0)
            return all;
        var orderMap = {};
        for (var i = 0; i < order.length; i++)
            orderMap[order[i]] = i;
        return all.sort(function (a, b) {
            var aOrder = orderMap[a.id] !== undefined ? orderMap[a.id] : 9999;
            var bOrder = orderMap[b.id] !== undefined ? orderMap[b.id] : 9999;
            return aOrder - bOrder;
        });
    }

    function getPluginBrowseItems() {
        var items = [];

        var launchers = PluginService.getLauncherPlugins();
        for (var pluginId in launchers) {
            var plugin = launchers[pluginId];
            var trigger = PluginService.getPluginTrigger(pluginId);
            var rawIcon = plugin.icon || "extension";
            items.push({
                id: "browse_" + pluginId,
                type: "plugin_browse",
                name: plugin.name || pluginId,
                subtitle: trigger ? I18n.tr("Trigger: %1").arg(trigger) : I18n.tr("No trigger"),
                icon: stripIconPrefix(rawIcon),
                iconType: detectIconType(rawIcon),
                section: "browse_plugins",
                data: {
                    pluginId: pluginId,
                    plugin: plugin
                },
                actions: [],
                primaryAction: {
                    name: I18n.tr("Browse"),
                    icon: "arrow_forward",
                    action: "browse_plugin"
                }
            });
        }

        var builtInLaunchers = AppSearchService.getBuiltInLauncherPlugins();
        for (var pluginId in builtInLaunchers) {
            var plugin = builtInLaunchers[pluginId];
            var trigger = AppSearchService.getBuiltInPluginTrigger(pluginId);
            items.push({
                id: "browse_" + pluginId,
                type: "plugin_browse",
                name: plugin.name || pluginId,
                subtitle: trigger ? I18n.tr("Trigger: %1").arg(trigger) : I18n.tr("No trigger"),
                icon: plugin.cornerIcon || "extension",
                iconType: "material",
                section: "browse_plugins",
                data: {
                    pluginId: pluginId,
                    plugin: plugin,
                    isBuiltIn: true
                },
                actions: [],
                primaryAction: {
                    name: I18n.tr("Browse"),
                    icon: "arrow_forward",
                    action: "browse_plugin"
                }
            });
        }

        return items;
    }

    function getBuiltInEmptyTriggerLaunchers() {
        var plugins = AppSearchService.getBuiltInLauncherPluginsWithEmptyTrigger();
        var visible = plugins.filter(function (pluginId) {
            return SettingsData.getPluginAllowWithoutTrigger(pluginId);
        });
        return sortPluginIdsByOrder(visible);
    }

    function getPluginItems(pluginId, query) {
        var items = AppSearchService.getPluginItemsForPlugin(pluginId, query);
        var transformed = [];

        for (var i = 0; i < items.length; i++) {
            transformed.push(transformPluginItem(items[i], pluginId));
        }

        return transformed;
    }

    function detectIconType(iconName) {
        if (!iconName)
            return "material";
        if (iconName.startsWith("unicode:"))
            return "unicode";
        if (iconName.startsWith("material:"))
            return "material";
        if (iconName.startsWith("image:"))
            return "image";
        if (iconName.indexOf("/") >= 0 || iconName.indexOf(".") >= 0)
            return "image";
        if (/^[a-z]+-[a-z]/.test(iconName.toLowerCase()))
            return "image";
        return "material";
    }

    function stripIconPrefix(iconName) {
        if (!iconName)
            return "extension";
        if (iconName.startsWith("unicode:"))
            return iconName.substring(8);
        if (iconName.startsWith("material:"))
            return iconName.substring(9);
        if (iconName.startsWith("image:"))
            return iconName.substring(6);
        return iconName;
    }

    function getPluginName(pluginId, isBuiltIn) {
        if (isBuiltIn) {
            var plugin = AppSearchService.builtInPlugins[pluginId];
            return plugin ? plugin.name : pluginId;
        }
        var launchers = PluginService.getLauncherPlugins();
        if (launchers[pluginId]) {
            return launchers[pluginId].name || pluginId;
        }
        return pluginId;
    }

    function getPluginMetadata(pluginId) {
        var builtIn = AppSearchService.builtInPlugins[pluginId];
        if (builtIn) {
            return {
                name: builtIn.name || pluginId,
                icon: builtIn.cornerIcon || "extension"
            };
        }
        var launchers = PluginService.getLauncherPlugins();
        if (launchers[pluginId]) {
            var rawIcon = launchers[pluginId].icon || "extension";
            return {
                name: launchers[pluginId].name || pluginId,
                icon: stripIconPrefix(rawIcon)
            };
        }
        return {
            name: pluginId,
            icon: "extension"
        };
    }

    function buildDynamicSectionDefs(items) {
        var baseDefs = sectionDefinitions.slice();
        var pluginSections = {};
        var basePriority = 2.6;

        for (var i = 0; i < items.length; i++) {
            var section = items[i].section;
            if (!section || !section.startsWith("plugin_"))
                continue;
            if (pluginSections[section])
                continue;
            var pluginId = section.substring(7);
            var meta = getPluginMetadata(pluginId);
            var viewPref = getPluginViewPref(pluginId);

            pluginSections[section] = {
                id: section,
                title: meta.name,
                icon: meta.icon,
                priority: basePriority,
                defaultViewMode: viewPref.mode || "list"
            };

            if (viewPref.enforced) {
                setPluginViewPreference(section, viewPref.mode, true);
            }

            basePriority += 0.01;
        }

        for (var sectionId in pluginSections) {
            baseDefs.push(pluginSections[sectionId]);
        }

        baseDefs.sort(function (a, b) {
            return a.priority - b.priority;
        });
        return baseDefs;
    }

    function getPluginViewPref(pluginId) {
        var builtIn = AppSearchService.builtInPlugins[pluginId];
        if (builtIn && builtIn.viewMode) {
            return {
                mode: builtIn.viewMode,
                enforced: builtIn.viewModeEnforced === true
            };
        }

        var pref = PluginService.getPluginViewPreference(pluginId);
        if (pref && pref.mode) {
            return pref;
        }

        return {
            mode: "list",
            enforced: false
        };
    }

    function transformPluginItem(item, pluginId) {
        var rawIcon = item.icon || "extension";
        var icon = stripIconPrefix(rawIcon);
        var iconType = item.iconType;
        if (!iconType) {
            if (rawIcon.startsWith("material:"))
                iconType = "material";
            else if (rawIcon.startsWith("unicode:"))
                iconType = "unicode";
            else
                iconType = "image";
        }

        return {
            id: item.id || item.name || "",
            type: "plugin",
            name: item.name || "",
            subtitle: item.comment || item.description || "",
            icon: icon,
            iconType: iconType,
            section: "plugin_" + pluginId,
            data: item,
            pluginId: pluginId,
            keywords: item.keywords || [],
            actions: item.actions || [],
            primaryAction: item.primaryAction || {
                name: I18n.tr("Select"),
                icon: "check",
                action: "execute"
            }
        };
    }

    function getFrecencyForItem(item) {
        if (item.type !== "app")
            return null;

        var appId = item.id;
        var usageRanking = AppUsageHistoryData.appUsageRanking || {};

        var idVariants = [appId, appId.replace(".desktop", "")];
        var usageData = null;

        for (var i = 0; i < idVariants.length; i++) {
            if (usageRanking[idVariants[i]]) {
                usageData = usageRanking[idVariants[i]];
                break;
            }
        }

        return {
            usageCount: usageData?.usageCount || 0
        };
    }

    function getFirstItemIndex() {
        for (var i = 0; i < flatModel.length; i++) {
            if (!flatModel[i].isHeader)
                return i;
        }
        return 0;
    }

    function updateSelectedItem() {
        if (selectedFlatIndex >= 0 && selectedFlatIndex < flatModel.length) {
            var entry = flatModel[selectedFlatIndex];
            selectedItem = entry.isHeader ? null : entry.item;
        } else {
            selectedItem = null;
        }
    }

    function getCurrentSectionViewMode() {
        if (selectedFlatIndex < 0 || selectedFlatIndex >= flatModel.length)
            return "list";
        var entry = flatModel[selectedFlatIndex];
        if (!entry || entry.isHeader)
            return "list";
        return getSectionViewMode(entry.sectionId);
    }

    function findNextNonHeaderIndex(startIndex) {
        for (var i = startIndex; i < flatModel.length; i++) {
            if (!flatModel[i].isHeader)
                return i;
        }
        return -1;
    }

    function findPrevNonHeaderIndex(startIndex) {
        for (var i = startIndex; i >= 0; i--) {
            if (!flatModel[i].isHeader)
                return i;
        }
        return -1;
    }

    function getSectionBounds(sectionId) {
        var start = -1, end = -1;
        for (var i = 0; i < flatModel.length; i++) {
            if (flatModel[i].isHeader && flatModel[i].section?.id === sectionId) {
                start = i + 1;
            } else if (start >= 0 && !flatModel[i].isHeader && flatModel[i].sectionId === sectionId) {
                end = i;
            } else if (start >= 0 && end >= 0 && flatModel[i].sectionId !== sectionId) {
                break;
            }
        }
        return {
            start: start,
            end: end,
            count: end >= start ? end - start + 1 : 0
        };
    }

    function getGridColumns(sectionId) {
        var mode = getSectionViewMode(sectionId);
        if (mode === "tile")
            return 3;
        if (mode === "grid")
            return gridColumns;
        return 1;
    }

    function selectNext() {
        keyboardNavigationActive = true;
        if (flatModel.length === 0)
            return;
        var entry = flatModel[selectedFlatIndex];
        if (!entry || entry.isHeader) {
            var next = findNextNonHeaderIndex(selectedFlatIndex + 1);
            if (next !== -1) {
                selectedFlatIndex = next;
                updateSelectedItem();
            }
            return;
        }

        var viewMode = getSectionViewMode(entry.sectionId);
        if (viewMode === "list") {
            var next = findNextNonHeaderIndex(selectedFlatIndex + 1);
            if (next !== -1) {
                selectedFlatIndex = next;
                updateSelectedItem();
            }
            return;
        }

        var bounds = getSectionBounds(entry.sectionId);
        var cols = getGridColumns(entry.sectionId);
        var posInSection = selectedFlatIndex - bounds.start;
        var newPosInSection = posInSection + cols;

        if (newPosInSection < bounds.count) {
            selectedFlatIndex = bounds.start + newPosInSection;
            updateSelectedItem();
        } else {
            var nextSection = findNextNonHeaderIndex(bounds.end + 1);
            if (nextSection !== -1) {
                selectedFlatIndex = nextSection;
                updateSelectedItem();
            }
        }
    }

    function selectPrevious() {
        keyboardNavigationActive = true;
        if (flatModel.length === 0)
            return;
        var entry = flatModel[selectedFlatIndex];
        if (!entry || entry.isHeader) {
            var prev = findPrevNonHeaderIndex(selectedFlatIndex - 1);
            if (prev !== -1) {
                selectedFlatIndex = prev;
                updateSelectedItem();
            }
            return;
        }

        var viewMode = getSectionViewMode(entry.sectionId);
        if (viewMode === "list") {
            var prev = findPrevNonHeaderIndex(selectedFlatIndex - 1);
            if (prev !== -1) {
                selectedFlatIndex = prev;
                updateSelectedItem();
            }
            return;
        }

        var bounds = getSectionBounds(entry.sectionId);
        var cols = getGridColumns(entry.sectionId);
        var posInSection = selectedFlatIndex - bounds.start;
        var newPosInSection = posInSection - cols;

        if (newPosInSection >= 0) {
            selectedFlatIndex = bounds.start + newPosInSection;
            updateSelectedItem();
        } else {
            var prevItem = findPrevNonHeaderIndex(bounds.start - 1);
            if (prevItem !== -1) {
                selectedFlatIndex = prevItem;
                updateSelectedItem();
            }
        }
    }

    function selectRight() {
        keyboardNavigationActive = true;
        if (flatModel.length === 0)
            return;
        var entry = flatModel[selectedFlatIndex];
        if (!entry || entry.isHeader) {
            var next = findNextNonHeaderIndex(selectedFlatIndex + 1);
            if (next !== -1) {
                selectedFlatIndex = next;
                updateSelectedItem();
            }
            return;
        }

        var viewMode = getSectionViewMode(entry.sectionId);
        if (viewMode === "list") {
            var next = findNextNonHeaderIndex(selectedFlatIndex + 1);
            if (next !== -1) {
                selectedFlatIndex = next;
                updateSelectedItem();
            }
            return;
        }

        var bounds = getSectionBounds(entry.sectionId);
        var posInSection = selectedFlatIndex - bounds.start;
        if (posInSection + 1 < bounds.count) {
            selectedFlatIndex = bounds.start + posInSection + 1;
            updateSelectedItem();
        }
    }

    function selectLeft() {
        keyboardNavigationActive = true;
        if (flatModel.length === 0)
            return;
        var entry = flatModel[selectedFlatIndex];
        if (!entry || entry.isHeader) {
            var prev = findPrevNonHeaderIndex(selectedFlatIndex - 1);
            if (prev !== -1) {
                selectedFlatIndex = prev;
                updateSelectedItem();
            }
            return;
        }

        var viewMode = getSectionViewMode(entry.sectionId);
        if (viewMode === "list") {
            var prev = findPrevNonHeaderIndex(selectedFlatIndex - 1);
            if (prev !== -1) {
                selectedFlatIndex = prev;
                updateSelectedItem();
            }
            return;
        }

        var bounds = getSectionBounds(entry.sectionId);
        var posInSection = selectedFlatIndex - bounds.start;
        if (posInSection > 0) {
            selectedFlatIndex = bounds.start + posInSection - 1;
            updateSelectedItem();
        }
    }

    function selectNextSection() {
        keyboardNavigationActive = true;
        var currentSection = null;
        if (selectedFlatIndex >= 0 && selectedFlatIndex < flatModel.length) {
            currentSection = flatModel[selectedFlatIndex].sectionId;
        }

        var foundCurrent = false;
        for (var i = 0; i < flatModel.length; i++) {
            if (flatModel[i].isHeader) {
                if (foundCurrent) {
                    for (var j = i + 1; j < flatModel.length; j++) {
                        if (!flatModel[j].isHeader) {
                            selectedFlatIndex = j;
                            updateSelectedItem();
                            return;
                        }
                    }
                }
                if (flatModel[i].section.id === currentSection) {
                    foundCurrent = true;
                }
            }
        }
    }

    function selectPreviousSection() {
        keyboardNavigationActive = true;
        var currentSection = null;
        if (selectedFlatIndex >= 0 && selectedFlatIndex < flatModel.length) {
            currentSection = flatModel[selectedFlatIndex].sectionId;
        }

        var lastSectionStart = -1;
        var prevSectionStart = -1;

        for (var i = 0; i < flatModel.length; i++) {
            if (flatModel[i].isHeader) {
                if (flatModel[i].section.id === currentSection) {
                    break;
                }
                prevSectionStart = lastSectionStart;
                lastSectionStart = i;
            }
        }

        if (prevSectionStart >= 0) {
            for (var j = prevSectionStart + 1; j < flatModel.length; j++) {
                if (!flatModel[j].isHeader) {
                    selectedFlatIndex = j;
                    updateSelectedItem();
                    return;
                }
            }
        }
    }

    function selectPageDown(visibleItems) {
        keyboardNavigationActive = true;
        if (flatModel.length === 0)
            return;
        var itemsToSkip = visibleItems || 8;
        var newIndex = selectedFlatIndex;

        for (var i = 0; i < itemsToSkip; i++) {
            var next = findNextNonHeaderIndex(newIndex + 1);
            if (next === -1)
                break;
            newIndex = next;
        }

        if (newIndex !== selectedFlatIndex) {
            selectedFlatIndex = newIndex;
            updateSelectedItem();
        }
    }

    function selectPageUp(visibleItems) {
        keyboardNavigationActive = true;
        if (flatModel.length === 0)
            return;
        var itemsToSkip = visibleItems || 8;
        var newIndex = selectedFlatIndex;

        for (var i = 0; i < itemsToSkip; i++) {
            var prev = findPrevNonHeaderIndex(newIndex - 1);
            if (prev === -1)
                break;
            newIndex = prev;
        }

        if (newIndex !== selectedFlatIndex) {
            selectedFlatIndex = newIndex;
            updateSelectedItem();
        }
    }

    function selectIndex(index) {
        keyboardNavigationActive = false;
        if (index >= 0 && index < flatModel.length && !flatModel[index].isHeader) {
            selectedFlatIndex = index;
            updateSelectedItem();
        }
    }

    function toggleSection(sectionId) {
        var newCollapsed = Object.assign({}, collapsedSections);
        var currentState = newCollapsed[sectionId];

        if (currentState === undefined) {
            for (var i = 0; i < sections.length; i++) {
                if (sections[i].id === sectionId) {
                    currentState = sections[i].collapsed || false;
                    break;
                }
            }
        }

        newCollapsed[sectionId] = !currentState;
        collapsedSections = newCollapsed;

        var newSections = sections.slice();
        for (var i = 0; i < newSections.length; i++) {
            if (newSections[i].id === sectionId) {
                newSections[i] = Object.assign({}, newSections[i], {
                    collapsed: newCollapsed[sectionId]
                });
            }
        }
        sections = newSections;

        flatModel = Scorer.flattenSections(sections);

        if (selectedFlatIndex >= flatModel.length) {
            selectedFlatIndex = getFirstItemIndex();
        }
        updateSelectedItem();
    }

    function executeSelected() {
        if (!selectedItem)
            return;
        executeItem(selectedItem);
    }

    function executeItem(item) {
        if (!item)
            return;
        if (item.type === "plugin_browse") {
            var browsePluginId = item.data?.pluginId;
            if (!browsePluginId)
                return;
            var browseTrigger = item.data.isBuiltIn ? AppSearchService.getBuiltInPluginTrigger(browsePluginId) : PluginService.getPluginTrigger(browsePluginId);

            if (browseTrigger && browseTrigger.length > 0) {
                searchQueryRequested(browseTrigger);
            } else {
                setMode("plugins");
                pluginFilter = browsePluginId;
                performSearch();
            }
            return;
        }

        switch (item.type) {
        case "app":
            if (item.isCore) {
                AppSearchService.executeCoreApp(item.data);
            } else if (item.data?.isAction) {
                launchAppAction(item.data);
            } else {
                launchApp(item.data);
            }
            break;
        case "plugin":
            if (item.isBuiltInLauncher) {
                AppSearchService.executeBuiltInLauncherItem(item.data);
            } else {
                AppSearchService.executePluginItem(item.data, item.pluginId);
            }
            break;
        case "file":
            openFile(item.data?.path);
            break;
        case "calculator":
            copyToClipboard(item.name);
            break;
        default:
            return;
        }

        itemExecuted();
    }

    function executeAction(item, action) {
        if (!item || !action)
            return;
        switch (action.action) {
        case "launch":
            executeItem(item);
            break;
        case "open":
            openFile(item.data.path);
            break;
        case "open_folder":
            openFolder(item.data.path);
            break;
        case "copy_path":
            copyToClipboard(item.data.path);
            break;
        case "copy":
            copyToClipboard(item.name);
            break;
        case "execute":
            executeItem(item);
            break;
        case "launch_dgpu":
            if (item.type === "app" && item.data) {
                launchAppWithNvidia(item.data);
            }
            break;
        default:
            if (item.type === "app" && action.actionData) {
                launchAppAction({
                    parentApp: item.data,
                    actionData: action.actionData
                });
            }
        }

        itemExecuted();
    }

    function launchApp(app) {
        if (!app)
            return;
        SessionService.launchDesktopEntry(app);
        AppUsageHistoryData.addAppUsage(app);
    }

    function launchAppWithNvidia(app) {
        if (!app)
            return;
        SessionService.launchDesktopEntry(app, true);
        AppUsageHistoryData.addAppUsage(app);
    }

    function launchAppAction(actionItem) {
        if (!actionItem || !actionItem.parentApp || !actionItem.actionData)
            return;
        SessionService.launchDesktopAction(actionItem.parentApp, actionItem.actionData);
        AppUsageHistoryData.addAppUsage(actionItem.parentApp);
    }

    function openFile(path) {
        if (!path)
            return;
        Qt.openUrlExternally("file://" + path);
    }

    function openFolder(path) {
        if (!path)
            return;
        var folder = path.substring(0, path.lastIndexOf("/"));
        Qt.openUrlExternally("file://" + folder);
    }

    function copyToClipboard(text) {
        if (!text)
            return;
        Quickshell.execDetached(["dms", "cl", "copy", text]);
    }
}
