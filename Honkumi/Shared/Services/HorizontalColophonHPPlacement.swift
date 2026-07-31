import CoreGraphics

nonisolated struct HorizontalColophonHPPlacement: Equatable {
    let urlX: CGFloat
    let qrX: CGFloat

    static func make(
        valueX: CGFloat,
        availableWidth: CGFloat,
        urlWidth: CGFloat,
        qrSize: CGFloat,
        showsURL: Bool,
        bodyMinX: CGFloat,
        bodyMaxX: CGFloat
    ) -> HorizontalColophonHPPlacement {
        let rawQRX: CGFloat
        if showsURL {
            rawQRX = valueX + (max(urlWidth, 0) - qrSize) / 2
        } else {
            rawQRX = valueX + (max(availableWidth, 0) - qrSize) / 2
        }
        let maximumQRX = max(bodyMaxX - qrSize, bodyMinX)

        return HorizontalColophonHPPlacement(
            urlX: valueX,
            qrX: min(max(rawQRX, bodyMinX), maximumQRX)
        )
    }
}
