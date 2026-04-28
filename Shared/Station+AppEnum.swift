import AppIntents

@available(macOS 14.0, *)
extension Station: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Station")
    }

    static var caseDisplayRepresentations: [Station: DisplayRepresentation] {
        [
            .nts1: DisplayRepresentation(title: "NTS 1"),
            .nts2: DisplayRepresentation(title: "NTS 2")
        ]
    }
}
