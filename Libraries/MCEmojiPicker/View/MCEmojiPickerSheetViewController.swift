// The MIT License (MIT)
//
// Copyright © 2024 Daniel Szabo
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import UIKit

public final class MCEmojiPickerSheetViewController: UIViewController {

    // MARK: - Public Properties

    /// Delegate for selecting an emoji object.
    public weak var delegate: MCEmojiPickerDelegate?

    /// Inset from the sourceView border.
    ///
    /// The default value of this property is `0`.
    public var horizontalInset: CGFloat = 0

    /// A boolean value that determines whether the screen will be hidden after the emoji is selected.
    ///
    /// If this property's value is `true`, the EmojiPicker will be dismissed after the emoji is selected.
    /// If you want EmojiPicker not to dismissed after emoji selection, you must set this property to `false`.
    /// The default value of this property is `true`.
    public var isDismissAfterChoosing: Bool = true

    /// Color for the selected emoji category.
    ///
    /// The default value of this property is `.systemBlue`.
    public var selectedEmojiCategoryTintColor: UIColor? {
        didSet {
            guard let selectedEmojiCategoryTintColor = selectedEmojiCategoryTintColor else { return }
            emojiPickerView.selectedEmojiCategoryTintColor = selectedEmojiCategoryTintColor
        }
    }

    /// Feedback generator style. To turn off, set `nil` to this parameter.
    ///
    /// The default value of this property is `.light`.
    public var feedBackGeneratorStyle: UIImpactFeedbackGenerator.FeedbackStyle? = .light {
        didSet {
            guard let feedBackGeneratorStyle = feedBackGeneratorStyle else {
                generator = nil
                return
            }
            generator = UIImpactFeedbackGenerator(style: feedBackGeneratorStyle)
        }
    }

    // MARK: - Private Properties

    private var generator: UIImpactFeedbackGenerator? = UIImpactFeedbackGenerator(style: .light)
    private var viewModel: MCEmojiPickerViewModelProtocol = MCEmojiPickerViewModel()

    private lazy var containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .popoverBackgroundColor
        return view
    }()

    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = "Search emoji"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        
        // Match the emoji picker's background color
        searchBar.backgroundColor = .clear
        if #available(iOS 13.0, *) {
            searchBar.searchTextField.backgroundColor = .secondarySystemGroupedBackground
        }
        
        // Remove the search bar's default background
        searchBar.backgroundImage = UIImage()
        searchBar.scopeBarBackgroundImage = UIImage()
        
        return searchBar
    }()

    private lazy var emojiPickerView: MCEmojiPickerView = {
        let categories = viewModel.emojiCategories.map { $0.type }
        let pickerView = MCEmojiPickerView(categoryTypes: categories, delegate: self)
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        return pickerView
    }()

    private lazy var dismissButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.addTarget(self, action: #selector(dismissSheet), for: .touchUpInside)
        button.tintColor = .secondaryLabel
        button.isHidden = true // Hidden by default, shown only on macOS
        return button
    }()

    // MARK: - Initializers

    public init() {
        super.init(nibName: nil, bundle: nil)
        setupSheetPresentationStyle()
        bindViewModel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Life Cycle

    public override func loadView() {
        view = containerView
        setupViews()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupSheetPresentationStyle()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.post(name: .MCEmojiPickerDidDisappear, object: nil)
    }

    // MARK: - Private Methods

    private func bindViewModel() {
        viewModel.selectedEmoji.bind { [unowned self] emoji in
            guard let emoji = emoji else { return }
            feedbackImpactOccurred()
            delegate?.didGetEmoji(emoji: emoji.string)
            if isDismissAfterChoosing {
                dismiss(animated: true, completion: nil)
            }
        }
        viewModel.selectedEmojiCategoryIndex.bind { [unowned self] categoryIndex in
            self.emojiPickerView.updateSelectedCategoryIcon(with: categoryIndex)
        }
        viewModel.searchText.bind { [unowned self] _ in
            // Update the emoji picker view with new categories
            let categories = viewModel.emojiCategories.map { $0.type }
            emojiPickerView.updateCategories(categories)
            // Force reload of collection view data to show updated emojis
            emojiPickerView.collectionView.reloadData()
        }
    }

    private func setupViews() {
        containerView.addSubview(searchBar)
        containerView.addSubview(emojiPickerView)
        containerView.addSubview(dismissButton)
        
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchBar.leadingAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            
            emojiPickerView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            emojiPickerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            emojiPickerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            emojiPickerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            dismissButton.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor, constant: 8),
            dismissButton.trailingAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            dismissButton.widthAnchor.constraint(equalToConstant: 24),
            dismissButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func setupSheetPresentationStyle() {
        modalPresentationStyle = .formSheet
        if #available(iOS 15, *) {
            if UIDevice.current.userInterfaceIdiom == .phone {
                sheetPresentationController?.detents = [.medium(), .large()]
                sheetPresentationController?.prefersGrabberVisible = true
            } else {
                // macOS specific setup
                sheetPresentationController?.detents = [.large()]
                sheetPresentationController?.prefersGrabberVisible = true
                dismissButton.isHidden = false
            }
        }
    }

    @objc private func dismissSheet() {
        dismiss(animated: true)
    }
}

// MARK: - EmojiPickerViewDelegate

extension MCEmojiPickerSheetViewController: MCEmojiPickerViewDelegate {
    func didChoiceEmojiCategory(at index: Int) {
        updateCurrentSelectedEmojiCategoryIndex(with: index)
    }

    func numberOfSections() -> Int {
        viewModel.numberOfSections()
    }

    func numberOfItems(in section: Int) -> Int {
        viewModel.numberOfItems(in: section)
    }

    func emoji(at indexPath: IndexPath) -> MCEmoji {
        viewModel.emoji(at: indexPath)
    }

    func sectionHeaderName(for section: Int) -> String {
        viewModel.sectionHeaderName(for: section)
    }

    func getCurrentSelectedEmojiCategoryIndex() -> Int {
        viewModel.selectedEmojiCategoryIndex.value
    }

    func updateCurrentSelectedEmojiCategoryIndex(with index: Int) {
        viewModel.selectedEmojiCategoryIndex.value = index
    }

    func getEmojiPickerFrame() -> CGRect {
        presentationController?.presentedView?.frame ?? view.frame
    }

    func updateEmojiSkinTone(_ skinToneRawValue: Int, in indexPath: IndexPath) {
        viewModel.selectedEmoji.value = viewModel.updateEmojiSkinTone(
            skinToneRawValue,
            in: indexPath
        )
    }

    func feedbackImpactOccurred() {
        generator?.impactOccurred()
    }

    func didChoiceEmoji(_ emoji: MCEmoji?) {
        viewModel.selectedEmoji.value = emoji
    }
}

// MARK: - UISearchBarDelegate

extension MCEmojiPickerSheetViewController: UISearchBarDelegate {
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        viewModel.searchText.value = searchText
    }
    
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        viewModel.searchText.value = ""
        searchBar.resignFirstResponder()
    }
}
