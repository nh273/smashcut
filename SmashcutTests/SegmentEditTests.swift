import AVFoundation
import CoreImage
import Foundation
import Testing
@testable import Smashcut

struct SegmentEditTests {

    // MARK: - SegmentEditViewModel Layer Management

    @Test func selectLayerClearsTextSelection() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        let textID = segment.textLayers.first!.id
        vm.selectTextLayer(textID)
        #expect(vm.selectedTextLayerID == textID)
        #expect(vm.selectedLayerID == nil)

        let layerID = segment.layers.first!.id
        vm.selectLayer(layerID)
        #expect(vm.selectedLayerID == layerID)
        #expect(vm.selectedTextLayerID == nil)
    }

    @Test func clearSelectionClearsBoth() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        vm.selectLayer(segment.layers[0].id)
        vm.clearSelection()
        #expect(vm.selectedLayerID == nil)
        #expect(vm.selectedTextLayerID == nil)
    }

    @Test func setFilterUpdatesLayer() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        let id = segment.layers[0].id
        vm.setFilter(layerID: id, filter: .vivid)
        #expect(vm.segment.layers[0].filter == .vivid)
    }

    @Test func setVolumeClampsRange() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        let id = segment.layers[0].id
        vm.setVolume(layerID: id, volume: 1.5)
        #expect(vm.segment.layers[0].volume == 1.0)
        vm.setVolume(layerID: id, volume: -0.5)
        #expect(vm.segment.layers[0].volume == 0.0)
    }

    @Test func setBorderAndCornerRadius() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        let id = segment.layers[0].id
        vm.setBorderWidth(layerID: id, width: 5)
        vm.setCornerRadius(layerID: id, radius: 12)
        #expect(vm.segment.layers[0].borderWidth == 5)
        #expect(vm.segment.layers[0].cornerRadius == 12)
    }

    @Test func setLayerTrimUpdatesValues() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        let id = segment.layers[0].id
        vm.setLayerTrim(layerID: id, start: 1.0, end: 3.0)
        #expect(vm.segment.layers[0].trimStartSeconds == 1.0)
        #expect(vm.segment.layers[0].trimEndSeconds == 3.0)
    }

    @Test func addTextLayerAppendsAndSelects() {
        let segment = makeSegment(textLayers: [])
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        #expect(vm.segment.textLayers.isEmpty)
        vm.addTextLayer()
        #expect(vm.segment.textLayers.count == 1)
        #expect(vm.selectedTextLayerID == vm.segment.textLayers[0].id)
        #expect(vm.selectedLayerID == nil)
    }

    @Test func deleteTextLayerRemovesAndClearsSelection() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        let textID = segment.textLayers[0].id
        vm.selectTextLayer(textID)
        vm.deleteTextLayer(id: textID)
        #expect(vm.segment.textLayers.isEmpty)
        #expect(vm.selectedTextLayerID == nil)
    }

    @Test func setTextLayerProperties() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        let id = segment.textLayers[0].id

        vm.setTextLayerText(id: id, text: "Updated")
        #expect(vm.segment.textLayers[0].text == "Updated")

        vm.setTextLayerFontSize(id: id, size: 48)
        #expect(vm.segment.textLayers[0].style.fontSize == 48)

        vm.setTextLayerContrastMode(id: id, mode: .stroke)
        #expect(vm.segment.textLayers[0].style.contrastMode == .stroke)
    }

    @Test func moveLayerUpdatesZIndices() {
        var segment = makeSegment()
        let layer2 = Layer(type: .photo, position: NormalizedRect(x: 0, y: 0, width: 1, height: 1), zIndex: 0)
        segment.layers.append(layer2)
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)

        // layers[0] is video (zIndex=1), layers[1] is photo (zIndex=0)
        vm.moveLayer(from: IndexSet(integer: 1), to: 0)
        // After move, photo should be first with higher z
        #expect(vm.segment.layers[0].type == .photo)
        #expect(vm.segment.layers[0].zIndex > vm.segment.layers[1].zIndex)
    }

    @Test func gridSnappingToThirds() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        vm.showGrid = true
        let id = segment.layers[0].id
        // Position near 1/3 should snap
        vm.updateLayerPosition(layerID: id, position: NormalizedRect(x: 0.34, y: 0.34, width: 0.3, height: 0.3))
        let pos = vm.segment.layers[0].position
        #expect(abs(pos.x - 1.0 / 3.0) < 0.001)
        #expect(abs(pos.y - 1.0 / 3.0) < 0.001)
    }

    @Test func gridSnappingDisabled() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        vm.showGrid = false
        let id = segment.layers[0].id
        vm.updateLayerPosition(layerID: id, position: NormalizedRect(x: 0.34, y: 0.34, width: 0.3, height: 0.3))
        let pos = vm.segment.layers[0].position
        #expect(abs(pos.x - 0.34) < 0.001)
    }

    // MARK: - TimelineViewModel

    @Test func timelineSegmentStartTimeCalculation() {
        var timeline = ProjectTimeline()
        timeline.segments = [
            makeTimelineSegment(scriptText: "A", duration: 3.0),
            makeTimelineSegment(scriptText: "B", duration: 5.0),
            makeTimelineSegment(scriptText: "C", duration: 2.0),
        ]
        var project = Project(title: "Test", rawIdea: "")
        project.timeline = timeline
        let vm = TimelineViewModel(project: project)

        #expect(vm.segmentStartTime(at: 0) == 0)
        #expect(vm.segmentStartTime(at: 1) == 3.0)
        #expect(vm.segmentStartTime(at: 2) == 8.0)
        #expect(vm.totalDuration == 10.0)
    }

    @Test func timelineSegmentIndexAtTime() {
        var timeline = ProjectTimeline()
        timeline.segments = [
            makeTimelineSegment(scriptText: "A", duration: 3.0),
            makeTimelineSegment(scriptText: "B", duration: 5.0),
        ]
        var project = Project(title: "Test", rawIdea: "")
        project.timeline = timeline
        let vm = TimelineViewModel(project: project)

        #expect(vm.segmentIndex(at: 1.0) == 0)
        #expect(vm.segmentIndex(at: 3.5) == 1)
        #expect(vm.segmentIndex(at: 10.0) == 1) // past end → last
    }

    @Test func selectSegmentUpdatesState() {
        var timeline = ProjectTimeline()
        timeline.segments = [
            makeTimelineSegment(scriptText: "A", duration: 3.0),
            makeTimelineSegment(scriptText: "B", duration: 5.0),
        ]
        var project = Project(title: "Test", rawIdea: "")
        project.timeline = timeline
        let vm = TimelineViewModel(project: project)

        vm.selectSegment(at: 1)
        #expect(vm.currentSegmentIndex == 1)
        #expect(vm.selectedSegmentID == timeline.segments[1].id)
    }

    // MARK: - LiveCompositorInstruction

    @Test func instructionStoresVideoLayerInfo() {
        let info = LiveCompositorInstruction.VideoLayerInfo(
            trackID: 1,
            position: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5),
            filter: .vivid,
            hasBackgroundRemoval: true,
            zIndex: 3,
            borderWidth: 2.0,
            cornerRadius: 8.0
        )

        let instruction = LiveCompositorInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 5, preferredTimescale: 600)),
            videoLayers: [info],
            photoLayers: [],
            textLayers: [],
            outputSize: CGSize(width: 1080, height: 1920)
        )

        #expect(instruction.videoLayers.count == 1)
        #expect(instruction.videoLayers[0].trackID == 1)
        #expect(instruction.videoLayers[0].filter == .vivid)
        #expect(instruction.videoLayers[0].hasBackgroundRemoval == true)
        #expect(instruction.videoLayers[0].zIndex == 3)
        #expect(instruction.videoLayers[0].borderWidth == 2.0)
        #expect(instruction.videoLayers[0].cornerRadius == 8.0)
        #expect(instruction.outputSize == CGSize(width: 1080, height: 1920))
    }

    @Test func instructionRequiredTrackIDsMatchesVideoLayers() {
        let v1 = LiveCompositorInstruction.VideoLayerInfo(
            trackID: 1, position: .fullFrame, filter: .none,
            hasBackgroundRemoval: false, zIndex: 0, borderWidth: 0, cornerRadius: 0
        )
        let v2 = LiveCompositorInstruction.VideoLayerInfo(
            trackID: 2, position: .fullFrame, filter: .noir,
            hasBackgroundRemoval: false, zIndex: 1, borderWidth: 0, cornerRadius: 0
        )

        let instruction = LiveCompositorInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 5, preferredTimescale: 600)),
            videoLayers: [v1, v2],
            photoLayers: [],
            textLayers: [],
            outputSize: CGSize(width: 1080, height: 1920)
        )

        let trackIDs = instruction.requiredSourceTrackIDs?.compactMap { ($0 as? NSNumber)?.int32Value }
        #expect(trackIDs == [1, 2])
    }

    @Test func instructionWithNoVideoLayersHasEmptyTrackIDs() {
        let instruction = LiveCompositorInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 600)),
            videoLayers: [],
            photoLayers: [],
            textLayers: [],
            outputSize: CGSize(width: 1080, height: 1920)
        )

        #expect(instruction.requiredSourceTrackIDs?.isEmpty == true)
        #expect(instruction.passthroughTrackID == kCMPersistentTrackID_Invalid)
    }

    @Test func instructionStoresPhotoLayerInfo() {
        let testImage = CIImage(color: CIColor.red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let photo = LiveCompositorInstruction.PhotoLayerInfo(
            image: testImage,
            position: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            filter: .fade,
            zIndex: 2,
            borderWidth: 1.0,
            cornerRadius: 4.0
        )

        let instruction = LiveCompositorInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 5, preferredTimescale: 600)),
            videoLayers: [],
            photoLayers: [photo],
            textLayers: [],
            outputSize: CGSize(width: 1080, height: 1920)
        )

        #expect(instruction.photoLayers.count == 1)
        #expect(instruction.photoLayers[0].filter == .fade)
        #expect(instruction.photoLayers[0].zIndex == 2)
        #expect(instruction.photoLayers[0].position.x == 0.25)
    }

    @Test func instructionStoresTextLayerInfo() {
        let baseLayer = Layer(
            type: .text,
            position: NormalizedRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1),
            zIndex: 10
        )
        let textLayer = TextLayer(layer: baseLayer, text: "Caption", startSeconds: 1.0, endSeconds: 4.0)
        let info = LiveCompositorInstruction.TextLayerInfo(textLayer: textLayer)

        let instruction = LiveCompositorInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 5, preferredTimescale: 600)),
            videoLayers: [],
            photoLayers: [],
            textLayers: [info],
            outputSize: CGSize(width: 1080, height: 1920)
        )

        #expect(instruction.textLayers.count == 1)
        #expect(instruction.textLayers[0].textLayer.text == "Caption")
        #expect(instruction.textLayers[0].textLayer.startSeconds == 1.0)
        #expect(instruction.textLayers[0].textLayer.endSeconds == 4.0)
    }

    @Test func instructionMixedLayerTypes() {
        let video = LiveCompositorInstruction.VideoLayerInfo(
            trackID: 1, position: .fullFrame, filter: .none,
            hasBackgroundRemoval: false, zIndex: 0, borderWidth: 0, cornerRadius: 0
        )
        let photo = LiveCompositorInstruction.PhotoLayerInfo(
            image: CIImage(color: CIColor.blue).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50)),
            position: NormalizedRect(x: 0, y: 0, width: 0.3, height: 0.3),
            filter: .none, zIndex: 1, borderWidth: 0, cornerRadius: 0
        )
        let text = LiveCompositorInstruction.TextLayerInfo(
            textLayer: TextLayer(
                layer: Layer(type: .text, position: NormalizedRect(x: 0, y: 0.9, width: 1, height: 0.1), zIndex: 10),
                text: "Overlay",
                startSeconds: 0,
                endSeconds: 5
            )
        )

        let instruction = LiveCompositorInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 5, preferredTimescale: 600)),
            videoLayers: [video],
            photoLayers: [photo],
            textLayers: [text],
            outputSize: CGSize(width: 1080, height: 1920)
        )

        #expect(instruction.videoLayers.count == 1)
        #expect(instruction.photoLayers.count == 1)
        #expect(instruction.textLayers.count == 1)
        #expect(instruction.enablePostProcessing == false)
        #expect(instruction.containsTweening == true)
    }

    // MARK: - LiveCompositor Instance

    @Test func compositorPixelFormatRequirements() {
        let compositor = LiveCompositor()
        let sourceFormat = compositor.sourcePixelBufferAttributes?[kCVPixelBufferPixelFormatTypeKey as String] as? OSType
        let renderFormat = compositor.requiredPixelBufferAttributesForRenderContext[kCVPixelBufferPixelFormatTypeKey as String] as? OSType
        #expect(sourceFormat == kCVPixelFormatType_32BGRA)
        #expect(renderFormat == kCVPixelFormatType_32BGRA)
    }

    // MARK: - Layer Model Compositor Properties

    @Test func layerNeedsCachingOnlyForBgRemovalVideo() {
        let videoWithBgRemoval = Layer(type: .video, hasBackgroundRemoval: true)
        let videoNoBgRemoval = Layer(type: .video, hasBackgroundRemoval: false)
        let photoWithBgRemoval = Layer(type: .photo, hasBackgroundRemoval: true)

        #expect(videoWithBgRemoval.needsCaching == true)
        #expect(videoNoBgRemoval.needsCaching == false)
        #expect(photoWithBgRemoval.needsCaching == false)
    }

    @Test func layerCacheInvalidation() {
        var layer = Layer(type: .video, hasBackgroundRemoval: true, cacheState: .ready)
        layer.cachedProcessedURL = URL(fileURLWithPath: "/tmp/cached.mp4")

        layer.invalidateCache()
        #expect(layer.cacheState == .stale)
        #expect(layer.cachedProcessedURL == nil)
    }

    @Test func layerCacheInvalidationNoopWhenNone() {
        var layer = Layer(type: .video)
        #expect(layer.cacheState == .none)
        layer.invalidateCache()
        #expect(layer.cacheState == .none) // Does not change from .none
    }

    @Test func filterPresetsAreDistinct() {
        let presets: [FilterPreset] = [.none, .vivid, .matte, .noir, .fade]
        let set = Set(presets.map(\.rawValue))
        #expect(set.count == 5)
    }

    // MARK: - SegmentEditViewModel Compositor Integration

    @Test func toggleBackgroundRemovalFlipsFlag() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        let id = segment.layers[0].id

        #expect(vm.segment.layers[0].hasBackgroundRemoval == false)
        vm.toggleBackgroundRemoval(layerID: id)
        #expect(vm.segment.layers[0].hasBackgroundRemoval == true)
        vm.toggleBackgroundRemoval(layerID: id)
        #expect(vm.segment.layers[0].hasBackgroundRemoval == false)
    }

    @Test func toggleBackgroundRemovalClearsCacheOnDisable() {
        var segment = makeSegment()
        segment.layers[0].hasBackgroundRemoval = true
        segment.layers[0].cacheState = .ready
        segment.layers[0].cachedProcessedURL = URL(fileURLWithPath: "/tmp/cached.mp4")
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        let id = segment.layers[0].id

        // Toggle off → should clear cache state
        vm.toggleBackgroundRemoval(layerID: id)
        #expect(vm.segment.layers[0].hasBackgroundRemoval == false)
        #expect(vm.segment.layers[0].cacheState == .none)
        #expect(vm.segment.layers[0].cachedProcessedURL == nil)
    }

    @Test func setFilterCyclesThroughPresets() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        let id = segment.layers[0].id

        for preset in [FilterPreset.vivid, .matte, .noir, .fade, .none] {
            vm.setFilter(layerID: id, filter: preset)
            #expect(vm.segment.layers[0].filter == preset)
        }
    }

    @Test func borderWidthClampsToNonNegative() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        let id = segment.layers[0].id
        vm.setBorderWidth(layerID: id, width: -5)
        #expect(vm.segment.layers[0].borderWidth == 0)
    }

    @Test func cornerRadiusClampsToNonNegative() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        let id = segment.layers[0].id
        vm.setCornerRadius(layerID: id, radius: -10)
        #expect(vm.segment.layers[0].cornerRadius == 0)
    }

    @Test func textLayerFontSizeClamps() {
        let segment = makeSegment()
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)
        let id = segment.textLayers[0].id

        vm.setTextLayerFontSize(id: id, size: 5) // below min 12
        #expect(vm.segment.textLayers[0].style.fontSize == 12)

        vm.setTextLayerFontSize(id: id, size: 200) // above max 120
        #expect(vm.segment.textLayers[0].style.fontSize == 120)
    }

    @Test func moveTextLayerUpdatesZIndices() {
        var segment = makeSegment()
        let baseLayer2 = Layer(
            type: .text,
            position: NormalizedRect(x: 0.1, y: 0.5, width: 0.8, height: 0.15),
            zIndex: 11
        )
        segment.textLayers.append(TextLayer(layer: baseLayer2, text: "Second", startSeconds: 0, endSeconds: 5))
        let vm = SegmentEditViewModel(segment: segment, segmentIndex: 0)

        vm.moveTextLayer(from: IndexSet(integer: 1), to: 0)
        #expect(vm.segment.textLayers[0].text == "Second")
        // Text layers z-indices should be 10+ range and ordered
        #expect(vm.segment.textLayers[0].layer.zIndex > vm.segment.textLayers[1].layer.zIndex)
    }

    // MARK: - NormalizedRect

    @Test func normalizedRectFullFrame() {
        let full = NormalizedRect.fullFrame
        #expect(full.x == 0)
        #expect(full.y == 0)
        #expect(full.width == 1)
        #expect(full.height == 1)
    }

    // MARK: - Helpers

    private func makeSegment(textLayers: [TextLayer]? = nil) -> TimelineSegment {
        let layer = Layer(
            type: .video,
            position: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            zIndex: 1
        )
        var segment = TimelineSegment(scriptText: "Test segment")
        segment.duration = 5.0
        segment.layers = [layer]
        if let textLayers {
            segment.textLayers = textLayers
        } else {
            let baseLayer = Layer(
                type: .text,
                position: NormalizedRect(x: 0.1, y: 0.7, width: 0.8, height: 0.15),
                zIndex: 10
            )
            segment.textLayers = [TextLayer(layer: baseLayer, text: "Hello", startSeconds: 0, endSeconds: 5)]
        }
        return segment
    }

    private func makeTimelineSegment(scriptText: String, duration: Double) -> TimelineSegment {
        var segment = TimelineSegment(scriptText: scriptText)
        segment.duration = duration
        return segment
    }
}
