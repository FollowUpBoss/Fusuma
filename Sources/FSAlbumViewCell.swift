//
//  FSAlbumViewCell.swift
//  Fusuma
//
//  Created by Yuta Akizuki on 2015/11/14.
//  Copyright © 2015年 ytakzk. All rights reserved.
//

import UIKit
import Photos

final class FSAlbumViewCell: UICollectionViewCell {
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var checkmarkImageView: UIImageView! {
        didSet {
            checkmarkImageView.isHidden = true
        }
    }

    var selectedLayer = CALayer()

    var image: UIImage? {
        didSet {
            UIView.transition(with: self.imageView, duration: 0.2, options: [.allowUserInteraction, .allowAnimatedContent, .transitionCrossDissolve], animations: {
                self.imageView.image = self.image
            }, completion: nil)
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        isSelected = false
        selectedLayer.backgroundColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.4).cgColor
    }

    override var isSelected : Bool {
        didSet {
            if selectedLayer.superlayer == imageView.layer {
                selectedLayer.removeFromSuperlayer()
                checkmarkImageView.isHidden = true
            }

            if isSelected {
                selectedLayer.frame = imageView.bounds
                imageView.layer.addSublayer(selectedLayer)
                checkmarkImageView.isHidden = false
            }
        }
    }
}
