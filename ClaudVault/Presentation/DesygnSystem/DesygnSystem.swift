import SwiftUI

enum AppTypography{
    static let screenTitle = Font.system(
        .largeTitle,
        design: .default,
        weight:.bold
    )
    
    static let navigationTitle = Font.system(
        .largeTitle,
        design: .default,
        weight: .bold
    )
    static let sectionTitle = Font.system(
        .title2,
        design: .default,
        weight: .semibold
    )
    static let secondary = Font.system(
        .subheadline,
        design: .default
    )
    static let cardTitle = Font.system(
        .headline,
        design: .default,
        weight: .semibold
    )
    static let body = Font.system(
        .body,
        design: .default,
        weight: .medium
    )
    static let bodyMedium = Font.system(
        .body,design:
                .default,
        weight:.medium
    )
    static let brand = Font.system(
        size:12,
        weight: .semibold,
        design: .default
    )
    static let metric = Font.system(
        .title3,
        design: .monospaced
    )
    static let metricSmall = Font.system(
        .caption,
        design: .monospaced
    )
    static let caption = Font.system(
        .caption2,
        design: .serif
    )
}

enum AppSpacing{
    static let xxs:CGFloat = 4
    static let xs:CGFloat = 8
    static let sm:CGFloat = 12
    static let md:CGFloat = 16
    static let lg:CGFloat = 20
    static let xl:CGFloat = 24
    static let xxl:CGFloat = 32
    static let xxxl:CGFloat = 40
    static let cardPadding:CGFloat = 2
    static let screenHorizontal:CGFloat = 24
    static let screenVertical:CGFloat = 24
    
    static let sectionSpacing:CGFloat = 24
    static let itemSpacing:CGFloat = 12
    
    static let buttomPadding:CGFloat = 16
    static let inputPadding:CGFloat = 14
    
    static let tabBarPadding:CGFloat = 12
}
enum AppRadius{
    static let small:CGFloat = 8
    static let medium:CGFloat = 12
    
    static let button:CGFloat = 12
    static let input:CGFloat = 12
    static let card:CGFloat = 16
    
    static let large: CGFloat = 20
    static let extraLarge: CGFloat = 24
    static let capsule:CGFloat = 1000
}
