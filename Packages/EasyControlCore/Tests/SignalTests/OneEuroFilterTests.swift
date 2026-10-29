import Testing
@testable import Signal

@Test func firstSamplePassesThrough() {
    var f = OneEuroFilter()
    #expect(f.filter([0.3, 0.7], at: 0) == [0.3, 0.7])
}

@Test func constantInputStaysConstant() {
    var f = OneEuroFilter()
    var out = SIMD2<Float>.zero
    for i in 0..<30 { out = f.filter([0.3, 0.7], at: Double(i) / 30) }
    #expect(abs(out.x - 0.3) < 1e-6 && abs(out.y - 0.7) < 1e-6)
}

@Test func stepConvergesWithinHalfSecond() {
    var f = OneEuroFilter()
    _ = f.filter([0, 0], at: 0)
    var last: Float = 0
    var valueAtHalf: Float = 0
    for i in 1...30 {
        let t = Double(i) / 30
        let v = f.filter([1, 1], at: t).x
        #expect(v >= last)
        last = v
        if i == 15 { valueAtHalf = v }
    }
    #expect(valueAtHalf > 0.95)
}

@Test func gapResetsFilter() {
    var f = OneEuroFilter()
    for i in 0..<30 { _ = f.filter([0, 0], at: Double(i) / 30) }
    #expect(f.filter([1, 1], at: 29.0 / 30 + 0.5) == [1, 1])
}
