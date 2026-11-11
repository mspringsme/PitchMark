//
//  SignGridViews.swift
//  PitchMark
//
//  Batter & Runner Grids on Home: the list, the editor, and printing.
//  Rules and printing are in SignGrid.swift.
//
import SwiftUI
import FirebaseAuth

// MARK: - Editor

struct SignGridEditorView: View {
    let original: SignGrid
    let onSave: (SignGrid) -> Void
    let onCancel: () -> Void
    @ObservedObject var myCalls: SignGridMyCallsStore

    @State private var draft: SignGrid
    @State private var currentGrid = 0
    @State private var selected = SignGridPosition(row: 0, column: 0)
    @State private var showDiscardDialog = false
    @State private var pendingGridCount: Int? = nil
    @State private var showQuickFill = false
    @State private var showRandomize = false
    /// Randomize's picks, kept while the editor is open.
    @State private var randomPicks: Set<String> = []
    @FocusState private var cellTextFocused: Bool
    @FocusState private var nameFocused: Bool

    init(grid: SignGrid, myCalls: SignGridMyCallsStore,
         onSave: @escaping (SignGrid) -> Void, onCancel: @escaping () -> Void) {
        self.original = grid
        self.myCalls = myCalls
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: grid)
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inchText(_ value: Double) -> String {
        "\(GridKeyPrintSize.inchText(value)) in"
    }

    private var cellText: Binding<String> {
        Binding(
            get: { draft.text(row: selected.row, column: selected.column, in: currentGrid) },
            set: { draft.setText($0, row: selected.row, column: selected.column, in: currentGrid) }
        )
    }

    private func moveToNextCell() {
        selected = draft.cellAfter(selected)
    }

    private func resize(rows: Int, columns: Int) {
        draft.resize(rows: rows, columns: columns)
        selected = SignGridPosition(row: min(selected.row, draft.rows - 1),
                                    column: min(selected.column, draft.columns - 1))
    }

    /// Fewer grids asks first when a grid being removed has something in it.
    private func requestGridCount(_ count: Int) {
        if draft.removesContent(settingGridCount: count) {
            pendingGridCount = count
        } else {
            applyGridCount(count)
        }
    }

    private func applyGridCount(_ count: Int) {
        draft.setGridCount(count)
        currentGrid = min(currentGrid, draft.gridCount - 1)
    }

    private func showGrid(_ index: Int) {
        guard index != currentGrid, (0..<draft.gridCount).contains(index) else { return }
        currentGrid = index
        selected = SignGridPosition(row: 0, column: 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    editorSection("Name") {
                        TextField("Grid name", text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFocused)
                            .accessibilityIdentifier("signGrid.name")
                    }
                    sizeSection
                    layoutSection
                    gridSection
                    wholeCardSection
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            // Rides on top of the keyboard while a cell is being typed in.
            // A bottom inset, not a keyboard toolbar: that one floats over
            // the cell's B F N, and the scroll view keeps the field above
            // an inset.
            .safeAreaInset(edge: .bottom) {
                if cellTextFocused { addToQuickFillBar }
            }
            .navigationTitle(original.name.isEmpty ? "New Grid" : "Edit Grid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if draft == original { onCancel() } else { showDiscardDialog = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = draft
                        saved.name = trimmedName
                        onSave(saved)
                    }
                    .disabled(trimmedName.isEmpty || draft.printSize == nil)
                    .accessibilityIdentifier("signGrid.save")
                }
                // Up top, not above the keyboard: a keyboard toolbar button
                // floats over the cell's B F N.
                if cellTextFocused || nameFocused {
                    ToolbarItem(placement: .principal) {
                        Button {
                            cellTextFocused = false
                            nameFocused = false
                        } label: {
                            Label("Hide Keyboard", systemImage: "keyboard.chevron.compact.down")
                                .labelStyle(.iconOnly)
                        }
                        .tint(.primary)
                        .accessibilityIdentifier("signGrid.keyboardDone")
                    }
                }
            }
        }
        .sheet(isPresented: $showQuickFill) {
            SignGridQuickFillSheet(myCalls: myCalls) { label in
                cellText.wrappedValue = label
                showQuickFill = false
            }
        }
        .sheet(isPresented: $showRandomize) {
            SignGridRandomizeSheet(myCalls: myCalls.calls, picks: $randomPicks,
                                   emptyCells: draft.emptyCallCells.count) { labels in
                draft.randomFill(with: labels)
                showRandomize = false
            }
        }
        .appConfirmationDialog(
            isPresented: $showDiscardDialog,
            title: "Discard Changes?",
            message: "Your changes to this grid won't be saved.",
            primaryTitle: "Discard",
            primaryRole: .destructive,
            primaryAction: { onCancel() },
            secondaryTitle: "Keep Editing"
        )
        .appConfirmationDialog(
            isPresented: Binding(get: { pendingGridCount != nil }, set: { if !$0 { pendingGridCount = nil } }),
            title: "Remove Grid \(draft.gridCount)?",
            message: "Its text and styles will be lost.",
            primaryTitle: "Remove",
            primaryRole: .destructive,
            primaryAction: {
                if let count = pendingGridCount { applyGridCount(count) }
                pendingGridCount = nil
            },
            secondaryTitle: "Keep It"
        )
    }

    private var addToQuickFillBar: some View {
        let text = cellText.wrappedValue
        let blank = SignGridMyCalls.cleaned(text).isEmpty
        let known = myCalls.calls.contains(text)
        return HStack {
            Button {
                myCalls.add(text)
            } label: {
                Label(!blank && known ? "In Quick Fill" : "Add to Quick Fill",
                      systemImage: !blank && known ? "checkmark" : "text.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(.systemGray5)))
            }
            .buttonStyle(.plain)
            .disabled(known)
            .opacity(known ? 0.5 : 1)
            .accessibilityIdentifier("signGrid.addToQuickFill")
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// Every section: a headline, then its controls, spaced the same.
    private func editorSection<Content: View>(_ title: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private var sizeSection: some View {
        editorSection("Print Size") {
            HStack(spacing: 8) {
                sizeMenu(title: "Width", value: draft.widthInches, options: GridKeyProduct.customWidthOptions) {
                    draft.widthInches = $0
                }
                sizeMenu(title: "Height", value: draft.heightInches, options: GridKeyProduct.customHeightOptions) {
                    draft.heightInches = $0
                }
            }
            Text("Prints at exactly \(draft.chosenSize.label).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func sizeMenu(title: String, value: Double, options: [Double],
                          set: @escaping (Double) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(inchText(option)) { set(option) }
            }
        } label: {
            SignGridPill(title: title) {
                Text(inchText(value))
                    .font(.subheadline)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("signGrid.\(title.lowercased())")
    }

    private var layoutSection: some View {
        editorSection("Layout") {
            HStack(spacing: 8) {
                countPill(title: "Rows", id: "rows", value: draft.rows, range: SignGrid.countRange) {
                    resize(rows: $0, columns: draft.columns)
                }
                countPill(title: "Columns", id: "columns", value: draft.columns, range: SignGrid.countRange) {
                    resize(rows: draft.rows, columns: $0)
                }
                countPill(title: "Grids", id: "grids", value: draft.gridCount, range: SignGrid.gridCountRange) {
                    requestGridCount($0)
                }
            }
            let arrangement = draft.arrangement
            Text(draft.gridCount == 1
                 ? "Every grid has \(draft.rows) rows and \(draft.columns) columns."
                 : "\(draft.gridCount) grids, \(arrangement.across) across and \(arrangement.down) down.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Three to a row, so the title sits above - value +.
    private func countPill(title: String, id: String, value: Int, range: ClosedRange<Int>,
                           set: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 0) {
                Button {
                    set(value - 1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .disabled(value <= range.lowerBound)
                .accessibilityLabel("Fewer \(title.lowercased())")
                .accessibilityIdentifier("signGrid.\(id).minus")

                Text("\(value)")
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 22)
                    .accessibilityIdentifier("signGrid.\(id).value")

                Button {
                    set(value + 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .disabled(value >= range.upperBound)
                .accessibilityLabel("More \(title.lowercased())")
                .accessibilityIdentifier("signGrid.\(id).plus")
            }
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemGray5)))
    }

    // MARK: The grid being edited

    private var gridSection: some View {
        let row = selected.row
        let column = selected.column
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Grid \(currentGrid + 1)")
                    .font(.headline)
                    .accessibilityIdentifier("signGrid.currentGrid")
                Spacer()
                if draft.gridCount > 1 {
                    gridStepButton("chevron.left", label: "Previous grid", id: "signGrid.previousGrid",
                                   enabled: currentGrid > 0) { showGrid(currentGrid - 1) }
                    Text("\(currentGrid + 1) of \(draft.gridCount)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    gridStepButton("chevron.right", label: "Next grid", id: "signGrid.nextGrid",
                                   enabled: currentGrid < draft.gridCount - 1) { showGrid(currentGrid + 1) }
                }
            }

            HStack(spacing: 8) {
                Text("Row \(row + 1)")
                    .font(.subheadline.weight(.semibold))
                SignGridStylePicker(id: "row", style: draft.rowStyle(row, in: currentGrid)) {
                    draft.setRowStyle($0, row: row, in: currentGrid)
                }
                Spacer(minLength: 4)
                ColorPicker("Grid \(currentGrid + 1) fill color",
                            selection: Binding(get: { draft.fillColor(in: currentGrid) },
                                               set: { draft.setFillColor($0, in: currentGrid) }),
                            supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 32, height: 32)
                    .accessibilityIdentifier("signGrid.fillColor")
                Spacer(minLength: 4)
                Text("Col \(column + 1)")
                    .font(.subheadline.weight(.semibold))
                SignGridStylePicker(id: "column", style: draft.columnStyle(column, in: currentGrid)) {
                    draft.setColumnStyle($0, column: column, in: currentGrid)
                }
            }
            .lineLimit(1)

            panel

            HStack(spacing: 8) {
                TextField("Cell text", text: cellText)
                    .textFieldStyle(.roundedBorder)
                    .focused($cellTextFocused)
                    .submitLabel(.next)
                    .onSubmit {
                        moveToNextCell()
                        cellTextFocused = true
                    }
                    .accessibilityIdentifier("signGrid.cellText")
                SignGridStylePicker(id: "cell", style: draft.style(row: row, column: column, in: currentGrid)) {
                    draft.setCellStyle($0, row: row, column: column, in: currentGrid)
                }
            }

            Button {
                cellTextFocused = false
                showQuickFill = true
            } label: {
                SignGridPill(title: "Quick Fill") {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("signGrid.quickFill")
        }
    }

    private func gridStepButton(_ systemName: String, label: String, id: String, enabled: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(.systemGray5)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// The current grid at its printed shape, with a button over each cell.
    private var panel: some View {
        let gridSize = SignGridCardLayout(grid: draft, size: draft.chosenSize.points).gridSize
        let ratio = gridSize.width / max(gridSize.height, 0.01)
        return GeometryReader { proxy in
            let size = proxy.size
            let layout = SignGridLayout(rect: CGRect(origin: .zero, size: size), rows: draft.rows, columns: draft.columns)
            ZStack(alignment: .topLeading) {
                SignGridPanelView(grid: draft, index: currentGrid, size: size, lineWidth: 1.5, selected: selected)
                ForEach(0..<draft.rows, id: \.self) { row in
                    ForEach(0..<draft.columns, id: \.self) { column in
                        let frame = layout.frame(row: row, column: column)
                        Button {
                            selected = SignGridPosition(row: row, column: column)
                            cellTextFocused = true
                        } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityLabel("Row \(row + 1), column \(column + 1)")
                        .accessibilityValue(draft.text(row: row, column: column, in: currentGrid))
                        .accessibilityIdentifier("signGrid.cell.\(row).\(column)")
                    }
                }
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .frame(maxHeight: 420)
        .frame(maxWidth: .infinity)
    }

    // MARK: The whole card

    private var wholeCardSection: some View {
        editorSection("Whole Card") {
            SignGridWireframe(grid: draft, current: currentGrid, onSelect: showGrid)
                .aspectRatio(draft.widthInches / max(draft.heightInches, 0.01), contentMode: .fit)
                .frame(maxWidth: 260)
                .frame(maxWidth: .infinity)
            Button {
                cellTextFocused = false
                nameFocused = false
                showRandomize = true
            } label: {
                SignGridPill(title: "Randomize") {
                    Image(systemName: "shuffle")
                        .font(.footnote.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("signGrid.randomize")
            Text("Fills the empty cells on every grid with Quick Fill calls you pick.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// The Quick Fill list. A List in a sheet, not a Menu: a Menu this long
/// loses its scroll position whenever the screen behind it re-renders.
private struct SignGridQuickFillSheet: View {
    @ObservedObject var myCalls: SignGridMyCallsStore
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !myCalls.calls.labels.isEmpty {
                    Section {
                        ForEach(myCalls.calls.labels, id: \.self) { label in
                            Button {
                                onPick(label)
                            } label: {
                                HStack {
                                    Text(label)
                                        .font(.subheadline.weight(.bold).monospaced())
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("signGrid.quickFill.\(label)")
                        }
                        .onDelete { offsets in
                            offsets.map { myCalls.calls.labels[$0] }.forEach(myCalls.remove)
                        }
                    } header: {
                        Text("My Calls")
                    } footer: {
                        Text("Swipe left to remove one.")
                    }
                }
                ForEach(SignGridQuickFill.sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.items, id: \.self) { item in
                            Button {
                                onPick(item.label)
                            } label: {
                                HStack {
                                    Text(item.meaning)
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 12)
                                    Text(item.label)
                                        .font(.subheadline.weight(.bold).monospaced())
                                        .foregroundStyle(.primary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("signGrid.quickFill.\(item.label)")
                        }
                    }
                }
            }
            .navigationTitle("Quick Fill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Randomize: pick the calls, then fill the empty cells with them.
/// A List in a sheet, like Quick Fill (a long Menu loses its place).
private struct SignGridRandomizeSheet: View {
    let myCalls: SignGridMyCalls
    @Binding var picks: Set<String>
    let emptyCells: Int
    let onFill: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss

    private var sections: [(title: String, labels: [String])] {
        let builtIn = SignGridQuickFill.sections.map { ($0.title, $0.items.map(\.label)) }
        return myCalls.labels.isEmpty ? builtIn : [("My Calls", myCalls.labels)] + builtIn
    }

    private var picked: [String] {
        sections.flatMap(\.labels).filter(picks.contains)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(section.labels, id: \.self) { label in
                            Button {
                                if picks.contains(label) { picks.remove(label) } else { picks.insert(label) }
                            } label: {
                                HStack {
                                    Image(systemName: picks.contains(label) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(picks.contains(label) ? Color.primary : Color.secondary)
                                    Text(label)
                                        .font(.subheadline.weight(.bold).monospaced())
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(picks.contains(label) ? "On" : "Off")
                            .accessibilityIdentifier("signGrid.randomize.pick.\(label)")
                        }
                    } header: {
                        HStack {
                            Text(section.title)
                            Spacer()
                            let all = section.labels.allSatisfy(picks.contains)
                            Button(all ? "None" : "All") {
                                if all { picks.subtract(section.labels) } else { picks.formUnion(section.labels) }
                            }
                            .font(.caption.weight(.semibold))
                            .textCase(nil)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    Button {
                        onFill(picked)
                    } label: {
                        Text(emptyCells == 0 ? "No Empty Cells" : "Fill \(emptyCells) Empty \(emptyCells == 1 ? "Cell" : "Cells")")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.primary))
                            .foregroundStyle(Color(.systemBackground))
                    }
                    .buttonStyle(.plain)
                    .disabled(picked.isEmpty || emptyCells == 0)
                    .opacity(picked.isEmpty || emptyCells == 0 ? 0.4 : 1)
                    .accessibilityIdentifier("signGrid.randomize.fill")
                    Text(picked.isEmpty ? "Pick the calls to use." : "\(picked.count) \(picked.count == 1 ? "call" : "calls") picked. Typed cells and the numbers are kept.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Randomize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// B, F and N as one control: B and F turn on and off on their own (both
/// is allowed), N clears both.
private struct SignGridStylePicker: View {
    let id: String
    let style: SignGridStyle
    let set: (SignGridStyle) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment("B", label: "Bold", isOn: style.bold, key: "b") {
                set(SignGridStyle(bold: !style.bold, fill: style.fill))
            }
            Divider().frame(height: 32)
            segment("F", label: "Fill", isOn: style.fill, key: "f") {
                set(SignGridStyle(bold: style.bold, fill: !style.fill))
            }
            Divider().frame(height: 32)
            segment("N", label: "Normal", isOn: style.isNormal, key: "n") {
                set(.normal)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary, lineWidth: 1.5))
        .fixedSize()
    }

    private func segment(_ letter: String, label: String, isOn: Bool, key: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(letter)
                .font(.subheadline.weight(.bold))
                .frame(width: 32, height: 32)
                .background(isOn ? Color.primary : Color.clear)
                .foregroundStyle(isOn ? Color(.systemBackground) : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(id)")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityIdentifier("signGrid.style.\(id).\(key)")
    }
}

/// The card zoomed out: each grid's lines and fills where it prints, the
/// grid being edited outlined. Tap a grid to edit it.
private struct SignGridWireframe: View {
    let grid: SignGrid
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = SignGridCardLayout(grid: grid, size: proxy.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                ForEach(0..<grid.gridCount, id: \.self) { index in
                    let rect = layout.gridRect(index)
                    Button {
                        onSelect(index)
                    } label: {
                        wireGrid(index, size: rect.size)
                    }
                    .buttonStyle(.plain)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityLabel("Grid \(index + 1)")
                    .accessibilityValue(index == current ? "Editing" : "")
                    .accessibilityIdentifier("signGrid.wire.\(index)")
                }
            }
        }
        .environment(\.colorScheme, .light)
    }

    private func wireGrid(_ index: Int, size: CGSize) -> some View {
        let layout = SignGridLayout(rect: CGRect(origin: .zero, size: size), rows: grid.rows, columns: grid.columns)
        return ZStack(alignment: .topLeading) {
            Color.white
            ForEach(0..<grid.rows, id: \.self) { row in
                ForEach(0..<grid.columns, id: \.self) { column in
                    if grid.style(row: row, column: column, in: index).fill {
                        let frame = layout.frame(row: row, column: column)
                        grid.fillColor(in: index)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            Path { path in
                for row in 0...grid.rows {
                    let y = CGFloat(row) * layout.cellSize.height
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                for column in 0...grid.columns {
                    let x = CGFloat(column) * layout.cellSize.width
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
            }
            .stroke(Color.black.opacity(0.45), lineWidth: 0.5)
            if index == current {
                Rectangle()
                    .strokeBorder(Color.orange, lineWidth: 2)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
    }
}

/// The editor's one control shape: a title on the left, its value and
/// controls on the right, on a grey pill.
private struct SignGridPill<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            trailing
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Capsule().fill(Color(.systemGray5)))
        .contentShape(Capsule())
    }
}

// MARK: - List

struct SignGridRow: View {
    let grid: SignGrid
    let onEdit: () -> Void
    let onPrint: () -> Void
    let onArchive: (Bool) -> Void
    var onCallingCard: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(grid.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(grid.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("signGrid.row.\(grid.name)")

            Button(action: onPrint) {
                Image(systemName: "printer")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.primary)
            .disabled(grid.printSize == nil)
            .accessibilityLabel("Print \(grid.name)")

            Button(action: onCallingCard) {
                Image(systemName: "list.number")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.primary)
            .accessibilityLabel("Calling card for \(grid.name)")
            .accessibilityIdentifier("signGrid.callingCard.\(grid.name)")

            Button(grid.isArchived ? "Unarchive" : "Archive") {
                onArchive(!grid.isArchived)
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(.gray)
        }
    }
}

private struct SignGridPDF: Identifiable {
    let id = UUID()
    let url: URL
}

/// The grids, with their editor and print sheets. Used by Home and by
/// the UI-test harness.
struct SignGridListView: View {
    @ObservedObject var store: SignGridStore
    @ObservedObject var myCalls: SignGridMyCallsStore
    @Binding var editing: SignGrid?

    @State private var showArchived = false
    @State private var pdf: SignGridPDF? = nil
    @State private var callingCardGrid: SignGrid? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = store.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if store.activeGrids.isEmpty {
                Text(store.archivedGrids.isEmpty ? "No grids yet. Tap + to make one." : "Every grid is archived.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
            ForEach(store.activeGrids) { grid in
                row(grid)
            }
            if !store.archivedGrids.isEmpty {
                Button(showArchived ? "Hide Archived" : "Show Archived") {
                    withAnimation(.easeInOut(duration: 0.2)) { showArchived.toggle() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.gray)
                if showArchived {
                    ForEach(store.archivedGrids) { grid in
                        row(grid)
                    }
                }
            }
        }
        .sheet(item: $editing) { grid in
            SignGridEditorView(
                grid: grid,
                myCalls: myCalls,
                onSave: { saved in
                    store.save(saved)
                    editing = nil
                },
                onCancel: { editing = nil }
            )
            .interactiveDismissDisabled()
            .fixedAppDynamicType()
        }
        .sheet(item: $pdf) { pdf in
            ShareSheet(items: [pdf.url])
                .fixedAppDynamicType()
        }
        .sheet(item: $callingCardGrid) { grid in
            SignGridCallingCardSheet(grid: grid) { callingCardGrid = nil }
                .fixedAppDynamicType()
        }
    }

    private func row(_ grid: SignGrid) -> some View {
        SignGridRow(
            grid: grid,
            onEdit: { editing = grid },
            onPrint: { print(grid) },
            onArchive: { store.setArchived(grid, $0) },
            onCallingCard: { callingCardGrid = grid }
        )
    }

    private func print(_ grid: SignGrid) {
        guard let size = grid.printSize else { return }
        let url = SignGridPrint.fileURL(for: grid)
        if SignGridPrint.writePDF(for: grid, size: size, to: url) {
            pdf = SignGridPDF(url: url)
        }
    }
}

/// Home's Batter & Runner Grids accordion. Its own struct (not a
/// SettingsView member) so Home's body type doesn't grow - see the
/// SettingsView type-depth crash in CLAUDE.md.
struct SignGridsHomeSection: View {
    @Binding var isExpanded: Bool

    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var store = SignGridStore()
    @StateObject private var myCalls = SignGridMyCallsStore()
    @State private var editing: SignGrid? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Batting Bases & Fielding")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("home.section.batting")
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true }
                    editing = SignGrid()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New batting, bases and fielding grid")
            }
            .padding(.horizontal)

            if isExpanded {
                SignGridListView(store: store, myCalls: myCalls, editing: $editing)
                    .padding(.horizontal)
            }
        }
        .task(id: authManager.user?.uid) {
            store.start(uid: authManager.user?.uid)
            myCalls.start(uid: authManager.user?.uid)
        }
    }
}

/// `-UITestSignGrids`: the list and editor on their own, nothing written
/// to Firestore.
struct SignGridUITestHarness: View {
    @StateObject private var store = SignGridStore(inMemory: true)
    @StateObject private var myCalls = SignGridMyCallsStore(inMemory: true)
    @State private var editing: SignGrid? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                SignGridListView(store: store, myCalls: myCalls, editing: $editing)
                    .padding()
            }
            .navigationTitle("Batting Bases & Fielding")
            .toolbar {
                Button {
                    editing = SignGrid()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityIdentifier("signGrid.new")
            }
        }
    }
}
