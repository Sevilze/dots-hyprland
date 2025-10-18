pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather

Variants {
    id: root
    model: Quickshell.screens

    PanelWindow {
        id: bgRoot

        required property var modelData

        // Hide when fullscreen
        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        visible: GlobalStates.screenLocked || (!(activeWorkspaceWithFullscreen != undefined)) || !Config?.options.background.hideWhenFullscreen

        // Workspaces
        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        property list<var> relevantWindows: HyprlandData.windowList.filter(win => win.monitor == monitor?.id && win.workspace.id >= 0).sort((a, b) => a.workspace.id - b.workspace.id)
        property int firstWorkspaceId: relevantWindows[0]?.workspace.id || 1
        property int lastWorkspaceId: relevantWindows[relevantWindows.length - 1]?.workspace.id || 10
        // Wallpaper
        property var wallpaperData: WallpaperListener.effectivePerMonitor[monitor.name] || { path: Config.options.background.wallpaperPath, workspaceFirst: 1, workspaceLast: 10 }
        property string resolvedPath: wallpaperData.path || Config.options.background.wallpaperPath
        // Only use wallpaperData workspace range if it actually exists in effectivePerMonitor, otherwise use defaults
        property bool hasPerMonitorWallpaper: WallpaperListener.effectivePerMonitor[monitor.name] !== undefined
        property int wallpaperFirstWorkspace: hasPerMonitorWallpaper ? (wallpaperData.workspaceFirst ?? 1) : 1
        property int wallpaperLastWorkspace: hasPerMonitorWallpaper ? (wallpaperData.workspaceLast ?? 10) : 10
        property var wallpaperData: WallpaperListener.effectivePerMonitor[monitor.name] || { path: Config.options.background.wallpaperPath, workspaceFirst: 1, workspaceLast: 10 }
        property string resolvedPath: wallpaperData.path || Config.options.background.wallpaperPath
        property int wallpaperFirstWorkspace: wallpaperData.workspaceFirst || 1
        property int wallpaperLastWorkspace: wallpaperData.workspaceLast || 10
        property bool wallpaperIsVideo: resolvedPath.endsWith(".mp4") || resolvedPath.endsWith(".webm") || resolvedPath.endsWith(".mkv") || resolvedPath.endsWith(".avi") || resolvedPath.endsWith(".mov")
        // Get per-monitor thumbnail if available, otherwise use global thumbnail
        property string thumbnailPath: {
            if (!wallpaperIsVideo) return resolvedPath;
            const thumbnailsByMonitor = Config.options.background?.thumbnailsByMonitor || [];
            for (let i = 0; i < thumbnailsByMonitor.length; i++) {
                if (thumbnailsByMonitor[i].monitor === monitor.name) {
                    return thumbnailsByMonitor[i].path;
                }
            }
            // For videos, NEVER fall back to the video file itself
            // Return the global thumbnail path if set, otherwise empty string
            // This prevents magick from trying to process video files
            return Config.options.background.thumbnailPath || "";
        }
        property string wallpaperPath: wallpaperIsVideo ? thumbnailPath : resolvedPath
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }
        property real wallpaperToScreenRatio: Math.min(wallpaperWidth / screen.width, wallpaperHeight / screen.height)
        property real preferredWallpaperScale: Config.options.background.parallax.workspaceZoom
        property real effectiveWallpaperScale: 1 // Some reasonable init value, to be updated
        property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
        property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated
        property real movableXSpace: ((wallpaperWidth / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.width) / 2
        property real movableYSpace: ((wallpaperHeight / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.height) / 2
        readonly property bool verticalParallax: (Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth) || Config.options.background.parallax.vertical
        // Colors
        property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        property color dominantColor: Appearance.colors.colPrimary // Default, to be changed
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Layer props
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Overlay : WlrLayer.Bottom
        // WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: {
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        onWallpaperPathChanged: {
            bgRoot.updateZoomScale();
            // Clock position gets updated after zoom scale is updated
        }

        // Wallpaper zoom scale
        function updateZoomScale() {
            // Don't run if wallpaperPath is empty (video thumbnail not ready yet)
            if (!bgRoot.wallpaperPath || bgRoot.wallpaperPath.length === 0) {
                console.log("[Background] Waiting for video thumbnail to be created...");
                return;
            }
            // Use thumbnail path for videos to avoid spawning persistent ffmpeg
            getWallpaperSizeProc.path = bgRoot.wallpaperPath; // wallpaperPath already handles video vs image
            getWallpaperSizeProc.running = true;
        }
        Process {
            id: getWallpaperSizeProc
            property string path: bgRoot.wallpaperPath // wallpaperPath already handles video vs image
            command: ["magick", "identify", "-format", "%w %h", path]
            stdout: StdioCollector {
                id: wallpaperSizeOutputCollector
                onStreamFinished: {
                    const output = wallpaperSizeOutputCollector.text;
                    const [width, height] = output.split(" ").map(Number);
                    const [screenWidth, screenHeight] = [bgRoot.screen.width, bgRoot.screen.height];
                    bgRoot.wallpaperWidth = width;
                    bgRoot.wallpaperHeight = height;

                    if (width <= screenWidth || height <= screenHeight) {
                        // Undersized/perfectly sized wallpapers
                        bgRoot.effectiveWallpaperScale = Math.max(screenWidth / width, screenHeight / height);
                    } else {
                        // Oversized = can be zoomed for parallax, yay
                        bgRoot.effectiveWallpaperScale = Math.min(bgRoot.preferredWallpaperScale, width / screenWidth, height / screenHeight);
                    }
                }
            }
        }

        // Clock positioning
        function updateClockPosition() {
            // Don't run if wallpaperPath is empty (video thumbnail not ready yet)
            if (!bgRoot.wallpaperPath || bgRoot.wallpaperPath.length === 0) {
                // Set default center position for videos without thumbnails yet
                bgRoot.clockX = bgRoot.screen.width / 2;
                bgRoot.clockY = bgRoot.screen.height / 2;
                return;
            }
            // Somehow all this manual setting is needed to make the proc correctly use the new values
            // Use thumbnail path for videos to avoid spawning persistent ffmpeg
            leastBusyRegionProc.path = bgRoot.wallpaperPath; // wallpaperPath already handles video vs image
            leastBusyRegionProc.contentWidth = clockLoader.implicitWidth + root.clockSizePadding * 2;
            leastBusyRegionProc.contentHeight = clockLoader.implicitHeight + root.clockSizePadding * 2;
            leastBusyRegionProc.horizontalPadding = bgRoot.movableXSpace + root.screenSizePadding * 2;
            leastBusyRegionProc.verticalPadding = bgRoot.movableYSpace + root.screenSizePadding * 2;
            leastBusyRegionProc.running = false;
            leastBusyRegionProc.running = true;
        }
        Process {
            id: leastBusyRegionProc
            property string path: bgRoot.wallpaperPath
            property int contentWidth: 300
            property int contentHeight: 300
            property int horizontalPadding: bgRoot.movableXSpace
            property int verticalPadding: bgRoot.movableYSpace
            command: [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh"), "--screen-width", Math.round(bgRoot.screen.width / bgRoot.effectiveWallpaperScale), "--screen-height", Math.round(bgRoot.screen.height / bgRoot.effectiveWallpaperScale), "--width", contentWidth, "--height", contentHeight, "--horizontal-padding", horizontalPadding, "--vertical-padding", verticalPadding, path
                // "--visual-output",
                ,]
            stdout: StdioCollector {
                id: leastBusyRegionOutputCollector
                onStreamFinished: {
                    const output = leastBusyRegionOutputCollector.text;
                    // console.log("[Background] Least busy region output:", output)
                    if (output.length === 0)
                        return;
                    const parsedContent = JSON.parse(output);
                    bgRoot.clockX = parsedContent.center_x * bgRoot.effectiveWallpaperScale;
                    bgRoot.clockY = parsedContent.center_y * bgRoot.effectiveWallpaperScale;
                    bgRoot.dominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                }
            }
        }

        // Wallpaper
        Item {
            anchors.fill: parent
            clip: true

            // Wallpaper
            StyledImage {
                id: wallpaper
                visible: opacity > 0 && !blurLoader.active
                opacity: (status === Image.Ready && !bgRoot.wallpaperIsVideo) ? 1 : 0
                cache: false
                smooth: false
                // Use per-monitor workspace range if multiMonitor is enabled, otherwise use dynamic global range
                property bool usePerMonitorRange: WallpaperListener.multiMonitorEnabled &&
                    (wallpaperData.workspaceFirst !== undefined && wallpaperData.workspaceLast !== undefined)
                property int chunkSize: usePerMonitorRange ? bgRoot.wallpaperLastWorkspace - bgRoot.wallpaperFirstWorkspace + 1 : 
                    Config?.options.bar.workspaces.shown ?? 10
                property int lower: usePerMonitorRange ?
                    Math.floor(bgRoot.wallpaperFirstWorkspace / chunkSize) * chunkSize :
                    Math.floor(bgRoot.firstWorkspaceId / chunkSize) * chunkSize
                property int upper: usePerMonitorRange ?
                    Math.ceil(bgRoot.wallpaperLastWorkspace / chunkSize) * chunkSize :
                    Math.ceil(bgRoot.lastWorkspaceId / chunkSize) * chunkSize
                property int range: upper - lower
                property real valueX: {
                    let result = 0.5;
                    if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) {
                        result = range > 0 ? ((bgRoot.monitor.activeWorkspace?.id - lower) / range) : 0.5;
                    }
                    if (Config.options.background.parallax.enableSidebar) {
                        result += (0.15 * GlobalStates.sidebarRightOpen - 0.15 * GlobalStates.sidebarLeftOpen);
                    }
                    return result;
                }
                property real valueY: {
                    let result = 0.5;
                    if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) {
                        result = range > 0 ? ((bgRoot.monitor.activeWorkspace?.id - lower) / range) : 0.5;
                    }
                    return result;
                }

                onValueXChanged: {
                    console.log("[Background] Wallpaper valueX changed:", valueX, "workspace:", bgRoot.monitor.activeWorkspace?.id, "range:", lower, "-", upper)
                }
                property real effectiveValueX: Math.max(0, Math.min(1, valueX))
                property real effectiveValueY: Math.max(0, Math.min(1, valueY))
                x: -(bgRoot.movableXSpace) - (effectiveValueX - 0.5) * 2 * bgRoot.movableXSpace
                y: -(bgRoot.movableYSpace) - (effectiveValueY - 0.5) * 2 * bgRoot.movableYSpace
                source: bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
                fillMode: Image.PreserveAspectCrop
                Behavior on x {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                sourceSize {
                    width: bgRoot.screen.width * bgRoot.effectiveWallpaperScale * bgRoot.monitor.scale
                    height: bgRoot.screen.height * bgRoot.effectiveWallpaperScale * bgRoot.monitor.scale
                }
                width: bgRoot.wallpaperWidth / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
                height: bgRoot.wallpaperHeight / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
            }

            // Video wallpaper with animated parallax (QtMultimedia approach)
            Loader {
                id: videoWallpaperLoader
                active: bgRoot.wallpaperIsVideo && bgRoot.visible
                anchors.fill: parent
                
                sourceComponent: VideoWallpaper {
                    // Source
                    source: bgRoot.resolvedPath
                    
                    // Dimensions
                    videoWidth: bgRoot.wallpaperWidth
                    videoHeight: bgRoot.wallpaperHeight
                    screenWidth: bgRoot.screen.width
                    screenHeight: bgRoot.screen.height
                    effectiveScale: bgRoot.effectiveWallpaperScale
                    videoToScreenRatio: bgRoot.wallpaperToScreenRatio
                    
                    // Parallax values (same calculation as image parallax)
                    // Use per-monitor workspace range if multiMonitor is enabled, otherwise use dynamic global range
                    property bool usePerMonitorRange: WallpaperListener.multiMonitorEnabled &&
                        (wallpaperData.workspaceFirst !== undefined && wallpaperData.workspaceLast !== undefined)
                    property int chunkSize: usePerMonitorRange ? bgRoot.wallpaperLastWorkspace - bgRoot.wallpaperFirstWorkspace + 1 : 
                        Config?.options.bar.workspaces.shown ?? 10
                    // Use wallpaper's configured workspace range when in per-monitor mode, otherwise use dynamic range
                    property int lower: usePerMonitorRange ?
                        bgRoot.wallpaperFirstWorkspace :
                        Math.floor(bgRoot.firstWorkspaceId / chunkSize) * chunkSize
                    property int upper: usePerMonitorRange ?
                        bgRoot.wallpaperLastWorkspace :
                        Math.ceil(bgRoot.lastWorkspaceId / chunkSize) * chunkSize
                    property int range: upper - lower
                    
                    valueX: {
                        let result = 0.5;
                        if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) {
                            result = range > 0 ? ((bgRoot.monitor.activeWorkspace?.id - lower) / range) : 0.5;
                        }
                        if (Config.options.background.parallax.enableSidebar) {
                            result += (0.15 * GlobalStates.sidebarRightOpen - 0.15 * GlobalStates.sidebarLeftOpen);
                        }
                        return result;
                    }
                    
                    valueY: {
                        let result = 0.5;
                        if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) {
                            result = range > 0 ? ((bgRoot.monitor.activeWorkspace?.id - lower) / range) : 0.5;
                        }
                        return result;
                    }
                }
            }

            Loader {
                id: blurLoader
                active: Config.options.lock.blur.enable && (GlobalStates.screenLocked || scaleAnim.running)
                anchors.fill: wallpaper
                scale: GlobalStates.screenLocked ? Config.options.lock.blur.extraZoom : 1
                Behavior on scale {
                    NumberAnimation {
                        id: scaleAnim
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
                sourceComponent: GaussianBlur {
                    source: wallpaper
                    radius: GlobalStates.screenLocked ? Config.options.lock.blur.radius : 0
                    samples: radius * 2 + 1

                    Rectangle {
                        opacity: GlobalStates.screenLocked ? 1 : 0
                        anchors.fill: parent
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                    }
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                anchors {
                    left: wallpaper.left
                    right: wallpaper.right
                    top: wallpaper.top
                    bottom: wallpaper.bottom
                    horizontalCenter: undefined
                    verticalCenter: undefined
                    readonly property real parallaxFactor: Config.options.background.parallax.widgetsFactor
                    leftMargin: {
                        const xOnWallpaper = bgRoot.movableXSpace;
                        const extraMove = (wallpaper.effectiveValueX * 2 * bgRoot.movableXSpace) * (parallaxFactor - 1);
                        return xOnWallpaper - extraMove;
                    }
                    topMargin: {
                        const yOnWallpaper = bgRoot.movableYSpace;
                        const extraMove = (wallpaper.effectiveValueY * 2 * bgRoot.movableYSpace) * (parallaxFactor - 1);
                        return yOnWallpaper - extraMove;
                    }
                    Behavior on leftMargin {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on topMargin {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
                width: wallpaper.width
                height: wallpaper.height
                states: State {
                    name: "centered"
                    when: GlobalStates.screenLocked || bgRoot.wallpaperSafetyTriggered
                    PropertyChanges {
                        target: widgetCanvas
                        width: parent.width
                        height: parent.height
                    }
                    AnchorChanges {
                        target: widgetCanvas
                        anchors {
                            left: undefined
                            right: undefined
                            top: undefined
                            bottom: undefined
                            horizontalCenter: parent.horizontalCenter
                            verticalCenter: parent.verticalCenter
                        }
                    }
                }
                transitions: Transition {
                    PropertyAnimation {
                        properties: "width,height"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                    AnchorAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable
                    sourceComponent: WeatherWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                        wallpaperScale: bgRoot.effectiveWallpaperScale
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.clock.enable
                    sourceComponent: ClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                        wallpaperScale: bgRoot.effectiveWallpaperScale
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    }
                }
            }
        }
    }
}
