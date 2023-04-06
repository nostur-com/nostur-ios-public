//
//  DataSource.swift
//  RagiSmoothList
//
//  Created by ragingo on 2022/12/17.
//

import SwiftUI
import UIKit

final class DataSource<
    SectionType: Hashable,
    ItemType: Hashable
>: UICollectionViewDiffableDataSource<SectionType, ItemType> {
    override func indexTitles(for collectionView: UICollectionView) -> [String]? {
        snapshot().sectionIdentifiers
            .compactMap {
                ($0 as? CustomStringConvertible)?.description
            }
    }
}
