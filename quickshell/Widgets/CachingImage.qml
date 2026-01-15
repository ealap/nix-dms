import QtQuick
import qs.Common

Image {
    id: root

    property string imagePath: ""
    property int maxCacheSize: 512

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

    readonly property string imageHash: imagePath ? djb2Hash(imagePath) : ""
    readonly property string cachePath: imageHash ? `${Paths.stringify(Paths.imagecache)}/${imageHash}@${maxCacheSize}x${maxCacheSize}.png` : ""
    readonly property string encodedImagePath: imagePath ? "file://" + imagePath.split('/').map(s => encodeURIComponent(s)).join('/') : ""

    asynchronous: true
    fillMode: Image.PreserveAspectCrop
    sourceSize.width: maxCacheSize
    sourceSize.height: maxCacheSize
    smooth: true

    onImagePathChanged: {
        if (!imagePath) {
            source = "";
            return;
        }
        Paths.mkdir(Paths.imagecache);
        const hash = djb2Hash(imagePath);
        const cPath = hash ? `${Paths.stringify(Paths.imagecache)}/${hash}@${maxCacheSize}x${maxCacheSize}.png` : "";
        const encoded = "file://" + imagePath.split('/').map(s => encodeURIComponent(s)).join('/');
        source = cPath || encoded;
    }

    onStatusChanged: {
        if (source == cachePath && status === Image.Error) {
            source = encodedImagePath;
            return;
        }
        if (source != encodedImagePath || status !== Image.Ready || !cachePath)
            return;
        Paths.mkdir(Paths.imagecache);
        const grabPath = cachePath;
        if (visible && width > 0 && height > 0 && Window.window?.visible) {
            grabToImage(res => res.saveToFile(grabPath));
        }
    }
}
