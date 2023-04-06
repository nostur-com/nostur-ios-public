//
//  RagiSmoothListSectionModel.swift
//  RagiSmoothList
//
//  Created by ragingo on 2022/12/09.
//

import Foundation

public struct RagiSmoothListSectionModel<Section: Identifiable & Hashable, ItemType: Identifiable & Hashable> {
    public typealias ItemsType = [ItemType]
    public var section: Section
    public var items: ItemsType

    public init(section: Section, items: ItemsType) {
        self.section = section
        self.items = items
    }
}

extension RagiSmoothListSectionModel: Hashable {}

public extension Array where Element: Identifiable & Hashable {
    func listEmptySectionModels() -> [RagiSmoothListSectionModel<RagiSmoothListEmptySection, Element>] {
        [
            RagiSmoothListSectionModel(
                section: RagiSmoothListEmptySection(),
                items: self
            )
        ]
    }
}

public extension Array {
    func listSectionModels<
        Section: Identifiable & Hashable,
        ItemType: Identifiable & Hashable
    >() -> [RagiSmoothListSectionModel<Section, ItemType>]
    where Element == (section: Section, items: RagiSmoothListSectionModel<Section, ItemType>.ItemsType) {
        self.compactMap { pair in
            RagiSmoothListSectionModel(
                section: pair.section,
                items: pair.items
            )
        }
    }
}
