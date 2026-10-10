// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XodusCore

extension Checks {
    /// M1: evidence-grounded package-type detection. Every case pins gathered
    /// file/manifest evidence to its expected neutral format verdict, and the
    /// classification round-trips through Codable so persisted evidence is stable.
    func packageTypeChecks() throws {
        let cases = try fixture("package-types-v1")["cases"]?.array ?? []
        check(cases.count >= 8, "Package-type corpus pins the format matrix across evidence combinations")
        for value in cases {
            guard let name = value["name"]?.string,
                  let expectedRaw = value["expected"]?.string,
                  let expected = PackageType(rawValue: expectedRaw),
                  let evidenceValue = value["evidence"] else {
                check(false, "Package-type case is well formed")
                continue
            }
            let evidence = try evidenceValue.decode(PackageTypeEvidence.self)
            check(PackageType.classify(evidence) == expected,
                  "Package-type detection: \(name) classifies as \(expected.label) from file evidence")
            let round = try JSONDecoder().decode(PackageTypeEvidence.self,
                from: JSONEncoder().encode(evidence))
            check(round == evidence && PackageType.classify(round) == expected,
                  "Package-type evidence round-trips through Codable without changing the verdict: \(name)")
        }
        // A fully empty evidence record is Unknown, never silently a supported format.
        check(PackageType.classify(PackageTypeEvidence()) == .unknown,
              "Absent package evidence is Unknown, not an invented format")
        // Full-trust universal manifests are packaged Win32 (Appx), not sandboxed UWP.
        check(PackageType.classify(PackageTypeEvidence(hasAppxManifest: true,
            targetDeviceFamilies: ["Windows.Universal"], declaresFullTrustEntryPoint: true)) == .appx,
              "A universal manifest declaring full trust is packaged Win32 (Appx), not UWP")
        check(PackageType.classify(PackageTypeEvidence(hasAppxManifest: true,
            targetDeviceFamilies: ["Windows.Universal"])) == .uwp,
              "A universal manifest without full trust is UWP")
    }
}
