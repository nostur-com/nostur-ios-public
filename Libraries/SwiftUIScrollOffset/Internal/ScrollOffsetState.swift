/**
*  SwiftUIScrollOffset
*  Copyright (c) Ciaran O'Brien 2024
*  MIT license, see LICENSE file for details
*/

import Combine
import Observation
import SwiftUI

@Observable
@available(iOS 17, macOS 14, tvOS 17, visionOS 1, *)
internal final class ScrollOffsetState: BaseScrollOffsetState {
    private(set) var value = CGFloat.zero
    
    func update(edge: Edge, id: AnyHashable?, range: ClosedRange<CGFloat>) {
        self.edge = edge
        self.range = range
        
        guard self.id != id else { return }
        
        self.id = id
        updateValue()
        
        let publisher = ScrollSubscriptionStore.shared
            .offsetChangedSubject
            .filter { $0 == id }
            .map { _ in () }
            .eraseToAnyPublisher()
        
        subscriber = publisher.sink { [weak self] _ in
            self?.updateValue()
        }
    }
    
    private var edge: Edge? = nil
    private var id: AnyHashable? = nil
    private var range: ClosedRange<CGFloat> = -CGFloat.infinity...CGFloat.infinity
    private var subscriber: AnyCancellable?
    
    private func updateValue() {
        let edgeOffset: CGFloat = if let id, let edge, let offset = ScrollSubscriptionStore.shared[offset: id] {
            offset[edge]
        } else {
            .zero
        }
        
        let newValue = min(max(edgeOffset, range.lowerBound), range.upperBound)
        
        if value != newValue {
            value = newValue
        }
    }
}


internal class BaseScrollOffsetState {
    static func build() -> BaseScrollOffsetState? {
        if #available(iOS 17, macOS 14, tvOS 17, visionOS 1, *) {
            ScrollOffsetState()
        } else {
            nil
        }
    }
}
