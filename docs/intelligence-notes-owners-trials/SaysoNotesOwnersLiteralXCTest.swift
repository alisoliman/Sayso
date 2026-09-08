    func testLiteralNoteLabelsRequireWholeListEqualityApartFromInitialCapitalization() {
        func check(_ source: String, _ output: [String], _ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(IntelligenceTextRules.restoringLiteralNoteLabels(in: output, source: source), expected, file: file, line: line)
        }
        check("- Cora: reserve the hall.\n- Sana: controleer de kabel.", ["Reserve the hall.", "Controleer de kabel."], ["Cora: Reserve the hall.", "Sana: Controleer de kabel."])
        check("- Status: Waiting for approval.", ["Waiting for approval."], ["Status: Waiting for approval."])
        check("- Alia: He said \"go, now\".\n- Jules: wait here.", ["He said \"go now\".", "wait here."], ["He said \"go now\".", "wait here."])
        check("- Amir: No, Lena will collect the parcel.", ["Lena will collect the parcel."], ["Lena will collect the parcel."])
        check("- Ada: send it.\n- Bo: don't send it.", ["don't send it.", "send it."], ["don't send it.", "send it."])
        check("- Logistics:\n  - Noor: check the door.", ["Logistics", "check the door."], ["Logistics", "check the door."])
        check("Evening shift\n- Noor: check the door.", ["check the door."], ["check the door."])
        check("- \"Mina: wait here.\"", ["wait here."], ["wait here."])
        check("- Ada: Notify US staff.", ["Notify us staff."], ["Notify us staff."])
        check("- Ada: Stop?", ["Stop."], ["Stop."])
        check("- Ada: check the cable.\n- Bo: Wait.", ["Check the cable.", "Wait!"], ["Check the cable.", "Wait!"])
        check("- Ada: check the door and window.", ["Check the door.", "Check the window."], ["Check the door.", "Check the window."])
        check("1. Ada: check the door.", ["Check the door."], ["Check the door."])
    }
