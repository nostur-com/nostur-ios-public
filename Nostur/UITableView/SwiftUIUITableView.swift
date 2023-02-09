//
//  SwiftUIUITableView.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/02/2023.
//

import UIKit
import SwiftUI
import CoreData

class HostingCell: UITableViewCell { // just to hold hosting controller
    var host: UIHostingController<AnyView>?
}

struct UIList: UIViewRepresentable {

    @State var didSetup = false
    @Binding var notes:[Event]
//    var events:FetchedResults<Event>

    func makeUIView(context: Context) -> UITableView {
        let collectionView = UITableView(frame: .zero, style: .plain)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.rowHeight = UITableView.automaticDimension
        collectionView.estimatedRowHeight = 200
        collectionView.estimatedRowHeight = UITableView.automaticDimension
        collectionView.register(HostingCell.self, forCellReuseIdentifier: "Cell")
        return collectionView
    }

    func updateUIView(_ uiView: UITableView, context: Context) {
        
        let oldTableViewHeight = uiView.contentSize.height

        context.coordinator.notes = self.notes
        uiView.reloadData()

//        uiView.setNeedsLayout()

        // Put your scroll position to where it was before

        let newTableViewHeight = uiView.contentSize.height;
        uiView.contentOffset = CGPointMake(0, uiView.contentOffset.y + (newTableViewHeight - oldTableViewHeight));
    }
    

    func makeCoordinator() -> Coordinator {
        Coordinator(notes: notes)
//        Coordinator(events: events)
    }

    class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {

//        var events: FetchedResults<Event>
//
//        init(events: FetchedResults<Event>) {
//            self.events = events
//        }
        
        var notes: [Event]

        init(notes: [Event]) {
            self.notes = notes
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            self.notes.count
//            self.events.count
        }
        
        func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
            return UITableView.automaticDimension
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

            let tableViewCell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! HostingCell

//            let view = NoteRowView(event: events[indexPath.row])
            let view = HStack {
                Text("#\(indexPath.row)")
                NoteRowView(event: notes[indexPath.row])
            }
            
            // create & setup hosting controller only once
            if tableViewCell.host == nil {
                let controller = UIHostingController(rootView: AnyView(view))
                tableViewCell.host = controller
                
                let tableCellViewContent = controller.view!
                tableCellViewContent.translatesAutoresizingMaskIntoConstraints = false
                tableViewCell.contentView.addSubview(tableCellViewContent)
                tableCellViewContent.topAnchor.constraint(equalTo: tableViewCell.contentView.topAnchor).isActive = true
                tableCellViewContent.leftAnchor.constraint(equalTo: tableViewCell.contentView.leftAnchor).isActive = true
                tableCellViewContent.bottomAnchor.constraint(equalTo: tableViewCell.contentView.bottomAnchor).isActive = true
                tableCellViewContent.rightAnchor.constraint(equalTo: tableViewCell.contentView.rightAnchor).isActive = true
            } else {
                // reused cell, so just set other SwiftUI root view
                tableViewCell.host?.rootView = AnyView(view)
            }
            tableViewCell.setNeedsLayout()
            return tableViewCell
        }
    }
}


//extension UIList {
//    func setupNotes() {
//        print("setupPages")
//        didSetup = true
//        
//        let oldestAtIndexZero = events.sorted(by: { $0.created_at < $1.created_at })
//        for index in 0..<events.count {
//            notes.append(oldestAtIndexZero[index])
//        }
//        
//        oldestAtIndexZero.forEach { event in
//            print("\(event.id!) \(d(event.created_at))")
//        }
//    }
//    
//    func loadNewNotes() {
//        
//        let oldestAtIndexZero = events.sorted(by: { $0.created_at < $1.created_at })
//        let beforeEventsCount = notes.count
//        for index in 0..<events.count { // 0..<11
//            if (index < beforeEventsCount) { continue }
//            notes.append(oldestAtIndexZero[index])
//            
//            // 0, 1, 2, 3, 4, 5, 6, 7
//            // N, N, 0, 1, 2, 3, 4, 5
//        }
//        oldestAtIndexZero.forEach { event in
//            print("\(event.id!) \(d(event.created_at))")
//        }
//    }
//}
