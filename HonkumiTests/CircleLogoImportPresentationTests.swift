@testable import Honkumi
import UniformTypeIdentifiers
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

    func testApprovedCircleLogoCopy() {
        XCTAssertEqual(CircleLogoImportCopy.uploadButton, "アップロード")
        XCTAssertEqual(CircleLogoImportCopy.photoSource, "写真から選択")
        XCTAssertEqual(CircleLogoImportCopy.fileSource, "ファイルから選択")
        XCTAssertEqual(CircleLogoImportCopy.cancel, "キャンセル")
    }

    func testFileTypesExplicitlyContainImageAndSVG() {
        XCTAssertTrue(CircleLogoImportFileTypes.allowed.contains(.image))
        XCTAssertTrue(CircleLogoImportFileTypes.allowed.contains(.svg))
    }
}
