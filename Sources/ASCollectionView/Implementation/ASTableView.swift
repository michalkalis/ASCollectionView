// ASCollectionView. Created by Apptek Studios 2019

import Combine
import SwiftUI

@available(iOS 13.0, *)
public typealias ASTableViewSection = ASSection

@available(iOS 13.0, *)
public struct ASTableView<SectionID: Hashable>: UIViewControllerRepresentable, ContentSize
{
	// MARK: Type definitions

	public typealias Section = ASTableViewSection<SectionID>

	public typealias OnScrollCallback = ((_ contentOffset: CGPoint, _ contentSize: CGSize) -> Void)
	public typealias OnReachedBottomCallback = (() -> Void)

	// MARK: Key variables

	public var sections: [Section]
	public var style: UITableView.Style
    public var editMode: Bool = false

	// MARK: Private vars set by public modifiers

	internal var onScrollCallback: OnScrollCallback?
	internal var onReachedBottomCallback: OnReachedBottomCallback?
    
    internal var scrollPositionSetter: Binding<ASTableViewScrollPosition?>?

	internal var scrollIndicatorEnabled: Bool = true
	internal var contentInsets: UIEdgeInsets = .zero

	internal var separatorsEnabled: Bool = true

	internal var onPullToRefresh: ((_ endRefreshing: @escaping (() -> Void)) -> Void)?

	internal var alwaysBounce: Bool = false
	internal var animateOnDataRefresh: Bool = true

	// MARK: Environment variables
	@Environment(\.invalidateCellLayout) var invalidateParentCellLayout // Call this if using content size binding (nested inside another ASCollectionView)

	// Other
	var contentSizeTracker: ContentSizeTracker?

	public func makeUIViewController(context: Context) -> AS_TableViewController
	{
		context.coordinator.parent = self

		let tableViewController = AS_TableViewController(style: style)
		tableViewController.coordinator = context.coordinator

		context.coordinator.tableViewController = tableViewController
		context.coordinator.updateTableViewSettings(tableViewController.tableView)

		context.coordinator.setupDataSource(forTableView: tableViewController.tableView)
		return tableViewController
	}

	public func updateUIViewController(_ tableViewController: AS_TableViewController, context: Context)
	{
		context.coordinator.parent = self
		context.coordinator.updateTableViewSettings(tableViewController.tableView)
		context.coordinator.updateContent(tableViewController.tableView, transaction: context.transaction)
		context.coordinator.configureRefreshControl(for: tableViewController.tableView)
#if DEBUG
		debugOnly_checkHasUniqueSections()
#endif
	}

	public func makeCoordinator() -> Coordinator
	{
		Coordinator(self)
	}

#if DEBUG
	func debugOnly_checkHasUniqueSections()
	{
		var sectionIDs: Set<SectionID> = []
		var conflicts: Set<SectionID> = []
		sections.forEach {
			let (inserted, _) = sectionIDs.insert($0.id)
			if !inserted
			{
				conflicts.insert($0.id)
			}
		}
		if !conflicts.isEmpty
		{
			print("ASTABLEVIEW: The following section IDs are used more than once, please use unique section IDs to avoid unexpected behaviour:", conflicts)
		}
	}
#endif

	public class Coordinator: NSObject, ASTableViewCoordinator, UITableViewDelegate, UITableViewDataSourcePrefetching, UITableViewDragDelegate, UITableViewDropDelegate
	{
		var parent: ASTableView
		weak var tableViewController: AS_TableViewController?

		var dataSource: ASDiffableDataSourceTableView<SectionID>?

		let cellReuseID = UUID().uuidString
		let supplementaryReuseID = UUID().uuidString

		// MARK: Private tracking variables

		private var hasDoneInitialSetup = false

		typealias Cell = ASTableViewCell

		init(_ parent: ASTableView)
		{
			self.parent = parent
		}

		func itemID(for indexPath: IndexPath) -> ASCollectionViewItemUniqueID?
		{
			guard
				let sectionID = sectionID(fromSectionIndex: indexPath.section)
			else { return nil }
			return parent.sections[safe: indexPath.section]?.dataSource.getItemID(for: indexPath.item, withSectionID: sectionID)
		}

		func sectionID(fromSectionIndex sectionIndex: Int) -> SectionID?
		{
			parent.sections[safe: sectionIndex]?.id
		}

		func section(forItemID itemID: ASCollectionViewItemUniqueID) -> Section?
		{
			parent.sections
				.first(where: { $0.id.hashValue == itemID.sectionIDHash })
		}

		func updateTableViewSettings(_ tableView: UITableView)
		{
			assignIfChanged(tableView, \.backgroundColor, newValue: (parent.style == .plain) ? .clear : .systemGroupedBackground)
			assignIfChanged(tableView, \.separatorStyle, newValue: parent.separatorsEnabled ? .singleLine : .none)
			assignIfChanged(tableView, \.contentInset, newValue: parent.contentInsets)
			assignIfChanged(tableView, \.alwaysBounceVertical, newValue: parent.alwaysBounce)
			assignIfChanged(tableView, \.showsVerticalScrollIndicator, newValue: parent.scrollIndicatorEnabled)
			assignIfChanged(tableView, \.showsHorizontalScrollIndicator, newValue: parent.scrollIndicatorEnabled)
			assignIfChanged(tableView, \.keyboardDismissMode, newValue: .onDrag)

            assignIfChanged(tableView, \.allowsSelection, newValue: true)
            assignIfChanged(tableView, \.allowsMultipleSelectionDuringEditing, newValue: true)
            assignIfChanged(tableView, \.allowsSelectionDuringEditing, newValue: true)
            assignIfChanged(tableView, \.isEditing, newValue: parent.editMode)
            
            
            if assignIfChanged(tableView, \.allowsMultipleSelection, newValue: parent.editMode) {
                if !parent.editMode {
                    tableView.allowsSelection = false; tableView.allowsSelection = true //Remove the old selection
                }
                updateSelectionBindings(tableView)
            }
		}
        
        func isIndexPathSelected(_ indexPath: IndexPath) -> Bool {
            tableViewController?.tableView.indexPathsForSelectedRows?.contains(indexPath) ?? false
        }

		func setupDataSource(forTableView tv: UITableView)
		{
			tv.delegate = self
			tv.prefetchDataSource = self

			tv.dragDelegate = self
			tv.dropDelegate = self
			tv.dragInteractionEnabled = true

			tv.register(Cell.self, forCellReuseIdentifier: cellReuseID)
			tv.register(ASTableViewSupplementaryView.self, forHeaderFooterViewReuseIdentifier: supplementaryReuseID)

			dataSource = .init(tableView: tv)
			{ [weak self] tableView, indexPath, itemID in
				guard let self = self else { return nil }
				guard
					let cell = tableView.dequeueReusableCell(withIdentifier: self.cellReuseID, for: indexPath) as? Cell
				else { return nil }
				cell.tableViewController = self.tableViewController

				guard let section = self.parent.sections[safe: indexPath.section] else { return cell }

				cell.backgroundColor = (self.parent.style == .plain || section.disableDefaultTheming) ? .clear : .secondarySystemGroupedBackground

				cell.separatorInset = section.tableViewSeparatorInsets ?? UIEdgeInsets(top: 0, left: UITableView.automaticDimension, bottom: 0, right: UITableView.automaticDimension)

                cell.isSelected = self.isIndexPathSelected(indexPath)
                
                cell.setContent(itemID: itemID, content: section.dataSource.content(forItemID: itemID, isSelected: cell.isSelected))
                cell.skipNextRefresh = true // Avoid setting this again when we refresh old cells in a moment
                
                cell.disableSwiftUIDropInteraction = section.dataSource.dropEnabled
                cell.disableSwiftUIDragInteraction = section.dataSource.dragEnabled
                
				cell.hostingController.invalidateCellLayoutCallback = { [weak self, weak cell] animated in
					self?.invalidateLayout(animated: animated, cell: cell)
				}
				cell.hostingController.tableViewScrollToCellCallback = { [weak self] position in
					self?.scrollToRow(indexPath: indexPath, position: position)
				}

				return cell
			}
            
            dataSource?.onDelete = { [weak self] indexPath in
                self?.onDeleteAction(indexPath: indexPath, completionHandler: {_ in })
            }
            dataSource?.onMove = { [weak self] from, to in
                self?.onMoveAction(from: from, to: to)
            }
		}

		func populateDataSource(animated: Bool = true, transaction: Transaction? = nil)
		{
			guard hasDoneInitialSetup else { return }
			let snapshot = ASDiffableDataSourceSnapshot(sections:
				parent.sections.map {
					ASDiffableDataSourceSnapshot.Section(id: $0.id, elements: $0.itemIDs)
				}
			)
            dataSource?.applySnapshot(snapshot, animated: animated) {
                if let scrollPositionToSet = self.parent.scrollPositionSetter?.wrappedValue
                {
                    switch scrollPositionToSet {
                    case .indexPath(let indexPath):
                        self.tableViewController?.tableView.scrollToRow(at: indexPath, at: .none, animated: animated)
                    case .top:
                        let contentInsets = self.tableViewController?.tableView.contentInset ?? .zero
                        self.tableViewController?.tableView.setContentOffset(CGPoint(x: 0, y: contentInsets.top), animated: animated)
                    case .bottom:
                        let contentSize = self.tableViewController?.tableView.contentSizePlusInsets ?? .zero
                        self.tableViewController?.tableView.scrollRectToVisible(CGRect(origin: .init(x: 0, y: contentSize.height), size: .zero), animated: animated)
                    }
                    DispatchQueue.main.async {
                        self.parent.scrollPositionSetter?.wrappedValue = nil
                    }
                }
            }
            tableViewController.map { updateSelectionBindings($0.tableView) }
            refreshVisibleCells(transaction: transaction, updateAll: false)
			tableViewController.map { self.didUpdateContentSize($0.tableView.contentSize) }
		}

		func updateContent(_ tv: UITableView, transaction: Transaction?)
		{
			guard hasDoneInitialSetup else { return }

			let transactionAnimationEnabled = (transaction?.animation != nil) && !(transaction?.disablesAnimations ?? false)
			populateDataSource(animated: parent.animateOnDataRefresh && transactionAnimationEnabled, transaction: transaction)

			dataSource?.updateCellSizes(animated: transactionAnimationEnabled)
		}

        func refreshVisibleCells(transaction: Transaction?, updateAll: Bool = true)
		{
			guard let tv = tableViewController?.tableView else { return }
			for case let cell as Cell in tv.visibleCells
			{
				guard
					let itemID = cell.itemID,
					let section = self.section(forItemID: itemID)
				else { continue }
                if cell.skipNextRefresh && !updateAll {
                    cell.skipNextRefresh = false
                } else {
                    cell.setContent(itemID: itemID, content: section.dataSource.content(forItemID: itemID, isSelected: cell.isSelected))
                    cell.disableSwiftUIDropInteraction = section.dataSource.dropEnabled
                    cell.disableSwiftUIDragInteraction = section.dataSource.dragEnabled
                }
			}

			for case let supplementaryView as ASTableViewSupplementaryView in tv.subviews
			{
				guard
					let supplementaryID = supplementaryView.supplementaryID,
					let section = parent.sections.first(where: { $0.id.hashValue == supplementaryID.sectionIDHash })
				else { continue }
                supplementaryView.setContent(supplementaryID: supplementaryID, content: section.dataSource.content(supplementaryID: supplementaryID))

			}
		}

		func invalidateLayout(animated: Bool, cell: ASTableViewCell?)
		{
			dataSource?.updateCellSizes(animated: animated)
		}

		func scrollToRow(indexPath: IndexPath, position: UITableView.ScrollPosition = .none)
		{
			tableViewController?.tableView.scrollToRow(at: indexPath, at: position, animated: true)
		}

		func onMoveToParent()
		{
			guard !hasDoneInitialSetup else { return }

			hasDoneInitialSetup = true
			populateDataSource(animated: false)
			tableViewController.map { checkIfReachedBottom($0.tableView) }
		}

		func onMoveFromParent() {
            hasDoneInitialSetup = false
            dataSource?.didDisappear()
        }

		// MARK: Function for updating contentSize binding

		var lastContentSize: CGSize = .zero
		func didUpdateContentSize(_ size: CGSize)
		{
			guard let tv = tableViewController?.tableView, tv.contentSize != lastContentSize, tv.contentSize.height != 0 else { return }
			let firstSize = lastContentSize == .zero
			lastContentSize = tv.contentSize
			parent.contentSizeTracker?.contentSize = size
			DispatchQueue.main.async {
				self.parent.invalidateParentCellLayout?(!firstSize)
			}
		}

		func configureRefreshControl(for tv: UITableView)
		{
			guard parent.onPullToRefresh != nil else
			{
				if tv.refreshControl != nil
				{
					tv.refreshControl = nil
				}
				return
			}
			if tv.refreshControl == nil
			{
				let refreshControl = UIRefreshControl()
				refreshControl.addTarget(self, action: #selector(tableViewDidPullToRefresh), for: .valueChanged)
				tv.refreshControl = refreshControl
			}
		}

		@objc
		public func tableViewDidPullToRefresh()
		{
			guard let tableView = tableViewController?.tableView else { return }
			let endRefreshing: (() -> Void) = { [weak tableView] in
				tableView?.refreshControl?.endRefreshing()
			}
			parent.onPullToRefresh?(endRefreshing)
		}

		public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath)
		{
			parent.sections[safe: indexPath.section]?.dataSource.onAppear(indexPath)
		}

		public func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath)
		{
			parent.sections[safe: indexPath.section]?.dataSource.onDisappear(indexPath)
		}

		public func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int)
		{
//			guard let view = (view as? ASTableViewSupplementaryView) else { return }
		}

		public func tableView(_ tableView: UITableView, didEndDisplayingHeaderView view: UIView, forSection section: Int)
		{
//			guard let view = (view as? ASTableViewSupplementaryView) else { return }
		}

		public func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int)
		{
//			guard let view = (view as? ASTableViewSupplementaryView) else { return }
		}

		public func tableView(_ tableView: UITableView, didEndDisplayingFooterView view: UIView, forSection section: Int)
		{
//			guard let view = (view as? ASTableViewSupplementaryView) else { return }
		}

		public func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath])
		{
			let itemIDsToPrefetchBySection: [Int: [IndexPath]] = Dictionary(grouping: indexPaths) { $0.section }
			itemIDsToPrefetchBySection.forEach
			{
				parent.sections[safe: $0.key]?.dataSource.prefetch($0.value)
			}
		}

		public func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath])
		{
			let itemIDsToCancelPrefetchBySection: [Int: [IndexPath]] = Dictionary(grouping: indexPaths) { $0.section }
			itemIDsToCancelPrefetchBySection.forEach
			{
				parent.sections[safe: $0.key]?.dataSource.cancelPrefetch($0.value)
			}
		}

		// MARK: Swipe actions

		public func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration?
		{
			guard parent.sections[safe: indexPath.section]?.dataSource.supportsDelete(at: indexPath) == true else { return nil }
			let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completionHandler in
				self?.onDeleteAction(indexPath: indexPath, completionHandler: completionHandler)
			}
			return UISwipeActionsConfiguration(actions: [deleteAction])
		}
        

		public func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle
		{
            if parent.sections[safe: indexPath.section]?.dataSource.supportsDelete(at: indexPath) ?? false {
                return .delete
            }
            return .none
		}

		private func onDeleteAction(indexPath: IndexPath, completionHandler: (Bool) -> Void)
		{
			parent.sections[safe: indexPath.section]?.dataSource.onDelete(indexPath: indexPath, completionHandler: completionHandler)
		}
        
        
        private func onMoveAction(from: IndexPath, to: IndexPath) {
            guard let sourceSection = parent.sections[safe: from.section],
                  let destinationSection = parent.sections[safe: to.section]
            else { return }
            if from.section == to.section {
                sourceSection.dataSource.applyMove(from: from.item, to: to.item)
            } else {
                if let item = sourceSection.dataSource.getDragItem(for: from) {
                    sourceSection.dataSource.applyRemove(atOffsets: [from.item])
                    destinationSection.dataSource.applyInsert(items: [item], at: to.item)
                }
            }
        }

		// MARK: Cell Selection
        
        

		public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
		{
            if parent.editMode {
                updateContent(tableView, transaction: nil)
            } else {
                tableView.deselectRow(at: indexPath, animated: true)
                parent.sections[safe: indexPath.section]?.dataSource.didSingleSelect(index: indexPath.item)
            }
		}

		public func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath)
		{
			updateContent(tableView, transaction: nil)
		}

		func updateSelectionBindings(_ tableView: UITableView)
		{
			let selected = tableView.allowsSelection ? (tableView.indexPathsForSelectedRows ?? []) : []
			let selectionBySection = Dictionary(grouping: selected) { $0.section }
				.mapValues
			{
				Set($0.map { $0.item })
			}
			parent.sections.enumerated().forEach { offset, section in
				section.dataSource.updateSelection(selectionBySection[offset] ?? [])
			}
		}

		public func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath?
		{
            if parent.editMode {
                if let selectedRows = tableView.indexPathsForSelectedRows, selectedRows.contains(indexPath) {
                    tableView.deselectRow(at: indexPath, animated: false)
                    return nil
                }
                guard parent.sections[safe: indexPath.section]?.dataSource.shouldSelect(indexPath) ?? false else
                {
                    return nil
                }
                return indexPath
            } else if parent.sections[safe: indexPath.section]?.dataSource.allowSingleSelection == true {
                return indexPath
            }
            return nil
		}

		public func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath?
		{
			guard parent.sections[safe: indexPath.section]?.dataSource.shouldDeselect(indexPath) ?? true else
			{
				return nil
			}
			return indexPath
		}

        
        public func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
            if parent.editMode {
                return parent.sections[safe: indexPath.section]?.dataSource.shouldSelect(indexPath) ?? false
            } else {
                return parent.sections[safe: indexPath.section]?.dataSource.allowSingleSelection ?? false
            }
        }
        

		public func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem]
		{
			guard !indexPath.isEmpty else { return [] }
			guard let dragItem = parent.sections[safe: indexPath.section]?.dataSource.getDragItem(for: indexPath) else { return [] }
			return [dragItem]
		}

		func canDrop(at indexPath: IndexPath) -> Bool
		{
			guard !indexPath.isEmpty else { return false }
			return parent.sections[safe: indexPath.section]?.dataSource.dropEnabled ?? false
		}

		public func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal
		{
			if tableView.hasActiveDrag
			{
				if let destination = destinationIndexPath
				{
					guard canDrop(at: destination) else
					{
						return UITableViewDropProposal(operation: .cancel)
					}
				}
				return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
			}
			else
			{
				return UITableViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
			}
		}

		public func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator)
		{
			guard
				let destinationIndexPath = coordinator.destinationIndexPath,
				!destinationIndexPath.isEmpty,
				let destinationSection = parent.sections[safe: destinationIndexPath.section]
			else { return }

			guard canDrop(at: destinationIndexPath) else { return }

			guard let oldSnapshot = dataSource?.currentSnapshot else { return }
			var dragSnapshot = oldSnapshot

			switch coordinator.proposal.operation
			{
			case .move:
				guard destinationSection.dataSource.reorderingEnabled else { return }
				let itemsBySourceSection = Dictionary(grouping: coordinator.items) { item -> Int? in
					if let sourceIndex = item.sourceIndexPath, !sourceIndex.isEmpty
					{
						return sourceIndex.section
					}
					else
					{
						return nil
					}
				}

				let sourceSections = itemsBySourceSection.keys.sorted { a, b in
					guard let a = a else { return false }
					guard let b = b else { return true }
					return a < b
				}

				var itemsToInsert: [UITableViewDropItem] = []

				for sourceSectionIndex in sourceSections
				{
					guard let items = itemsBySourceSection[sourceSectionIndex] else { continue }

					if
						let sourceSectionIndex = sourceSectionIndex,
						let sourceSection = parent.sections[safe: sourceSectionIndex]
					{
						guard sourceSection.dataSource.reorderingEnabled else { continue }

						let sourceIndices = items.compactMap { $0.sourceIndexPath?.item }

						// Remove from source section
						dragSnapshot.removeItems(fromSectionIndex: sourceSectionIndex, atOffsets: IndexSet(sourceIndices))
						sourceSection.dataSource.applyRemove(atOffsets: IndexSet(sourceIndices))
					}

					// Add to insertion array (regardless whether sourceSection is nil)
					itemsToInsert.append(contentsOf: items)
				}

				let itemsToInsertIDs: [ASCollectionViewItemUniqueID] = itemsToInsert.compactMap { item in
					if let sourceIndexPath = item.sourceIndexPath
					{
						return oldSnapshot.sections[sourceIndexPath.section].elements[sourceIndexPath.item].differenceIdentifier
					}
					else
					{
						return destinationSection.dataSource.getItemID(for: item.dragItem, withSectionID: destinationSection.id)
					}
				}
				let safeDestinationIndex = min(destinationIndexPath.item, dragSnapshot.sections[destinationIndexPath.section].elements.endIndex)
				dragSnapshot.insertItems(itemsToInsertIDs, atSectionIndex: destinationIndexPath.section, atOffset: destinationIndexPath.item)
				destinationSection.dataSource.applyInsert(items: itemsToInsert.map { $0.dragItem }, at: safeDestinationIndex)

			case .copy:
				destinationSection.dataSource.applyInsert(items: coordinator.items.map { $0.dragItem }, at: destinationIndexPath.item)

			default: break
			}

			dataSource?.applySnapshot(dragSnapshot, animated: false)
			refreshVisibleCells(transaction: nil)
            if let dragItem = coordinator.items.first, let destination = coordinator.destinationIndexPath
            {
                if dragItem.sourceIndexPath != nil
                {
                    coordinator.drop(dragItem.dragItem, toRowAt: destination)
                }
            }
		}
        

		public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat
		{
			guard parent.sections[safe: section]?.supplementary(ofKind: UICollectionView.elementKindSectionHeader) != nil else
			{
				return CGFloat.leastNormalMagnitude
			}
			return UITableView.automaticDimension
		}

		public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat
		{
			guard parent.sections[safe: section]?.supplementary(ofKind: UICollectionView.elementKindSectionFooter) != nil else
			{
				return CGFloat.leastNormalMagnitude
			}
			return UITableView.automaticDimension
		}

		public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView?
		{
			guard let reusableView = tableView.dequeueReusableHeaderFooterView(withIdentifier: supplementaryReuseID) else { return nil }
			configureSupplementary(reusableView, supplementaryKind: UICollectionView.elementKindSectionHeader, forSection: section)
			return reusableView
		}

		public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView?
		{
			guard let reusableView = tableView.dequeueReusableHeaderFooterView(withIdentifier: supplementaryReuseID) else { return nil }
			configureSupplementary(reusableView, supplementaryKind: UICollectionView.elementKindSectionFooter, forSection: section)
			return reusableView
		}

		func configureSupplementary(_ cell: UITableViewHeaderFooterView, supplementaryKind: String, forSection sectionIndex: Int)
		{
			guard let reusableView = cell as? ASTableViewSupplementaryView
			else { return }

            guard let section = parent.sections[safe: sectionIndex] else { reusableView.setAsEmpty(supplementaryID: nil); return }
			let supplementaryID = ASSupplementaryCellID(sectionIDHash: section.id.hashValue, supplementaryKind: supplementaryKind)
			
            reusableView.setContent(supplementaryID: supplementaryID, content: section.dataSource.content(supplementaryID: supplementaryID))

		}

		// MARK: Context Menu Support

		public func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration?
		{
			guard !indexPath.isEmpty else { return nil }
			return parent.sections[safe: indexPath.section]?.dataSource.getContextMenu(for: indexPath)
		}

		public func scrollViewDidScroll(_ scrollView: UIScrollView)
		{
			parent.onScrollCallback?(scrollView.contentOffset, scrollView.contentSizePlusInsets)
			checkIfReachedBottom(scrollView)
		}

		var hasAlreadyReachedBottom: Bool = false
		func checkIfReachedBottom(_ scrollView: UIScrollView)
		{
			if (scrollView.contentSize.height - scrollView.contentOffset.y) <= scrollView.frame.size.height
			{
				if !hasAlreadyReachedBottom
				{
					hasAlreadyReachedBottom = true
					parent.onReachedBottomCallback?()
				}
			}
			else
			{
				hasAlreadyReachedBottom = false
			}
		}
	}
}

@available(iOS 13.0, *)
protocol ASTableViewCoordinator: AnyObject
{
	func onMoveToParent()
	func onMoveFromParent()
	func didUpdateContentSize(_ size: CGSize)
}

@available(iOS 13.0, *)
public enum ASTableViewScrollPosition
{
    case top
    case bottom
    case indexPath(_: IndexPath)
}