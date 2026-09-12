import TelefonDomain

extension PhoneModel {
    func block(_ number: String) {
        block([number])
    }

    func block(_ numbers: [String]) {
        do {
            var next = snapshot
            var keys = Set(next.blocks.compactMap { try? CallDestination($0.number).matchingKey() })
            for number in numbers {
                guard let value = try? CallDestination(number), keys.insert(value.matchingKey()).inserted else { continue }
                next.blocks.append(BlockRule(number: value.value))
            }
            guard next.blocks != snapshot.blocks else { return }
            try commit(next, changes: SnapshotChanges(preferences: true))
        } catch { report(error) }
    }

    func unblock(_ number: String) {
        unblock([number])
    }

    func unblock(_ numbers: [String]) {
        do {
            let keys = Set(numbers.compactMap { try? CallDestination($0).matchingKey() })
            guard !keys.isEmpty else { return }
            var next = snapshot
            next.blocks.removeAll { rule in
                guard let key = try? CallDestination(rule.number).matchingKey() else { return false }
                return keys.contains(key)
            }
            guard next.blocks != snapshot.blocks else { return }
            try commit(next, changes: SnapshotChanges(preferences: true))
        } catch { report(error) }
    }
}
