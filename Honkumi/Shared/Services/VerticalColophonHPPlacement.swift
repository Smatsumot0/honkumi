import CoreGraphics

nonisolated struct VerticalColophonHPPlacement: Equatable {
    let urlX: CGFloat
    let qrX: CGFloat

    static func make(
        valueX: CGFloat,
        availableWidth: CGFloat,
        urlWidth: CGFloat,
        qrSize: CGFloat,
        bodyMinX: CGFloat,
        bodyMaxX: CGFloat
    ) -> VerticalColophonHPPlacement {
        let valueRegionMaxX = min(
            valueX + max(availableWidth, 0),
            bodyMaxX
        )
        let visibleURLWidth = min(
            max(urlWidth, 0),
            max(valueRegionMaxX - valueX, 0)
        )
        let rawQRX = valueX + max(
            (visibleURLWidth - qrSize) / 2,
            0
        )
        let minimumQRX = max(valueX, bodyMinX)
        let maximumQRX = max(valueRegionMaxX - qrSize, minimumQRX)

        return VerticalColophonHPPlacement(
            urlX: valueX,
            qrX: min(max(rawQRX, minimumQRX), maximumQRX)
        )
    }
}
