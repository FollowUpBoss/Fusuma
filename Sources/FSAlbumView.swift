//
//  FSAlbumView.swift
//  Fusuma
//
//  Created by Yuta Akizuki on 2015/11/14.
//  Copyright © 2015年 ytakzk. All rights reserved.
//

import UIKit
import Photos

public protocol FSAlbumViewDelegate: class {
    // Returns height ratio of crop image. e.g) 4:3 -> 7.5
    func getCropHeightRatio() -> CGFloat

    func albumViewCameraRollUnauthorized()
    func albumViewCameraRollAuthorized()
    func albumbSelectionLimitReached()
    func albumShouldEnableDoneButton(isEnabled: Bool)
}

final class FSAlbumView: UIView, UICollectionViewDataSource, UICollectionViewDelegate, PHPhotoLibraryChangeObserver, UIGestureRecognizerDelegate {

    @IBOutlet weak var collectionView: UICollectionView!

    weak var delegate: FSAlbumViewDelegate? = nil
    var allowMultipleSelection = false
    var photoSelectionLimit = 1
    var autoSelectFirstImage = false

    private var images: PHFetchResult<PHAsset>!
    private var imageManager: PHCachingImageManager?
    private var previousPreheatRect: CGRect = .zero
    private let cellSize = CGSize(width: 100, height: 100)

    var phAsset: PHAsset!

    var selectedImages: [UIImage] = []
    var selectedAssets: [PHAsset] = []

    // Variables for calculating the position
    enum Direction {
        case scroll
        case stop
        case up
        case down
    }

    private var imaginaryCollectionViewOffsetStartPosY: CGFloat = 0.0

    private var cropBottomY: CGFloat  = 0.0
    private var dragStartPos: CGPoint = CGPoint.zero
    private let dragDiff: CGFloat     = 20.0

    static func instance() -> FSAlbumView {
        return UINib(nibName: "FSAlbumView", bundle: Bundle(for: self.classForCoder())).instantiate(withOwner: self, options: nil)[0] as! FSAlbumView
    }

    func initialize() {
        guard images == nil else { return }

        isHidden = false

        collectionView.register(UINib(nibName: "FSAlbumViewCell", bundle: Bundle(for: self.classForCoder)), forCellWithReuseIdentifier: "FSAlbumViewCell")
        collectionView.backgroundColor = fusumaBackgroundColor
        collectionView.allowsMultipleSelection = allowMultipleSelection

        // Never load photos Unless the user allows to access to photo album
        checkPhotoAuth()

        // Sorting condition
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]

        images = PHAsset.fetchAssets(with: .image, options: options)

        if images.count > 0 {
            if autoSelectFirstImage == true {
                changeImage(images[0])
                collectionView.reloadData()
                collectionView.selectItem(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: UICollectionView.ScrollPosition())
            } else {
                updateImageViewOnly(images[0])
                collectionView.reloadData()
            }
        }

        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        if PHPhotoLibrary.authorizationStatus() == PHAuthorizationStatus.authorized {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    // MARK: - UICollectionViewDelegate Protocol

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "FSAlbumViewCell", for: indexPath) as! FSAlbumViewCell

        let currentTag = cell.tag + 1
        cell.tag = currentTag

        let asset = images[(indexPath as NSIndexPath).item]

        imageManager?.requestImage(for: asset,
                                        targetSize: cellSize,
                                        contentMode: .aspectFill,
                                        options: nil) { (result, info) in
                                            if cell.tag == currentTag {
                                                cell.image = result
                                            }
        }

        return cell
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return images == nil ? 0 : images.count
    }

    @objc func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: IndexPath) -> CGSize {
        let width = (collectionView.frame.width - 3) / 3
        return CGSize(width: width, height: width)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if !allowMultipleSelection {
            selectedImages.removeAll()
            selectedAssets.removeAll()
        }

        if photoSelectionLimit > 0 && selectedImages.count + 1 <= photoSelectionLimit {
            changeImage(images[(indexPath as NSIndexPath).row])
            delegate?.albumShouldEnableDoneButton(isEnabled: true)
        } else {
            delegate?.albumbSelectionLimitReached()
            collectionView.deselectItem(at: indexPath, animated: true)
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        let asset = images[(indexPath as NSIndexPath).item]
        let selectedAsset = selectedAssets.enumerated().filter ({ $1 == asset }).first

        if let selected = selectedAsset {
            selectedImages.remove(at: selected.offset)
            selectedAssets.remove(at: selected.offset)
        }

        if selectedImages.count > 0 {
            delegate?.albumShouldEnableDoneButton(isEnabled: true)
        } else {
            delegate?.albumShouldEnableDoneButton(isEnabled: false)
        }

        return true
    }


    // MARK: - ScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == collectionView {
            updateCachedAssets()
        }
    }

    //MARK: - PHPhotoLibraryChangeObserver

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async {
            guard let collectionChanges = changeInstance.changeDetails(for: self.images) else {
                return
            }

            self.selectedImages.removeAll()
            self.selectedAssets.removeAll()

            self.images = collectionChanges.fetchResultAfterChanges

            let collectionView = self.collectionView!

            if !collectionChanges.hasIncrementalChanges ||
                collectionChanges.hasMoves {
                collectionView.reloadData()
            } else {
                collectionView.performBatchUpdates({
                    if let removedIndexes = collectionChanges.removedIndexes, removedIndexes.count != 0 {
                        collectionView.deleteItems(at: removedIndexes.aapl_indexPathsFromIndexesWithSection(0))
                    }

                    if let insertedIndexes = collectionChanges.insertedIndexes, insertedIndexes.count != 0 {
                        collectionView.insertItems(at: insertedIndexes.aapl_indexPathsFromIndexesWithSection(0))
                    }

                    if let changedIndexes = collectionChanges.changedIndexes, changedIndexes.count != 0 {
                        collectionView.reloadItems(at: changedIndexes.aapl_indexPathsFromIndexesWithSection(0))
                    }
                }, completion: nil)
            }

            self.resetCachedAssets()
        }
    }
}

internal extension UICollectionView {
    func aapl_indexPathsForElementsInRect(_ rect: CGRect) -> [IndexPath] {
        let allLayoutAttributes = self.collectionViewLayout.layoutAttributesForElements(in: rect)
        if (allLayoutAttributes?.count ?? 0) == 0 {return []}

        var indexPaths: [IndexPath] = []
        indexPaths.reserveCapacity(allLayoutAttributes!.count)

        for layoutAttributes in allLayoutAttributes! {
            let indexPath = layoutAttributes.indexPath
            indexPaths.append(indexPath)
        }

        return indexPaths
    }
}

internal extension IndexSet {
    func aapl_indexPathsFromIndexesWithSection(_ section: Int) -> [IndexPath] {
        var indexPaths: [IndexPath] = []
        indexPaths.reserveCapacity(self.count)

        (self as NSIndexSet).enumerate({idx, stop in
            indexPaths.append(IndexPath(item: idx, section: section))
        })

        return indexPaths
    }
}

private extension FSAlbumView {
    func changeImage(_ asset: PHAsset) {
        DispatchQueue.global(qos: .default).async(execute: {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            self.imageManager?.requestImage(for: asset,
                                            targetSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                                            contentMode: .aspectFill,
                                            options: options) {
                                                result, info in
                                                
                                                if let result = result,
                                                    !self.selectedAssets.contains(asset) {
                                                    
                                                    self.selectedAssets.append(asset)
                                                    self.selectedImages.append(result)
                                                }
            }
        })
    }

    func updateImageViewOnly(_ asset: PHAsset) {

        DispatchQueue.global(qos: .default).async(execute: {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            self.imageManager?.requestImage(for: asset, targetSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight), contentMode: .aspectFill, options: options) { result, info in

            }
        })
    }

    // Check the status of authorization for PHPhotoLibrary
    func checkPhotoAuth() {
        PHPhotoLibrary.requestAuthorization { (status) -> Void in
            switch status {
            case .authorized:
                self.imageManager = PHCachingImageManager()

                if let images = self.images, images.count > 0 {
                    self.changeImage(images[0])
                }

                DispatchQueue.main.async {
                    self.delegate?.albumViewCameraRollAuthorized()
                }
            case .restricted, .denied:
                DispatchQueue.main.async(execute: { () -> Void in
                    self.delegate?.albumViewCameraRollUnauthorized()
                })
            default:
                break
            }
        }
    }

    // MARK: - Asset Caching

    func resetCachedAssets() {
        imageManager?.stopCachingImagesForAllAssets()
        previousPreheatRect = CGRect.zero
    }

    func updateCachedAssets() {
        guard let collectionView = self.collectionView else { return }

        var preheatRect = collectionView.bounds
        preheatRect = preheatRect.insetBy(dx: 0.0, dy: -0.5 * preheatRect.height)

        let delta = abs(preheatRect.midY - self.previousPreheatRect.midY)

        if delta > collectionView.bounds.height / 3.0 {
            var addedIndexPaths: [IndexPath]   = []
            var removedIndexPaths: [IndexPath] = []

            self.computeDifferenceBetweenRect(
                self.previousPreheatRect,
                andRect: preheatRect,
                removedHandler: { removedRect in
                    let indexPaths = self.collectionView.aapl_indexPathsForElementsInRect(removedRect)
                    removedIndexPaths += indexPaths
                },
                addedHandler: { addedRect in
                    let indexPaths = self.collectionView.aapl_indexPathsForElementsInRect(addedRect)
                    addedIndexPaths += indexPaths
                }
            )

            let assetsToStartCaching = assetsAtIndexPaths(addedIndexPaths)
            let assetsToStopCaching = assetsAtIndexPaths(removedIndexPaths)

            imageManager?.startCachingImages(for: assetsToStartCaching,
                                             targetSize: cellSize,
                                             contentMode: .aspectFill,
                                             options: nil)

            imageManager?.stopCachingImages(for: assetsToStopCaching,
                                            targetSize: cellSize,
                                            contentMode: .aspectFill,
                                            options: nil)

            previousPreheatRect = preheatRect
        }
    }

    func computeDifferenceBetweenRect(_ oldRect: CGRect, andRect newRect: CGRect, removedHandler: (CGRect) -> Void, addedHandler: (CGRect) -> Void) {
        if newRect.intersects(oldRect) {
            let oldMaxY = oldRect.maxY
            let oldMinY = oldRect.minY
            let newMaxY = newRect.maxY
            let newMinY = newRect.minY

            if newMaxY > oldMaxY {
                let rectToAdd = CGRect(x: newRect.origin.x, y: oldMaxY, width: newRect.size.width, height: (newMaxY - oldMaxY))
                addedHandler(rectToAdd)
            }

            if oldMinY > newMinY {
                let rectToAdd = CGRect(x: newRect.origin.x, y: newMinY, width: newRect.size.width, height: (oldMinY - newMinY))
                addedHandler(rectToAdd)
            }

            if newMaxY < oldMaxY {
                let rectToRemove = CGRect(x: newRect.origin.x, y: newMaxY, width: newRect.size.width, height: (oldMaxY - newMaxY))
                removedHandler(rectToRemove)
            }

            if oldMinY < newMinY {
                let rectToRemove = CGRect(x: newRect.origin.x, y: oldMinY, width: newRect.size.width, height: (newMinY - oldMinY))
                removedHandler(rectToRemove)
            }
        } else {
            addedHandler(newRect)
            removedHandler(oldRect)
        }
    }

    func assetsAtIndexPaths(_ indexPaths: [IndexPath]) -> [PHAsset] {
        if indexPaths.count == 0 { return [] }

        var assets: [PHAsset] = []
        assets.reserveCapacity(indexPaths.count)

        for indexPath in indexPaths {
            let asset = images[(indexPath as NSIndexPath).item]
            assets.append(asset)
        }

        return assets
    }
}
