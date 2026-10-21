import SwiftUI

/// Listenzeile der Bibliothek: Thumbnail, Titel, Metadaten und Vertrauens-Badge.
struct RecipeCardView: View {
    let recipe: RecipeItem

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            thumbnail
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(recipe.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: AppTheme.Spacing.s) {
                    if let total = recipe.totalTimeMinutes {
                        Label("\(total) Min", systemImage: "clock")
                    }
                    Label("\(recipe.servings)", systemImage: "person.2")
                    if recipe.hasNutrition {
                        Label("\(recipe.caloriesPerServing) kcal", systemImage: "flame")
                    }
                    Label(recipe.source.kind.title, systemImage: recipe.source.kind.symbolName)
                        .labelStyle(.iconOnly)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                TrustBadgeView(recipe: recipe)
            }

            Spacer(minLength: 0)

            if recipe.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(AppTheme.destructive)
                    .accessibilityLabel("Favorit")
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = recipe.thumbnailData ?? recipe.heroImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                AppTheme.tertiaryBackground
                Image(systemName: "fork.knife")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    List {
        RecipeCardView(recipe: RecipeItem.sampleShakshuka())
        RecipeCardView(recipe: RecipeItem.samplePancakes())
    }
    .scrollContentBackground(.hidden)
    .background(AppTheme.background)
}
