//
//  UIListContentConfiguration.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/02/2023.
//

import Foundation
import UIKit

private let aCellIdentifier = "someIdentifier"

override func viewDidLoad() {
    super.viewDidLoad()
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: aCellIdentifier)
}

func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    guard let cell = tableView.dequeueReusableCell(withIdentifier: aCellIdentifier) else {
        fatalError("You forgot to register your table view cell")
    }

    // Example content based on:
    // https://developer.apple.com/documentation/uikit/uilistcontentconfiguration
    var listContentConfiguration = cell.defaultContentConfiguration()
    listContentConfiguration.image = UIImage(systemName: "star")
    listContentConfiguration.text = "Favorites"
    listContentConfiguration.imageProperties.tintColor = .purple

    cell.contentConfiguration = listContentConfiguration

    return cell
}
