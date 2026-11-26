// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import Testing
import LeanDomain

private func res(_ w: Int, _ h: Int, px: Int? = nil) -> DisplayResolution {
    .init(width: w, height: h, pixelWidth: px ?? w, pixelHeight: (px.map { $0 * h / w }) ?? h)
}
private var nextID: Int32 = 1
private func mode(_ r: DisplayResolution, _ hz: Int) -> DisplayModeOption {
    nextID += 1
    return .init(id: nextID, resolution: r, milliHertz: hz * 1000)
}
private func catalog(current: DisplayModeOption, _ others: [DisplayModeOption]) -> DisplayModeCatalog {
    .init(current: current, modes: others)
}

/// The three displays of the maintainer's desk (widths in mm from macOS).
private func desk(externalCurrent: DisplayResolution? = nil, monitorHz: Int = 100) -> [DisplayCheckInput] {
    let builtinCurrent = mode(res(1800, 1169, px: 3600), 120)
    let builtin = catalog(current: builtinCurrent, [
        mode(res(1512, 982, px: 3024), 120), mode(res(3024, 1964), 120), mode(res(1800, 1169, px: 3600), 60)])

    let fhd = res(1920, 1080)
    let monitor = catalog(current: mode(fhd, monitorHz), [
        mode(fhd, 100), mode(fhd, 75), mode(fhd, 60), mode(res(960, 540, px: 1920), 100), mode(res(1600, 900), 100)])

    let big = res(2048, 1280, px: 4096), small = res(1280, 800, px: 2560), full = res(2560, 1600)
    let panelCurrent = mode(externalCurrent ?? big, 60)
    let panel = catalog(current: panelCurrent, [mode(big, 60), mode(small, 60), mode(full, 60), mode(res(1920, 1200), 60)])

    return [
        .init(id: 1, name: "Built-in", isBuiltIn: true, widthMM: 301.8, catalog: builtin),
        .init(id: 2, name: "24in", isBuiltIn: false, widthMM: 530.1, catalog: monitor),
        .init(id: 3, name: "16in", isBuiltIn: false, widthMM: 340.0, catalog: panel)
    ]
}

@Suite("DisplayCheck")
struct DisplayCheckTests {
    @Test func pointsPerInchUsesPhysicalWidth() throws {
        let d = try #require(DisplayCheck.ptPerInch(width: 1800, widthMM: 301.8))
        #expect(abs(d - 151.5) < 0.5)
        #expect(DisplayCheck.ptPerInch(width: 1800, widthMM: 0) == nil)
    }

    @Test func alreadyMatchedDeskRecommendsNothing() throws {
        let verdicts = DisplayCheck.evaluate(desk())
        #expect(verdicts.allSatisfy { $0.recommended == nil })
        #expect(verdicts[0].isReference)
        let monitor = verdicts[1]
        #expect(monitor.isPanelLimited)              // a 1080p panel cannot reach the built-in's size
        let panel = verdicts[2]
        #expect(!panel.isPanelLimited)
        #expect(panel.isCurrentScaled)               // 4096 px rendered onto a 2560 px panel
        #expect(panel.sharpest?.resolution.width == 1280)
        #expect(verdicts[0].isCurrentScaled)
        #expect(verdicts[0].sharpest?.resolution.width == 1512)
    }

    @Test func externalAtWrongSizeIsMovedToTheMatchingMode() throws {
        let verdicts = DisplayCheck.evaluate(desk(externalCurrent: res(1280, 800, px: 2560)))
        let panel = try #require(verdicts.first { $0.id == 3 })
        #expect(panel.recommended?.resolution.width == 2048)
        let result = try #require(panel.resultPtPerInch)
        let target = try #require(panel.targetPtPerInch)
        #expect(abs(result - target) / target < 0.05)
    }

    @Test func slightlyBetterResolutionDoesNotCauseAChange() throws {
        // 1920x1200 on the 16in panel is farther away than 2048x1280, but the current one is already within the gain threshold.
        let verdicts = DisplayCheck.evaluate(desk())
        #expect(verdicts[2].recommended == nil)
    }

    @Test func lowerRefreshRateIsRaisedToTheMaximum() throws {
        let verdicts = DisplayCheck.evaluate(desk(monitorHz: 60))
        let monitor = try #require(verdicts.first { $0.id == 2 })
        #expect(monitor.recommended?.milliHertz == 100_000)
        #expect(monitor.recommended?.resolution == res(1920, 1080))
    }

    @Test func mirroredAndUnknownSizeAreSkipped() {
        let c = desk()
        let mirrored = DisplayCheckInput(id: 3, name: "m", isBuiltIn: false, widthMM: 340,
                                         catalog: .init(current: c[2].catalog.current, modes: c[2].catalog.modes, isMirrored: true))
        let unknown = DisplayCheckInput(id: 2, name: "u", isBuiltIn: false, widthMM: 0, catalog: c[1].catalog)
        let verdicts = DisplayCheck.evaluate([c[0], unknown, mirrored])
        #expect(verdicts[1].skipped && verdicts[1].recommended == nil)
        #expect(verdicts[2].skipped && verdicts[2].recommended == nil)
    }

    @Test func withoutABuiltInDisplayTheSharpestExternalIsTheReference() {
        let c = desk()
        let verdicts = DisplayCheck.evaluate([c[1], c[2]])
        #expect(verdicts[1].isReference)             // the 16in panel has the higher point density
    }
}
