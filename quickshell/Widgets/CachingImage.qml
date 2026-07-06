import QtQuick
import qs.Common

Item {
    id: root

    property string imagePath: ""
    property int maxCacheSize: 512
    property int status: isAnimated ? animatedImg.status : staticImg.status
    property int fillMode: Image.PreserveAspectCrop
    property bool _fromCache: false

    readonly property bool isRemoteUrl: imagePath.startsWith("http://") || imagePath.startsWith("https://")
    readonly property bool isAnimated: {
        if (!imagePath)
            return false;
        const lower = imagePath.toLowerCase();
        return lower.endsWith(".gif") || lower.endsWith(".webp");
    }
    readonly property string normalizedPath: {
        if (!imagePath)
            return "";
        if (isRemoteUrl)
            return imagePath;
        if (imagePath.startsWith("file://"))
            return imagePath.substring(7);
        return imagePath;
    }

    function djb2Hash(str) {
        if (!str)
            return "";
        let hash = 5381;
        for (let i = 0; i < str.length; i++) {
            hash = ((hash << 5) + hash) + str.charCodeAt(i);
            hash = hash & 0x7FFFFFFF;
        }
        return hash.toString(16).padStart(8, '0');
    }

    readonly property string imageHash: normalizedPath ? djb2Hash(normalizedPath) : ""
    readonly property string cacheFileName: imageHash && !isRemoteUrl && !isAnimated ? `${imageHash}@${maxCacheSize}x${maxCacheSize}.png` : ""
    readonly property string cachePath: cacheFileName ? `${Paths.stringify(Paths.imagecache)}/${cacheFileName}` : ""
    readonly property string encodedImagePath: {
        if (!normalizedPath)
            return "";
        if (isRemoteUrl)
            return normalizedPath;
        return "file://" + normalizedPath.split('/').map(s => encodeURIComponent(s)).join('/');
    }

    AnimatedImage {
        id: animatedImg
        anchors.fill: parent
        visible: root.isAnimated
        asynchronous: true
        fillMode: root.fillMode
        source: root.isAnimated ? root.imagePath : ""
        playing: visible && status === AnimatedImage.Ready
    }

    Image {
        id: staticImg
        anchors.fill: parent
        visible: !root.isAnimated
        asynchronous: true
        fillMode: root.fillMode
        sourceSize.width: root.maxCacheSize
        sourceSize.height: root.maxCacheSize
        smooth: true

        onStatusChanged: {
            switch (status) {
            case Image.Error:
                if (!root._fromCache)
                    return;
                root._fromCache = false;
                CacheUtils.forgetCachedFile(root.cacheFileName);
                source = root.encodedImagePath;
                return;
            case Image.Ready:
                if (root._fromCache || root.isRemoteUrl || !root.cachePath)
                    return;
                if (!visible || width <= 0 || height <= 0 || !Window.window?.visible)
                    return;
                Paths.mkdir(Paths.imagecache);
                const grabPath = root.cachePath;
                const grabName = root.cacheFileName;
                grabToImage(res => {
                    if (res.saveToFile(grabPath))
                        CacheUtils.recordCachedFile(grabName);
                });
                return;
            }
        }
    }

    onImagePathChanged: {
        if (!imagePath) {
            _fromCache = false;
            staticImg.source = "";
            return;
        }
        if (isAnimated)
            return;
        if (isRemoteUrl) {
            _fromCache = false;
            staticImg.source = imagePath;
            return;
        }
        if (!cachePath) {
            _fromCache = false;
            staticImg.source = encodedImagePath;
            return;
        }
        Paths.mkdir(Paths.imagecache);
        // Read cache only when present; else load source and cache it on Ready
        if (CacheUtils.hasCachedFile(cacheFileName)) {
            _fromCache = true;
            staticImg.source = cachePath;
        } else {
            _fromCache = false;
            staticImg.source = encodedImagePath;
        }
    }
}
