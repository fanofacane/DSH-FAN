// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing
@testable import DSHClient
struct ComposerTests {
    @Test func contracts() {
        #expect(ComposerCompletion.mention(path: "one.txt", directory: false) == "@one.txt")
        #expect(ComposerCompletion.mention(path: "my file.txt", directory: false) == "@\"my file.txt\"")
        #expect(ComposerCompletion.mention(path: "my folder", directory: true) == "@\"my folder/")
        #expect(ComposerCompletion.mention(path: "bad\"name", directory: false) == nil)
        #expect(ComposerCompletion.mention(path: "bad\nname", directory: false) == nil)
        #expect(ComposerCompletion.fileRange(in: "read @one") != nil)
        #expect(ComposerCompletion.fileRange(in: "read @\"my folder/") != nil)
        #expect(ComposerCompletion.fileRange(in: "a@b.test") == nil)
        #expect(ComposerCompletion.fileRange(in: "read @one then") == nil)
    }
}
