//
//  SparkleUpdateTypes.swift
//  ClipDock
//

import Foundation

enum SparkleFeedURL {
    static let release = "https://maxcj.github.io/ClipDock/appcast.xml"
    static let beta = "https://maxcj.github.io/ClipDock/appcast-beta.xml"
}

enum SparkleUpdateDefaults {
    static let defaultUpdateChannelRawValue = "release"
}

enum SparkleUpdateChannel: String, CaseIterable, Identifiable {
    case release
    case beta

    var id: String { rawValue }

    var titleKey: AppTextKey {
        switch self {
        case .release:
            return .releaseChannel
        case .beta:
            return .betaChannel
        }
    }

    var feedURLString: String {
        switch self {
        case .release:
            return SparkleFeedURL.release
        case .beta:
            return SparkleFeedURL.beta
        }
    }
}
