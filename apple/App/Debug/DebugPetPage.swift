// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/test/pets/{pet_golden_test,support}.dart (composer, strip, held and bubble).
#if DEBUG
import SwiftUI

struct DebugPetPage: View {
    var body: some View {
        GeometryReader { geometry in
            let fixture = DebugPageRegistry.argument("-dsh-screen-fixture")
            let strip = fixture == "strip"
            let bubble = fixture == "bubble"
            let expression: PetExpression = strip ? .working : bubble ? .error : .idle
            let frame = CGRect(x: 12, y: geometry.size.height - (strip ? 92 : 52),
                               width: geometry.size.width - 24, height: 44)
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("改好了。登录按钮在请求返回前会保持禁用，重复点击不会再发出第二次请求。")
                    .type(.body).foregroundStyle(DS.ink)
                Text("测试 12 项全部通过。").type(.body).foregroundStyle(DS.ink)
                Spacer()
                if strip {
                    HStack {
                        Text("Running a command").settingsType(.bodySmall)
                        Spacer()
                    }.padding(.horizontal, Space.md).frame(height: 34).glassCapsule(.chrome)
                }
                HStack(spacing: Space.md) {
                    Glyph(glyph: AppIcon.add, size: 20)
                    Text("Message").settingsType(.bodyMedium).foregroundStyle(DS.inkFaint)
                    Spacer()
                    Glyph(glyph: AppIcon.voice, size: 20)
                }
                .padding(.horizontal, Space.md).frame(height: 44).glassCapsule(.chrome)
            }
            .padding(.horizontal, Space.floatInset)
            .padding(.top, Space.lg).padding(.bottom, Space.sm)
            .background { AppBackdrop() }
            .overlay {
                PetStage(perch: frame, fixturePose: expression,
                         fixtureHold: fixture == "held" ? CGSize(width: 80, height: -200) : nil,
                         fixtureBubble: bubble ? PetBubbleState(
                            PetEvent(id: "example", kind: .failed, session: "b", title: "修复登录重复提交", at: .now), now: .now) : nil)
            }
        }
    }
}
#endif
