pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Common

Singleton {
    id: root

    // Filenames present on disk, so CachingImage never points an Image at a
    // missing cache file (Qt logs that as a "Cannot open" warning).
    property var cachedFiles: ({})

    Component.onCompleted: scan()

    function scan() {
        Proc.runCommand("imagecache_scan", ["ls", "-1", Paths.stringify(Paths.imagecache)], function (output, exitCode) {
            const map = {};
            if (exitCode === 0 && output) {
                const lines = output.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    const name = lines[i].trim();
                    if (name)
                        map[name] = true;
                }
            }
            root.cachedFiles = map;
        });
    }

    function hasCachedFile(name) {
        return name ? root.cachedFiles[name] === true : false;
    }

    function recordCachedFile(name) {
        if (name)
            root.cachedFiles[name] = true;
    }

    function forgetCachedFile(name) {
        if (name && root.cachedFiles[name] !== undefined)
            delete root.cachedFiles[name];
    }

    function clearImageCache() {
        Quickshell.execDetached(["rm", "-rf", Paths.stringify(Paths.imagecache)]);
        Paths.mkdir(Paths.imagecache);
        root.cachedFiles = ({});
    }

    function clearOldCache(ageInMinutes) {
        // Rescan on delete completion since we can't know which files matched.
        Proc.runCommand("imagecache_prune", ["find", Paths.stringify(Paths.imagecache), "-name", "*.png", "-mmin", `+${ageInMinutes}`, "-delete"], function (output, exitCode) {
            root.scan();
        });
    }

    function clearCacheForSize(size) {
        Quickshell.execDetached(["find", Paths.stringify(Paths.imagecache), "-name", `*@${size}x${size}.png`, "-delete"]);
        const suffix = `@${size}x${size}.png`;
        const map = {};
        for (const key in root.cachedFiles)
            if (!key.endsWith(suffix))
                map[key] = true;
        root.cachedFiles = map;
    }

    function getCacheSize(callback) {
        Proc.runCommand("cache_size", ["du", "-sm", Paths.stringify(Paths.imagecache)], function (output, exitCode) {
            const sizeMB = parseInt(output.split("\t")[0]) || 0;
            callback(sizeMB);
        });
    }
}
