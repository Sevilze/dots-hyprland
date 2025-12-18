pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia

/**
 * Video wallpaper component with animated parallax support
 * Uses QtMultimedia's MediaPlayer and VideoOutput for native video rendering
 * Unlike the IPC approach, this supports smooth animated transitions
 */
Item {
    id: root
    
    // Source video file
    required property string source
    
    // Parallax positioning (0.0 to 1.0, where 0.5 is center)
    property real valueX: 0.5
    property real valueY: 0.5
    
    // Dimensions and scaling
    required property real videoWidth
    required property real videoHeight
    required property real screenWidth
    required property real screenHeight
    required property real effectiveScale
    required property real videoToScreenRatio
    
    // Calculate movable space (same logic as image parallax)
    readonly property real movableXSpace: ((videoWidth / videoToScreenRatio * effectiveScale) - screenWidth) / 2
    readonly property real movableYSpace: ((videoHeight / videoToScreenRatio * effectiveScale) - screenHeight) / 2
    
    // Effective values clamped to valid range
    readonly property real effectiveValueX: Math.max(0, Math.min(1, valueX))
    readonly property real effectiveValueY: Math.max(0, Math.min(1, valueY))
    
    // Computed position (same calculation as StyledImage parallax)
    readonly property real computedX: -(movableXSpace) - (effectiveValueX - 0.5) * 2 * movableXSpace
    readonly property real computedY: -(movableYSpace) - (effectiveValueY - 0.5) * 2 * movableYSpace
    
    // Computed size
    readonly property real computedWidth: videoWidth / videoToScreenRatio * effectiveScale
    readonly property real computedHeight: videoHeight / videoToScreenRatio * effectiveScale
    
    MediaPlayer {
        id: mediaPlayer
        source: root.source
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
            muted: true // Wallpapers should be silent
        }
        videoOutput: videoOutput
        
        Component.onCompleted: {
            play()
        }
        
        onErrorOccurred: (error, errorString) => {
            console.error("[VideoWallpaper] MediaPlayer error:", error, errorString)
        }
    }
    
    VideoOutput {
        id: videoOutput
        
        // Position with smooth animation
        x: root.computedX
        y: root.computedY
        
        // Critical: Add the missing animations from the request
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
        
        width: root.computedWidth
        height: root.computedHeight
        
        fillMode: VideoOutput.PreserveAspectCrop
    }
    
    // Debug logging
    onValueXChanged: {
        console.log("[VideoWallpaper] valueX changed:", valueX, "-> computedX:", computedX.toFixed(2))
    }
}
