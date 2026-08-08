import SwiftUI
import UniformTypeIdentifiers
struct NotebookEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    let notebook: Notebook
    @State var canvasIndex = 0
    @State var palette = ToolPaletteState()
    @State var favoriteOne = ToolConfiguration.favoriteOne
    @State var favoriteTwo = ToolConfiguration.favoriteTwo
    @State private var isRadialMenuVisible = false
    @State private var radialMenuOrigin: CGPoint?
    @State private var previousDrawingTool = CanvasTool.ballpoint
    @State private var textEditingSession: CanvasTextEditingSession?
    @State var isTextToolActive = false
    @State private var isFileImporterPresented = false
    @State private var exportDocument: NotebookExportDocument?
    @State private var exportContentType = UTType.pdf
    @State private var exportFilename = "Notebook"
    @State private var navigationCommand: CanvasNavigationCommand?
    @State private var visibleCanvasBounds = CanvasRect(x: 9_500, y: 9_500, width: 1_024, height: 1_366)
    @State private var isMinimapVisible = false
    @State private var editingCommand: CanvasEditingCommand?
    @State private var isObjectSelectionActive = false
    @State private var highlightedStrokeIDs: Set<StrokeID> = []
    @State private var isCanvasBrowserPresented = false
    @State private var paperPickerPurpose: PaperPickerPurpose?
    @State private var sharedFile: SharedFile?
    @AppStorage("defaultPaperType") private var defaultPaperTypeRawValue = PaperType.blankWhite.rawValue
    @AppStorage("isFingerDrawingEnabled") private var isFingerDrawingEnabled = false
    @AppStorage("isToolbarOnLeft") var isToolbarOnLeft = true
    @AppStorage("canvasToolbarOrientation") private var toolbarOrientationRawValue =
        CanvasToolbarOrientation.vertical.rawValue
    @AppStorage("favoriteToolOne") private var favoriteOneData = ""
    @AppStorage("favoriteToolTwo") private var favoriteTwoData = ""
    init(model: AppModel, notebook: Notebook) {
        self.model = model
        self.notebook = notebook
        let targetCanvasID = model.pendingSearchNavigation?.canvasID
        let initialIndex = notebook.canvases.firstIndex { $0.id == targetCanvasID } ?? 0
        _canvasIndex = State(initialValue: initialIndex)
    }

    var toolbarOrientation: CanvasToolbarOrientation {
        CanvasToolbarOrientation(rawValue: toolbarOrientationRawValue) ?? .vertical
    }

    var selectedDrawingTool: CanvasTool {
        configuration.tool.instrument == nil ? previousDrawingTool : configuration.tool
    }

    var body: some View {
        ZStack {
            PencilCanvasView(
                strokes: currentStrokes,
                nonStrokeObjects: currentNonStrokeObjects,
                assets: currentAssets,
                navigationCommand: navigationCommand,
                editingCommand: editingCommand,
                highlightedStrokeIDs: highlightedStrokeIDs,
                recognizedText: currentRecognizedText,
                configuration: configuration,
                template: currentCanvas.template,
                isFingerDrawingEnabled: DrawingInputPolicy.allowsFingerDrawingForCurrentBuild(
                    userPreference: isFingerDrawingEnabled
                ),
                textEditingSession: textEditingSession,
                isTextToolActive: isTextToolActive,
                onStrokesCompleted: { strokes in
                    let didSnapShape = model.addStrokes(
                        strokes,
                        to: notebook.id,
                        canvasID: currentCanvas.id,
                        layerID: activeLayer.id,
                        shouldConvertToText: configuration.tool == .handwritingToText
                    )
                    if didSnapShape { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                },
                onDrawingChanged: { strokes in
                    model.replaceVisibleStrokes(strokes, in: notebook.id, canvasID: currentCanvas.id)
                },
                onConvertStrokesToText: { strokes in
                    model.convertStrokesToText(Set(strokes.map(\.id)), in: notebook.id, canvasID: currentCanvas.id)
                },
                onTransformObjects: { objectIDs, transform, center in
                    model.transformObjects(
                        objectIDs,
                        transform: transform,
                        center: center,
                        notebookID: notebook.id,
                        canvasID: currentCanvas.id
                    )
                },
                onDeleteObjects: { objectIDs in
                    model.deleteObjects(objectIDs, notebookID: notebook.id, canvasID: currentCanvas.id)
                },
                onPasteObjects: { objects in
                    model.pasteObjects(objects, notebookID: notebook.id, canvasID: currentCanvas.id)
                },
                onMoveObjectsToLayer: { objectIDs, layerID in
                    model.moveObjects(
                        objectIDs,
                        to: layerID,
                        notebookID: notebook.id,
                        canvasID: currentCanvas.id
                    )
                },
                onEditText: { textBlock in
                    textEditingSession = .editing(textBlock)
                },
                onPlaceText: placeText,
                onCommitText: commitText,
                onCancelText: { textEditingSession = nil },
                onObjectSelectionChanged: { isObjectSelectionActive = $0 },
                onViewportChanged: { visibleCanvasBounds = $0 },
                onPencilSqueeze: { location in
                    radialMenuOrigin = location
                    showRadialMenu()
                },
                onPencilDoubleTap: switchDrawingToolAndEraser
            )
            floatingToolbar
            if isRadialMenuVisible {
            RadialToolMenu(
                    configuration: configuration,
                    isVisible: $isRadialMenuVisible,
                    requestedOrigin: radialMenuOrigin,
                    isSelectionActive: isObjectSelectionActive,
                    onSelect: selectTool,
                    onUndo: { model.undo(notebook.id) },
                    onRedo: { model.redo(notebook.id) },
                    onCycleWidth: cycleWidth,
                    onCycleColor: cycleColor,
                    onSelectionAction: sendEditingCommand
                )
                    .transition(.opacity.combined(with: .scale(scale: 0.86)))
            }
            if isMinimapVisible {
                CanvasMinimapView(
                    contentBounds: currentCanvas.contentBounds ?? visibleCanvasBounds,
                    viewportBounds: visibleCanvasBounds
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
                onMove: { source, destination in
                    model.moveCanvas(from: source, to: destination, in: notebook.id)
                },
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
            isFingerDrawingEnabled: $isFingerDrawingEnabled,
            onClose: model.closeNotebook,
            onRenameNotebook: { model.renameNotebook(notebook.id, to: $0) },
            onOpenBrowser: { isCanvasBrowserPresented = true },
            onNewCanvas: { paperPickerPurpose = .newCanvas },
            onSelectionAction: sendEditingCommand,
            onExportPDF: preparePDFExport,
            onExportPNG: preparePNGExport,
            onExportNative: prepareNativeExport,
            onSharePDF: preparePDFShare,
            onDuplicateCanvas: { model.duplicateCanvas(currentCanvas.id, in: notebook.id) },
            onDeleteCanvas: deleteCanvas,
            onMoveCanvas: moveCanvas
        )
    }

    private var defaultPaperType: PaperType {
        PaperType(rawValue: defaultPaperTypeRawValue) ?? .blankWhite
    }

    private func addCanvas(_ paperType: PaperType) {
        model.addCanvas(to: notebook.id, paperType: paperType)
        canvasIndex = notebook.canvases.count
    }

    private func deleteCanvas() {
        model.deleteCanvas(currentCanvas.id, in: notebook.id)
        canvasIndex = max(0, canvasIndex - 1)
    }

    private func moveCanvas(to destination: Int) {
        model.moveCanvas(from: canvasIndex, to: destination, in: notebook.id)
        canvasIndex = destination
    }
    func select(_ toolConfiguration: ToolConfiguration) {
        isTextToolActive = false
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
        palette.select(.eraser)
        palette.setEraserMode(mode)
    }
    func cycleWidth() {
        let widths = ToolWidth.allCases
        let index = widths.firstIndex(of: configuration.width) ?? 0
        palette.setWidth(widths[(index + 1) % widths.count])
    }

    func cycleColor() {
        let colors: [InkColor] = [
            .black,
            InkColor(red: 0.18, green: 0.32, blue: 0.55, alpha: 1),
            InkColor(red: 0.65, green: 0.2, blue: 0.18, alpha: 1)
        ]
        let index = colors.firstIndex(of: configuration.color) ?? 0
        palette.setColor(colors[(index + 1) % colors.count])
    }

    func showRadialMenu() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        if isReduceMotionEnabled {
            isRadialMenuVisible = true
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isRadialMenuVisible = true }
        }
    }

    func changeTemplate(_ template: CanvasTemplate) {
        model.changeTemplate(template, notebookID: notebook.id, canvasID: currentCanvas.id)
    }

    func showPaperGallery() {
        paperPickerPurpose = .currentCanvas
    }

    func addLayer() {
        model.addLayer(to: currentCanvas.id, in: notebook.id)
    }

    func activateTextTool() {
        isTextToolActive = true
    }

    private func placeText(at point: CanvasPoint) {
        guard isTextToolActive, textEditingSession == nil else { return }
        textEditingSession = .new(layerID: activeLayer.id, insertionPoint: point)
    }

    private func commitText(_ textBlock: TextBlock) {
        guard let session = textEditingSession else { return }
        if session.isExistingText {
            model.updateTextBlock(textBlock, canvasID: currentCanvas.id, notebookID: notebook.id)
        } else {
            model.addTextBlock(
                TextBlockInsertion(
                    text: textBlock.text,
                    fontSize: textBlock.fontSize,
                    alignment: textBlock.alignment,
                    fontName: textBlock.fontName,
                    frame: textBlock.frame,
                    layerID: textBlock.layerID,
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

}

private extension NotebookEditorView {
    func preparePDFExport() {
        do {
            exportDocument = NotebookExportDocument(
                data: try NotebookPDFExporter().export(notebook, assets: model.assets(in: notebook))
            )
            exportContentType = .pdf
            exportFilename = notebook.title
        } catch {
            model.presentedError = error.localizedDescription
        }
    }

    func preparePNGExport() {
        do {
            exportDocument = NotebookExportDocument(
                data: try CanvasPNGExporter().export(currentCanvas, region: currentCanvas.exportBounds)
            )
            exportContentType = .png
            exportFilename = "\(notebook.title) - \(currentCanvas.title)"
        } catch {
            model.presentedError = error.localizedDescription
        }
    }

    func prepareNativeExport() {
        do {
            let package = NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
            let wrapper = try NativeNotebookArchive().fileWrapper(package: package, assets: model.assets(in: notebook))
            exportDocument = NotebookExportDocument(wrapper: wrapper)
            exportContentType = NotebookExportDocument.nativeType
            exportFilename = notebook.title
        } catch {
            model.presentedError = error.localizedDescription
        }
    }

    func preparePDFShare() {
        do {
            let data = try NotebookPDFExporter().export(notebook, assets: model.assets(in: notebook))
            let url = FileManager.default.temporaryDirectory
                .appending(path: notebook.title)
                .appendingPathExtension("pdf")
            try data.write(to: url, options: .atomic)
            sharedFile = SharedFile(url: url)
        } catch {
            model.presentedError = error.localizedDescription
        }
    }

    func sendEditingCommand(_ action: CanvasEditingAction) {
        editingCommand = CanvasEditingCommand(action: action)
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
    private var exportPresentation: Binding<Bool> {
        Binding(
            get: { exportDocument != nil },
            set: { if !$0 { exportDocument = nil } }
        )
    }

    func switchDrawingToolAndEraser() {
        isTextToolActive = false
        if configuration.tool == .eraser {
            palette.select(previousDrawingTool)
        } else {
            if configuration.tool != .lasso { previousDrawingTool = configuration.tool }
            palette.select(.eraser)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
