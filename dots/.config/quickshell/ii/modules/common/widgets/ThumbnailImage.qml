import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Thumbnail image. It currently generates to the right place at the right size, but does not handle metadata/maintenance on modification.
 * See Freedesktop's spec: https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html
 */
StyledImage {
    id: root

    property bool generateThumbnail: true
    required property string sourcePath
    property string thumbnailSizeName: Images.thumbnailSizeNameForDimensions(sourceSize.width, sourceSize.height)
    property string thumbnailPath: {
        if (sourcePath.length == 0) return;
        const resolvedUrlWithoutFileProtocol = FileUtils.trimFileProtocol(`${Qt.resolvedUrl(sourcePath)}`);
        const encodedUrlWithoutFileProtocol = resolvedUrlWithoutFileProtocol.split("/").map(part => encodeURIComponent(part)).join("/");
        const md5Hash = Qt.md5(`file://${encodedUrlWithoutFileProtocol}`);
        return `${Directories.genericCache}/thumbnails/${thumbnailSizeName}/${md5Hash}.png`;
    }
    source: thumbnailPath

    asynchronous: true
    smooth: true
    mipmap: false

    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Debug: log when thumbnail path changes
    onThumbnailPathChanged: {
        if (sourcePath && sourcePath.length > 0) {
            const isVideo = /\.(mp4|webm|mkv|avi|mov)$/i.test(sourcePath);
            if (isVideo) {
                console.log("[ThumbnailImage] Video file:", sourcePath.substring(sourcePath.lastIndexOf('/') + 1), "=> Thumbnail:", thumbnailPath);
            }
        }
        // Trigger thumbnail generation when path changes
        if (root.generateThumbnail && thumbnailPath && thumbnailPath.length > 0) {
            thumbnailGeneration.running = false;
            thumbnailGeneration.running = true;
        }
    }
    Process {
        id: thumbnailGeneration
        command: {
            const maxSize = Images.thumbnailSizes[root.thumbnailSizeName];
            const sourcePath = root.sourcePath;
            const thumbnailPath = FileUtils.trimFileProtocol(root.thumbnailPath);
            const thumbnailDir = thumbnailPath.substring(0, thumbnailPath.lastIndexOf('/'));
            
            // Check if it's a video file
            const isVideo = /\.(mp4|webm|mkv|avi|mov)$/i.test(sourcePath);
            
            if (isVideo) {
                // Use ffmpeg for video files with timeout
                // Create directory first, then check if thumbnail exists, then generate if needed
                // -update 1 is required for single image output
                // Don't use -loglevel error as it causes silent failures in some ffmpeg versions
                return ["bash", "-c", 
                    `mkdir -p '${thumbnailDir}' && [ -f '${thumbnailPath}' ] && exit 0 || { timeout 10s ffmpeg -y -hwaccel auto -ss 1 -i '${sourcePath}' -vframes 1 -update 1 -vf 'scale=${maxSize}:${maxSize}:force_original_aspect_ratio=decrease' '${thumbnailPath}' >/dev/null 2>&1 || timeout 10s ffmpeg -y -hwaccel auto -i '${sourcePath}' -vframes 1 -update 1 -vf 'scale=${maxSize}:${maxSize}:force_original_aspect_ratio=decrease' '${thumbnailPath}' >/dev/null 2>&1; [ -f '${thumbnailPath}' ] && [ -s '${thumbnailPath}' ] && exit 1 || exit 2; }`
                ];
            } else {
                // Use magick for image files
                return ["bash", "-c", 
                    `mkdir -p '${thumbnailDir}' && [ -f '${thumbnailPath}' ] && exit 0 || { magick '${sourcePath}' -resize ${maxSize}x${maxSize} '${thumbnailPath}' && exit 1; }`
                ];
            }
        }
        onExited: (exitCode, exitStatus) => {
            const isVideo = /\.(mp4|webm|mkv|avi|mov)$/i.test(root.sourcePath);
            if (exitCode === 1) { // Force reload if thumbnail had to be generated
                if (isVideo) {
                    console.log("[ThumbnailImage] ✓ Video thumbnail generated:", root.sourcePath.substring(root.sourcePath.lastIndexOf('/') + 1));
                }
                root.source = "";
                root.source = root.thumbnailPath; // Force reload
            } else if (exitCode === 2) {
                // Thumbnail generation failed for video
                console.error("[ThumbnailImage] ✗ Failed to generate video thumbnail for:", root.sourcePath.substring(root.sourcePath.lastIndexOf('/') + 1));
            } else if (exitCode === 0 && isVideo) {
                // Thumbnail already exists
                console.log("[ThumbnailImage] ✓ Video thumbnail cached:", root.sourcePath.substring(root.sourcePath.lastIndexOf('/') + 1));
            }
        }
    }
}
