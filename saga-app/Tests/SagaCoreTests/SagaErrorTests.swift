import Foundation
import Testing
@testable import Saga

@Suite("SagaError")
struct SagaErrorTests {

    @Test("micPermissionDenied har recovery med System Settings-URL")
    func micPermissionDeniedRecovery() {
        let error = SagaError.micPermissionDenied()
        #expect(!error.title.isEmpty)
        #expect(!error.detail.isEmpty)
        #expect(error.recovery != nil)
        if case .openURL(let url) = error.recovery?.kind {
            #expect(url.absoluteString.contains("Privacy_Microphone"))
        } else {
            Issue.record("Forventede openURL-recovery")
        }
    }

    @Test("axPermissionMissing peger på Accessibility-pane")
    func axPermissionRecovery() {
        let error = SagaError.axPermissionMissing()
        if case .openURL(let url) = error.recovery?.kind {
            #expect(url.absoluteString.contains("Privacy_Accessibility"))
        } else {
            Issue.record("Forventede openURL-recovery")
        }
    }

    @Test("speechRecognitionDenied peger på SpeechRecognition-pane")
    func speechRecognitionRecovery() {
        let error = SagaError.speechRecognitionDenied()
        if case .openURL(let url) = error.recovery?.kind {
            #expect(url.absoluteString.contains("Privacy_SpeechRecognition"))
        } else {
            Issue.record("Forventede openURL-recovery")
        }
    }

    @Test("asrModelLoading + selectionRequired har INGEN recovery (informational)")
    func informationalErrorsHaveNoRecovery() {
        #expect(SagaError.asrModelLoading().recovery == nil)
        #expect(SagaError.selectionRequired().recovery == nil)
        #expect(SagaError.micPermissionNotRequested().recovery == nil)
    }

    @Test("generic wrapper bevarer detail-teksten")
    func genericWrapsDetail() {
        let error = SagaError.generic("Noget gik galt i testen")
        #expect(error.detail == "Noget gik galt i testen")
        #expect(error.recovery == nil)
    }

    @Test("Equatable: samme factory giver samme værdi")
    func equatable() {
        #expect(SagaError.micPermissionDenied() == SagaError.micPermissionDenied())
        #expect(SagaError.micPermissionDenied() != SagaError.axPermissionMissing())
    }
}
