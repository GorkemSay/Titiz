import SwiftUI
import TitizCore

/// Native macOS popover displaying before/after diff details, TDK rule rationale,
/// clickable Bucket 2 alternatives, per-edit revert ("Geri Al"), and "Bu adı hep koru".
struct EditDetailPopoverView: View {
    let target: InspectionTarget
    let ruleCatalog: SpellingRuleCatalog
    let onApplyEditAlternative: (String, Edit) -> Void
    let onRevertEdit: (Edit) -> Void
    let onApplySuggestionCandidate: (String, AmbiguousTokenSuggestion) -> Void
    let onProtectTerm: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch target {
            case let .edit(edit, _):
                editDetailBody(edit)
            case let .suggestion(suggestion, _):
                suggestionDetailBody(suggestion)
            }
        }
        .padding(14)
        .frame(width: 290, alignment: .leading)
    }

    @ViewBuilder
    private func editDetailBody(_ edit: Edit) -> some View {
        let meta = lookupMetadata(for: edit.ruleID)

        HStack(spacing: 6) {
            Text(edit.original.isEmpty ? "∅" : edit.original)
                .font(.system(.callout, weight: .medium))
                .foregroundStyle(.secondary)
                .strikethrough()

            Image(systemName: "arrow.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)

            Text(edit.replacement.isEmpty ? "∅" : edit.replacement)
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(.primary)
        }

        if let meta {
            VStack(alignment: .leading, spacing: 4) {
                Text(meta.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(meta.explanationTR)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let url = URL(string: meta.tdkReferenceURL) {
                    Link(destination: url) {
                        Label("TDK Kuralına Bak", systemImage: "arrow.up.right.square")
                            .font(.caption2.weight(.medium))
                    }
                    .padding(.top, 2)
                }
            }
        }

        if !edit.alternatives.isEmpty {
            Divider()
            alternativePills(
                title: "Diğer Adaylar",
                candidates: edit.alternatives
            ) { candidate in
                onApplyEditAlternative(candidate, edit)
            }
        }

        Divider()

        HStack(spacing: 8) {
            Button("Geri Al", systemImage: "arrow.uturn.backward") {
                onRevertEdit(edit)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            let protectable = cleanProtectableTerm(edit.original)
            if !protectable.isEmpty {
                Button("Bu adı hep koru", systemImage: "shield") {
                    onProtectTerm(protectable)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func suggestionDetailBody(_ suggestion: AmbiguousTokenSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Belirsiz Bağlam — Özgün Hâli Korundu")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Text("“\(suggestion.original)” geçerli bir sözcük olduğu için değiştirilmedi. İsterseniz aşağıdaki Türkçe adaylardan biriyle değiştirebilirsiniz:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        alternativePills(
            title: "Önerilen Adaylar",
            candidates: suggestion.candidates
        ) { candidate in
            onApplySuggestionCandidate(candidate, suggestion)
        }

        Divider()

        HStack {
            Spacer()
            let protectable = cleanProtectableTerm(suggestion.original)
            if !protectable.isEmpty {
                Button("Bu adı hep koru", systemImage: "shield") {
                    onProtectTerm(protectable)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func alternativePills(
        title: String,
        candidates: [String],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(candidates.prefix(4), id: \.self) { candidate in
                    Button(candidate) {
                        onSelect(candidate)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func lookupMetadata(for ruleID: String) -> SpellingRuleMetadata? {
        if let direct = ruleCatalog.metadata(for: ruleID) {
            return direct
        }
        let parts = ruleID.split(separator: "+").map(String.init)
        if let primary = parts.last, let meta = ruleCatalog.metadata(for: primary) {
            return meta
        }
        if let fallback = parts.first {
            return ruleCatalog.metadata(for: fallback)
        }
        return nil
    }

    private func cleanProtectableTerm(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
