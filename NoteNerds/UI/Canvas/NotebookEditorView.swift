import SwiftUI
import UniformTypeIdentifiers
struct NotebookEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var isReduceMotionEnabled
    let notebook: Notebook
    @State var canvasIndex = 0
    @State var selectedLayerIDs: [CanvasID: LayerID] = [:]
    @State var palette = ToolPaletteState()
    @State var favoriteOne = ToolConfiguration.favoriteOne
    @State var favoriteTwo = ToolConfiguration.favoriteTwo
    @State private var isRadialMenuVisible = false
    @State private var radialMenuOrigin: CGPoint?
    @State var previousDrawingTool = CanvasTool.ballpoint
    @State var previousCanvasTool = CanvasTool.pencil
    @State private var textEditingSession: CanvasTextEditingSession?
    @State var isTextToolActive = false
    @State var selectedShapeKind: RecognizedShapeKind?
    @State private var isFileImporterPresented = false
    @State var exportDocument: NotebookExportDocument?
    @State var exportContentType = UTType.pdf
    @State var exportFilename = "Notebook"
    @State private var navigationCommand: CanvasNavigationCommand?
    @State private var viewport = CanvasViewportModel()
    @State private var isMinimapVisible = false
    @State private var editingCommand: CanvasEditingCommand?
    @State private var isObjectSelectionActive = false
    @State private var highlightedStrokeIDs: Set<StrokeID> = []
    @State var plannerRegionSelection = PlannerRegionSelection()
    @State private var isCanvasBrowserPresented = false
    @State private var paperPickerPurpose: PaperPickerPurpose?
    @State var sharedFile: SharedFile?
    @GestureState var toolbarDragTranslation = CGSize.zero
    @GestureState var isToolbarDragging = false
    @AppStorage("defaultPaperType") private var defaultPaperTypeRawValue = PaperType.blankWhite.rawValue
    @AppStorage("isFingerDrawingEnabled") var isFingerDrawingEnabled = false
    @AppStorage("isCanvasLocked") var isCanvasLocked = false
    @AppStorage("isToolbarOnLeft") var isToolbarOnLeft = true
    @AppStorage("canvasToolbarOrientation") var toolbarOrientationRawValue =
        CanvasToolbarOrientation.vertical.rawValue
    @AppStorage("favoriteToolOne") private var favoriteOneData = ""
    @AppStorage("favoriteToolTwo") private var favoriteTwoData = ""
    @AppStorage private var lastViewedCanvasID: String
    init(model: AppModel, notebook: Notebook) {
        self.model = model
        self.notebook = notebook
        let lastViewedCanvasKey = "lastViewedCanvasID.\(notebook.id.rawValue.uuidString.lowercased())"
        _lastViewedCanvasID = AppStorage(wrappedValue: "", lastViewedCanvasKey)
        let targetCanvasID = model.pendingSearchNavigation?.canvasID
        let storedCanvasID = UserDefaults.standard.string(forKey: lastViewedCanvasKey)
            .flatMap(UUID.init(uuidString:))
            .map(CanvasID.init(rawValue:))
        let initialIndex = NotebookCanvasOpeningPolicy.initialIndex(
            canvasIDs: notebook.canvases.map(\.id),
            pendingCanvasID: targetCanvasID,
            storedCanvasID: storedCanvasID
        )
        _canvasIndex = State(initialValue: initialIndex)
#if DEBUG
        if let origin = PencilSqueezeBehavior.radialMenuTestOrigin(arguments: ProcessInfo.processInfo.arguments) {
            _radialMenuOrigin = State(initialValue: origin)
            _isRadialMenuVisible = State(initialValue: true)
        }
#endif
    }

    var body: some View {
        let targetCanvasID = currentCanvas.id
        let persistenceCallbacks = pencilPersistenceCallbacks(for: targetCanvasID)
        return ZStack {
            PencilCanvasView(
                strokes: currentStrokes,
                nonStrokeObjects: currentNonStrokeObjects,
                assets: currentAssets,
                navigationCommand: navigationCommand,
                editingCommand: editingCommand,
                highlightedStrokeIDs: highlightedStrokeIDs,
                recognizedText: currentRecognizedText,
                configuration: configuration,
                canvasID: targetCanvasID,
                activeLayerID: activeLayer.id,
                template: currentCanvas.template,
                plannerRegions: plannerRegions,
                selectedPlannerRegionID: selectedPlannerRegion?.id,
                isPlannerRegionPagingEnabled: isPlannerRegionPagingPresented,
                shouldAnimatePlannerRegionChanges: !isReduceMotionEnabled,
                isFingerDrawingEnabled: allowsFingerDrawingOnCanvas,
                isCanvasLocked: isCanvasLocked,
                textEditingSession: textEditingSession,
                isTextToolActive: isTextToolActive,
                shapePlacementKind: selectedShapeKind,
                actions: pencilCanvasActions(
                    canvasID: targetCanvasID,
                    persistence: persistenceCallbacks
                )
            )
            .id(targetCanvasID)
            floatingToolbar
            if isPlannerRegionPagingPresented {
                VStack {
                    Spacer()
                    PlannerRegionPageControl(
                        regions: plannerRegions,
                        selectedIndex: selectedPlannerRegionIndex,
                        onSelect: selectPlannerRegion
                    )
                    .frame(width: 220, height: 44)
                    .padding(.bottom, 18)
                }
            }
            if isRadialMenuVisible {
                RadialToolMenu(
                    configuration: configuration,
                    isVisible: $isRadialMenuVisible,
                    requestedOrigin: radialMenuOrigin,
                    isSelectionActive: isObjectSelectionActive,
                    onSelect: selectTool,
                    onUndo: { model.undo(notebook.id) },
                    onRedo: { model.redo(notebook.id) },
                    onSetWidth: setWidth,
                    onSetColor: setColor,
                    onSelectEraser: selectEraser,
                    onSelectionAction: sendEditingCommand
                )
            }
            if isMinimapVisible {
                CanvasViewportMinimap(
                    viewport: viewport,
                    contentBounds: currentCanvas.contentBounds
                )
                .frame(width: 190, height: 120)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar { canvasHeader }
        .onAppear {
            loadFavoriteTools()
            applyPendingSearchNavigation()
            revealWrittenContentIfNeeded()
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true
        ) { result in
            do {
                for url in try result.get() {
                    model.importFile(
                        at: url,
                        into: notebook.id,
                        canvasID: currentCanvas.id,
                        layerID: activeLayer.id
                    )
                }
            } catch {
                model.presentedError = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: exportPresentation,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result { model.presentedError = error.localizedDescription }
            exportDocument = nil
        }
        .sheet(isPresented: $isCanvasBrowserPresented) {
            CanvasBrowserView(
                notebook: notebook,
                selectedIndex: $canvasIndex,
                onRename: { canvasID, name in
                    model.renameCanvas(canvasID, to: name, in: notebook.id)
                },
                onDuplicate: { canvasID in
                    model.duplicateCanvas(canvasID, in: notebook.id)
                },
                onMove: { source, destination in
                    model.moveCanvas(from: source, to: destination, in: notebook.id)
                },
                onDelete: deleteCanvas,
                onChangePaper: { canvasID, paperType in
                    model.changeTemplate(paperType, notebookID: notebook.id, canvasID: canvasID)
                }
            )
        }
        .sheet(item: $paperPickerPurpose) { purpose in
            PaperGalleryView(
                initialSelection: purpose == .newCanvas ? defaultPaperType : currentCanvas.template,
                confirmationTitle: purpose == .newCanvas ? "Create" : "Apply"
            ) { paperType in
                if purpose == .newCanvas {
                    addCanvas(paperType)
                } else {
                    changeTemplate(paperType)
                }
            }
        }
        .sheet(item: $sharedFile) { file in
            ActivityShareSheet(items: [file.url])
        }
        .onChange(of: notebook.canvases.count) { _, count in canvasIndex = min(canvasIndex, max(0, count - 1)) }
        .onChange(of: currentCanvas.id) { _, canvasID in
            lastViewedCanvasID = canvasID.rawValue.uuidString.lowercased()
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                model.importFile(at: url, into: notebook.id, canvasID: currentCanvas.id, layerID: activeLayer.id)
            }
            return !urls.isEmpty
        }
    }
    private var canvasHeader: CanvasHeaderView {
        CanvasHeaderView(
            notebookTitle: notebook.title,
            canvasTitle: currentCanvas.title,
            canvasIndex: $canvasIndex,
            canvasCount: notebook.canvases.count,
            layers: currentCanvas.layers,
            isSelectionMenuVisible: configuration.tool == .lasso || isObjectSelectionActive,
            isObjectSelectionActive: isObjectSelectionActive,
            isCanvasLocked: isCanvasLocked,
            onClose: model.closeNotebook,
            onRenameNotebook: { model.renameNotebook(notebook.id, to: $0) },
            onOpenBrowser: { isCanvasBrowserPresented = true },
            onNewCanvas: { paperPickerPurpose = .newCanvas },
            onSelectionAction: sendEditingCommand,
            onToggleCanvasLock: toggleCanvasLock,
            onFitCanvasToContent: zoomToContent,
            onExportPDF: preparePDFExport,
            onExportPNG: preparePNGExport,
            onExportNative: prepareNativeExport,
            onSharePDF: preparePDFShare
        )
    }

    private var defaultPaperType: PaperType {
        PaperType(rawValue: defaultPaperTypeRawValue) ?? .blankWhite
    }

    private func addCanvas(_ paperType: PaperType) {
        model.addCanvas(to: notebook.id, paperType: paperType)
        canvasIndex = notebook.canvases.count
    }

    private func deleteCanvas(_ canvasID: CanvasID) {
        guard let index = notebook.canvases.firstIndex(where: { $0.id == canvasID }) else { return }
        model.deleteCanvas(canvasID, in: notebook.id)
        if index <= canvasIndex { canvasIndex = max(0, canvasIndex - 1) }
    }

    func select(_ toolConfiguration: ToolConfiguration) {
        isTextToolActive = false
        selectedShapeKind = nil
        if configuration.tool != toolConfiguration.tool { previousCanvasTool = configuration.tool }
        palette.select(toolConfiguration.tool)
        palette.setWidth(toolConfiguration.width)
        palette.setColor(toolConfiguration.color)
    }

    func saveFavoriteOne() {
        favoriteOne = configuration
        favoriteOneData = encoded(configuration)
    }

    func saveFavoriteTwo() {
        favoriteTwo = configuration
        favoriteTwoData = encoded(configuration)
    }

    private func loadFavoriteTools() {
        favoriteOne = decoded(favoriteOneData) ?? .favoriteOne
        favoriteTwo = decoded(favoriteTwoData) ?? .favoriteTwo
    }

    private func encoded(_ value: ToolConfiguration) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private func decoded(_ value: String) -> ToolConfiguration? {
        value.data(using: .utf8).flatMap { try? JSONDecoder().decode(ToolConfiguration.self, from: $0) }
    }

    func selectTool(_ tool: CanvasTool) {
        isTextToolActive = false
        selectedShapeKind = nil
        if configuration.tool != tool { previousCanvasTool = configuration.tool }
        if tool != .eraser && tool != .lasso { previousDrawingTool = tool }
        palette.select(tool)
    }

    func setWidth(_ width: ToolWidth) {
        palette.setWidth(width)
    }

    func setColor(_ color: InkColor) {
        palette.setColor(color)
    }

    func selectEraser(_ mode: EraserMode) {
        isTextToolActive = false
        selectedShapeKind = nil
        palette.select(.eraser)
        palette.setEraserMode(mode)
    }
    func toggleRadialMenu() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        if isReduceMotionEnabled {
            isRadialMenuVisible.toggle()
        } else {
            withAnimation(.easeOut(duration: 0.12)) { isRadialMenuVisible.toggle() }
        }
    }

    func handlePencilSqueeze(_ response: PencilSqueezeResponse, location: CGPoint?) {
        switch response {
        case .none:
            break
        case .switchEraser:
            switchDrawingToolAndEraser()
        case .switchPreviousTool:
            switchToPreviousTool()
        case .showRadialPalette:
            radialMenuOrigin = location
            toggleRadialMenu()
        }
    }

    func showPaperGallery() {
        paperPickerPurpose = .currentCanvas
    }

    private func placeText(at point: CanvasPoint) {
        guard isTextToolActive, textEditingSession == nil else { return }
        textEditingSession = .new(
            layerID: activeLayer.id,
            insertionPoint: point,
            constrainedTo: plannerContentRegion(at: point)?.frame
        )
    }

    private func commitText(_ textBlock: TextBlock) {
        let constrainedTextBlock = constrainTextBlockToPlannerRegion(textBlock)
        let isExistingText = currentCanvas.layers
            .flatMap(\.objects)
            .contains { $0.id == constrainedTextBlock.id }
        if isExistingText {
            model.updateTextBlock(constrainedTextBlock, canvasID: currentCanvas.id, notebookID: notebook.id)
        } else {
            model.addTextBlock(
                TextBlockInsertion(
                    text: constrainedTextBlock.text,
                    fontSize: constrainedTextBlock.fontSize,
                    alignment: constrainedTextBlock.alignment,
                    fontName: constrainedTextBlock.fontName,
                    frame: constrainedTextBlock.frame,
                    layerID: constrainedTextBlock.layerID,
                    canvasID: currentCanvas.id
                ),
                notebookID: notebook.id
            )
        }
        textEditingSession = nil
    }

    func importContent() {
        isFileImporterPresented = true
    }

    func returnHome() {
        navigationCommand = CanvasNavigationCommand(action: .home)
    }

    func zoomToContent() {
        navigationCommand = CanvasNavigationCommand(action: .zoomToContent(currentCanvas.exportBounds))
    }

    func toggleMinimap() {
        isMinimapVisible.toggle()
    }

    func toggleCanvasLock() {
        UISelectionFeedbackGenerator().selectionChanged()
        isCanvasLocked.toggle()
    }
}

private extension NotebookEditorView {
    func sendEditingCommand(_ action: CanvasEditingAction) {
        editingCommand = CanvasEditingCommand(action: action)
    }

    func revealWrittenContentIfNeeded() {
        guard navigationCommand == nil else { return }
        let action = CanvasViewportPolicy.openingAction(contentBounds: currentCanvas.contentBounds)
        guard case .zoomToContent = action else { return }
        navigationCommand = CanvasNavigationCommand(action: action)
    }

    func applyPendingSearchNavigation() {
        guard let result = model.pendingSearchNavigation,
              result.notebookID == notebook.id else { return }
        if let canvasID = result.canvasID,
           let index = notebook.canvases.firstIndex(where: { $0.id == canvasID }) {
            canvasIndex = index
        }
        if let bounds = result.bounds {
            navigationCommand = CanvasNavigationCommand(action: .zoomToContent(bounds))
        }
        highlightedStrokeIDs = result.sourceStrokeIDs
        model.pendingSearchNavigation = nil
        Task {
            try? await Task.sleep(for: .seconds(2))
            highlightedStrokeIDs = []
        }
    }
}

extension NotebookEditorView {
    func pencilCanvasActions(
        canvasID: CanvasID,
        persistence: NotebookEditorPencilPersistenceCallbacks
    ) -> PencilCanvasActions {
        let notebookID = notebook.id
        return PencilCanvasActions(
            onStrokesCompleted: persistence.onStrokesCompleted,
            onDrawingChanged: persistence.onDrawingChanged,
            onConvertStrokesToText: { strokes in
                model.convertStrokesToText(Set(strokes.map(\.id)), in: notebookID, canvasID: canvasID)
            },
            onTransformObjects: { objectIDs, transform, center, strokes in
                model.transformObjects(
                    CanvasObjectTransformRequest(
                        objectIDs: objectIDs,
                        transform: transform,
                        center: center,
                        strokeReplacements: strokes
                    ),
                    notebookID: notebookID,
                    canvasID: canvasID
                )
            },
            onDeleteObjects: { model.deleteObjects($0, notebookID: notebookID, canvasID: canvasID) },
            onPasteObjects: { objects in
                model.pasteObjects(objects, notebookID: notebookID, canvasID: canvasID, layerID: activeLayer.id)
            },
            onMoveObjectsToLayer: { objectIDs, layerID in
                model.moveObjects(objectIDs, to: layerID, notebookID: notebookID, canvasID: canvasID)
            },
            onEditText: { textEditingSession = .editing($0) },
            onPlaceText: placeText,
            onPlaceShape: placeShape,
            onCommitText: commitText,
            onCancelText: { textEditingSession = nil },
            onObjectSelectionChanged: { isObjectSelectionActive = $0 },
            onViewportChanged: { viewport.report($0) },
            onPencilSqueeze: { handlePencilSqueeze($0, location: $1) },
            onPencilDoubleTap: switchDrawingToolAndEraser,
            onPlannerRegionPageRequested: selectPlannerRegion,
            onPencilContactChanged: { isActive in
                if isActive { model.pencilContactBegan(on: canvasID) } else { model.pencilContactEnded(on: canvasID) }
            }
        )
    }
}
