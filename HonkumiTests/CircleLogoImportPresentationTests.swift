@testable import Honkumi
import XCTest

final class CircleLogoImportPresentationTests: XCTestCase {
    func testReplacingSourceChooserWithPhotoPickerSurvivesStaleDialogDismissal() {
        var presentation = CircleLogoImportPresentation()

        presentation.present(.sourceChooser)
        presentation.present(.photoLibrary)
        presentation.dismiss(.sourceChooser)

        XCTAssertTrue(presentation.isPresented(.photoLibrary))
        XCTAssertFalse(presentation.isPresented(.sourceChooser))
    }

    func testDismissingCurrentDestinationClearsPresentation() {
        var presentation = CircleLogoImportPresentation()

        presentation.present(.fileImporter)
        presentation.dismiss(.fileImporter)

        XCTAssertNil(presentation.destination)
    }
}
